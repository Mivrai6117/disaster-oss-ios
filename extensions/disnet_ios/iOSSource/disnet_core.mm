#include "disnet_core.h"
#include "enet_unity.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>

static int      g_enet_ready = 0;
static ENetHost *g_host      = NULL;
static ENetPeer *g_peer      = NULL;

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

double disnet_core_init(void)
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

void disnet_core_reset(void)
{
	if (g_peer)
	{
		enet_peer_disconnect_now(g_peer, 0);
		g_peer = NULL;
	}
}

void disnet_core_uninit(void)
{
	disnet_core_reset();

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
}

double disnet_core_connect(const char *address, double port)
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
	disnet_core_reset();

	if (disnet_core_init() == 0.0)
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

int disnet_core_poll(uint8_t *out, size_t out_cap, size_t *out_len)
{
	if (out_len)
		*out_len = 0;

	if (!g_host)
		return DISNET_EVENT_NONE;

	ENetEvent ev;
	if (enet_host_service(g_host, &ev, 0) <= 0)
		return DISNET_EVENT_NONE;

	switch (ev.type)
	{
		case ENET_EVENT_TYPE_CONNECT:
			return DISNET_EVENT_CONNECTED;

		case ENET_EVENT_TYPE_DISCONNECT:
		{
			/* the server puts its DisconnectReason in the event data */
			g_peer = NULL;

			if (out && out_cap >= 4)
			{
				out[0] = (uint8_t)(ev.data & 0xFF);
				out[1] = (uint8_t)((ev.data >> 8) & 0xFF);
				out[2] = (uint8_t)((ev.data >> 16) & 0xFF);
				out[3] = (uint8_t)((ev.data >> 24) & 0xFF);

				if (out_len)
					*out_len = 4;
			}

			return DISNET_EVENT_DISCONNECTED;
		}

		case ENET_EVENT_TYPE_RECEIVE:
		{
			int result = (ev.packet->flags & ENET_PACKET_FLAG_RELIABLE)
				? DISNET_EVENT_RELIABLE
				: DISNET_EVENT_UNRELIABLE;

			size_t n = ev.packet->dataLength;
			if (n > out_cap)
				n = out_cap;

			if (out && n)
				memcpy(out, ev.packet->data, n);

			if (out_len)
				*out_len = n;

			enet_packet_destroy(ev.packet);
			return result;
		}

		default:
			return DISNET_EVENT_NONE;
	}
}

void disnet_core_send(const uint8_t *data, size_t len, int reliable)
{
	if (!g_peer || !data || len == 0)
		return;

	ENetPacket *packet = enet_packet_create(data, len, reliable ? ENET_PACKET_FLAG_RELIABLE : 0);
	if (!packet)
		return;

	enet_uint8 channel = reliable ? DISNET_CHANNEL_RELIABLE : DISNET_CHANNEL_UNRELIABLE;
	if (enet_peer_send(g_peer, channel, packet) < 0)
		enet_packet_destroy(packet);
}
