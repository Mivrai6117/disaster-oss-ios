#include "disnet_core.h"
#include "enet_unity.h"

#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static int      g_enet_ready = 0;
static ENetHost *g_host      = NULL;
static ENetPeer *g_peer      = NULL;

/* One lock protects the ENet host/peer, the event queue and the keepalive packet.
 * The game thread and the background keepalive thread never touch ENet at the same time. */
static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
#define LOCK()   pthread_mutex_lock(&g_mu)
#define UNLOCK() pthread_mutex_unlock(&g_mu)

/* Events collected by the background thread while the game is frozen. poll() hands them
 * out first. Only connect / disconnect / reliable events are kept: unreliable packets
 * received in the background are stale position updates, so they are dropped. */
#define QCAP 512
typedef struct { int type; size_t len; uint8_t data[DISNET_BUFFER_SIZE]; } QEvent;
static QEvent g_q[QCAP];
static int    g_qhead = 0;
static int    g_qcount = 0;

static void q_clear(void)
{
	g_qhead = 0;
	g_qcount = 0;
}

static int q_push(int type, const uint8_t *data, size_t len)
{
	if (g_qcount >= QCAP)
		return 0;

	QEvent *e = &g_q[(g_qhead + g_qcount) % QCAP];
	e->type = type;
	e->len = len > sizeof(e->data) ? sizeof(e->data) : len;
	if (e->len)
		memcpy(e->data, data, e->len);

	g_qcount++;
	return 1;
}

static int q_pop(uint8_t *out, size_t out_cap, size_t *out_len)
{
	if (g_qcount == 0)
		return DISNET_EVENT_NONE;

	QEvent *e = &g_q[g_qhead];
	size_t n = e->len > out_cap ? out_cap : e->len;
	if (out && n)
		memcpy(out, e->data, n);
	if (out_len)
		*out_len = n;

	int type = e->type;
	g_qhead = (g_qhead + 1) % QCAP;
	g_qcount--;
	return type;
}

/* Packet the background thread resends so the server keeps seeing activity. */
static uint8_t g_ka[DISNET_KEEPALIVE_MAX];
static size_t  g_ka_len = 0;

/* Why the last connect attempt failed, for diagnostics. "none" after a success. */
static char g_err[160] = "none";

static void set_err(const char *what)
{
	snprintf(g_err, sizeof(g_err), "%s", what);
}

static void set_err_errno(const char *what)
{
	snprintf(g_err, sizeof(g_err), "%s (errno %d: %s)", what, errno, strerror(errno));
}

const char *disnet_core_last_error(void)
{
	return g_err;
}

static double init_locked(void)
{
	if (g_host)
		return 1.0;

	if (!g_enet_ready)
	{
		if (enet_initialize() != 0)
		{
			set_err("enet_initialize failed");
			return 0.0;
		}

		g_enet_ready = 1;
	}

	/* client host: no bind address, 1 outgoing peer, 2 channels, 5 MB/s each way */
	errno = 0;
	g_host = enet_host_create(NULL, 1, DISNET_CHANNEL_COUNT, DISNET_BANDWIDTH, DISNET_BANDWIDTH);
	if (!g_host)
	{
		set_err_errno("enet_host_create failed");
		return 0.0;
	}

	return 1.0;
}

double disnet_core_init(void)
{
	LOCK();
	double r = init_locked();
	UNLOCK();
	return r;
}

/* caller holds the lock */
static void reset_locked(void)
{
	if (g_peer)
	{
		enet_peer_disconnect_now(g_peer, 0);
		g_peer = NULL;
	}

	q_clear();
	g_ka_len = 0;
}

void disnet_core_reset(void)
{
	LOCK();
	reset_locked();
	UNLOCK();
}

void disnet_core_uninit(void)
{
	disnet_core_bg_stop();

	LOCK();
	reset_locked();

	if (g_host)
	{
		enet_host_destroy(g_host);
		g_host = NULL;
	}

	if (g_enet_ready)
	{
		enet_deinitialize();
		g_enet_ready = 0;
	}
	UNLOCK();
}

static double connect_locked(const char *address, double port)
{
	if (!address || !address[0])
	{
		set_err("empty address");
		return 0.0;
	}

	if (port < 0.0 || port > 65535.0)
	{
		set_err("port out of range");
		return 0.0;
	}

	/* The game normally resets before reconnecting; make that unconditional. */
	reset_locked();

	if (init_locked() == 0.0)
		return 0.0; /* init already recorded the reason */

	ENetAddress addr;
	memset(&addr, 0, sizeof(addr));
	addr.port = (enet_uint16)(int)port;

	/* numeric IP first, then a DNS lookup - same order as the original */
	if (enet_address_set_host_ip(&addr, address) < 0)
	{
		if (enet_address_set_host(&addr, address) < 0)
		{
			snprintf(g_err, sizeof(g_err), "cannot resolve host '%.60s'", address);
			return 0.0;
		}
	}

	g_peer = enet_host_connect(g_host, &addr, DISNET_CHANNEL_COUNT, 0);
	if (!g_peer)
	{
		set_err("enet_host_connect returned NULL (no free peer)");
		return 0.0;
	}

	set_err("none");
	return 1.0;
}

double disnet_core_connect(const char *address, double port)
{
	LOCK();
	double r = connect_locked(address, port);
	UNLOCK();
	return r;
}

/* Turns one ENet event into a DISNET_EVENT_* code and copies its payload.
 * Destroys the packet. Caller holds the lock. */
static int translate_event(ENetEvent *ev, uint8_t *out, size_t out_cap, size_t *out_len)
{
	switch (ev->type)
	{
		case ENET_EVENT_TYPE_CONNECT:
			return DISNET_EVENT_CONNECTED;

		case ENET_EVENT_TYPE_DISCONNECT:
		{
			/* the server puts its DisconnectReason in the event data */
			g_peer = NULL;

			if (out && out_cap >= 4)
			{
				out[0] = (uint8_t)(ev->data & 0xFF);
				out[1] = (uint8_t)((ev->data >> 8) & 0xFF);
				out[2] = (uint8_t)((ev->data >> 16) & 0xFF);
				out[3] = (uint8_t)((ev->data >> 24) & 0xFF);

				if (out_len)
					*out_len = 4;
			}

			return DISNET_EVENT_DISCONNECTED;
		}

		case ENET_EVENT_TYPE_RECEIVE:
		{
			int result = (ev->packet->flags & ENET_PACKET_FLAG_RELIABLE)
				? DISNET_EVENT_RELIABLE
				: DISNET_EVENT_UNRELIABLE;

			size_t n = ev->packet->dataLength;
			if (n > out_cap)
				n = out_cap;

			if (out && n)
				memcpy(out, ev->packet->data, n);

			if (out_len)
				*out_len = n;

			enet_packet_destroy(ev->packet);
			return result;
		}

		default:
			return DISNET_EVENT_NONE;
	}
}

int disnet_core_poll(uint8_t *out, size_t out_cap, size_t *out_len)
{
	if (out_len)
		*out_len = 0;

	LOCK();

	/* anything the background thread collected while the game was frozen comes first */
	int result = q_pop(out, out_cap, out_len);

	if (result == DISNET_EVENT_NONE && g_host)
	{
		ENetEvent ev;
		if (enet_host_service(g_host, &ev, 0) > 0)
			result = translate_event(&ev, out, out_cap, out_len);
	}

	UNLOCK();
	return result;
}

void disnet_core_send(const uint8_t *data, size_t len, int reliable)
{
	LOCK();

	if (g_peer && data && len > 0)
	{
		ENetPacket *packet = enet_packet_create(data, len, reliable ? ENET_PACKET_FLAG_RELIABLE : 0);
		if (packet)
		{
			enet_uint8 channel = reliable ? DISNET_CHANNEL_RELIABLE : DISNET_CHANNEL_UNRELIABLE;
			if (enet_peer_send(g_peer, channel, packet) < 0)
				enet_packet_destroy(packet);
		}
	}

	UNLOCK();
}

void disnet_core_set_keepalive(const uint8_t *data, size_t len)
{
	LOCK();

	if (data && len > 0 && len <= sizeof(g_ka))
	{
		memcpy(g_ka, data, len);
		g_ka_len = len;
	}
	else
		g_ka_len = 0;

	UNLOCK();
}

/* ---- background keepalive ------------------------------------------------ */

static pthread_mutex_t g_ctl = PTHREAD_MUTEX_INITIALIZER; /* serialises start / stop */
static pthread_t       g_bg;
static int             g_bg_running = 0;
static volatile int    g_bg_stop    = 0;

static uint64_t now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000u + (uint64_t)(ts.tv_nsec / 1000000);
}

static void *bg_main(void *arg)
{
	(void)arg;
	uint64_t last_ka = now_ms();

	while (!g_bg_stop)
	{
		LOCK();

		if (g_host)
		{
			/* answers the server's pings and collects what it sends */
			ENetEvent ev;
			for (int guard = 0; guard < 64 && enet_host_service(g_host, &ev, 0) > 0; guard++)
			{
				uint8_t buf[DISNET_BUFFER_SIZE];
				size_t n = 0;
				int type = translate_event(&ev, buf, sizeof(buf), &n);

				if (type == DISNET_EVENT_CONNECTED || type == DISNET_EVENT_DISCONNECTED || type == DISNET_EVENT_RELIABLE)
					q_push(type, buf, n);
			}

			uint64_t now = now_ms();
			if (g_peer && g_peer->state == ENET_PEER_STATE_CONNECTED && g_ka_len > 0
				&& now - last_ka >= DISNET_KEEPALIVE_MS)
			{
				ENetPacket *packet = enet_packet_create(g_ka, g_ka_len, 0);
				if (packet && enet_peer_send(g_peer, DISNET_CHANNEL_UNRELIABLE, packet) < 0)
					enet_packet_destroy(packet);

				last_ka = now;
			}
		}

		UNLOCK();
		usleep(20 * 1000);
	}

	return NULL;
}

void disnet_core_bg_start(void)
{
	pthread_mutex_lock(&g_ctl);

	if (!g_bg_running)
	{
		g_bg_stop = 0;
		if (pthread_create(&g_bg, NULL, bg_main, NULL) == 0)
			g_bg_running = 1;
	}

	pthread_mutex_unlock(&g_ctl);
}

void disnet_core_bg_stop(void)
{
	pthread_mutex_lock(&g_ctl);

	if (g_bg_running)
	{
		g_bg_stop = 1;
		pthread_join(g_bg, NULL);
		g_bg_running = 0;
	}

	pthread_mutex_unlock(&g_ctl);
}
