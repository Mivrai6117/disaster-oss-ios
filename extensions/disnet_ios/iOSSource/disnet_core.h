/*
 * disnet_core - portable rebuild of the "disnet" networking extension used by
 * the Disaster 2D client. Behaviour was derived from the original Linux build
 * (libdisnet.so) and from the betterserver-oss server, so it is wire compatible:
 *
 *   - ENet client host: 1 peer, 2 channels, 5,000,000 B/s in and out
 *   - reliable packets   -> channel 0, ENET_PACKET_FLAG_RELIABLE
 *   - unreliable packets -> channel 1, no flags
 *   - poll() returns an event code and writes the payload to the caller's buffer
 *
 * Differences from the original (all hardening, none change the protocol):
 *   - poll() never writes more than the caller's buffer capacity
 *   - send() before a connection exists is ignored instead of crashing
 *   - failed sends free their packet
 *   - connect() drops any previous peer first
 */
#ifndef DISNET_CORE_H
#define DISNET_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Same numbering as DisnetEvent in net_wrapper.gml */
enum
{
	DISNET_EVENT_NONE         = 0,
	DISNET_EVENT_CONNECTED    = 1,
	DISNET_EVENT_DISCONNECTED = 2, /* payload: u32 little-endian disconnect code */
	DISNET_EVENT_RELIABLE     = 3,
	DISNET_EVENT_UNRELIABLE   = 4
};

/* Size of obj_netclient.buffer (buffer_create(256, buffer_fixed, 1)) */
#define DISNET_BUFFER_SIZE 256

#define DISNET_CHANNEL_RELIABLE   0
#define DISNET_CHANNEL_UNRELIABLE 1
#define DISNET_CHANNEL_COUNT      2
#define DISNET_BANDWIDTH          5000000

/* Background keepalive: largest packet that can be stored, and how often it is resent */
#define DISNET_KEEPALIVE_MAX 512
#define DISNET_KEEPALIVE_MS  500

/* Returns 1.0 on success, 0.0 on failure. Safe to call more than once. */
double disnet_core_init(void);

/* Why the last connect attempt failed ("none" if it did not). Never NULL. */
const char *disnet_core_last_error(void);

/* Disconnects and frees everything. */
void disnet_core_uninit(void);

/* Drops the current connection (if any) immediately. */
void disnet_core_reset(void);

/* Starts connecting. Accepts an IPv4 address or a host name.
 * Returns 1.0 if the attempt was started (completion arrives as an event). */
double disnet_core_connect(const char *address, double port);

/* Services the network once without blocking.
 * Returns one of DISNET_EVENT_*. For RELIABLE / UNRELIABLE / DISCONNECTED the
 * payload is copied to `out` (at most `out_cap` bytes) and its size stored in
 * `*out_len`. */
int disnet_core_poll(uint8_t *out, size_t out_cap, size_t *out_len);

/* Queues a packet. reliable != 0 -> channel 0 reliable, otherwise channel 1. */
void disnet_core_send(const uint8_t *data, size_t len, int reliable);

/* Remembers a packet (sent unreliably) that the background thread resends while the
 * game is frozen. The game refreshes it every frame with its latest position update.
 * Pass len 0 to clear. Cleared automatically by reset / connect. */
void disnet_core_set_keepalive(const uint8_t *data, size_t len);

/* Starts a thread that keeps servicing the connection (answers pings, collects reliable
 * events for the next poll) and resends the keepalive packet every DISNET_KEEPALIVE_MS.
 * Call when the game is about to freeze (iOS: app resigning active). Idempotent. */
void disnet_core_bg_start(void);

/* Stops that thread and waits for it. Call when the game resumes. Idempotent. */
void disnet_core_bg_stop(void);

/* One line of counters for debugging the keepalive (see README, "Diagnosing"). */
const char *disnet_core_bg_stats(void);

#ifdef __cplusplus
}
#endif

#endif /* DISNET_CORE_H */
