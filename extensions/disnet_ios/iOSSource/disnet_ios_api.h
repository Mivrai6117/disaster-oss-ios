/*
 * String-only interface for the iOS extension.
 *
 * Why this exists: on Windows/Android GameMaker passes buffer_get_address() to
 * the extension as a raw pointer. How that pointer is marshalled into an
 * Objective-C method on iOS is not documented, so this interface avoids
 * pointers entirely. Binary packets travel as base64 text, and every function
 * takes at most ONE argument (double or string) and returns a double or string.
 *
 * Message formats
 *   connect   "host:port"            e.g. "192.168.1.5:8606" (port optional, default 8606)
 *   send      "<r>:<base64>"         r = 1 reliable, 0 unreliable,
 *                                    2 unreliable AND remember it as the keepalive packet
 *                                    (resent every 500 ms while the app is in the background)
 *   poll ->   ""                     nothing happened
 *             "1"                    connected
 *             "2:<code>"             disconnected, <code> = server's DisconnectReason (decimal)
 *             "3:<base64>"           reliable packet received
 *             "4:<base64>"           unreliable packet received
 */
#ifndef DISNET_IOS_API_H
#define DISNET_IOS_API_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

double      dnios_connect(const char *hostport); /* 1.0 = attempt started */
const char *dnios_poll(void);                    /* never NULL; valid until next call */
double      dnios_send(const char *message);     /* 1.0 = accepted, 0.0 = malformed */
double      dnios_reset(void);                   /* always 0.0 */

/* Called by the Objective-C glue when the app resigns / becomes active. While "begun", a
 * thread keeps the connection alive and resends the keepalive packet. */
void        dnios_background_begin(void);
void        dnios_background_end(void);

/* Diagnostics: "dnios build=<date time> connect_calls=<n> last_rc=<r> parse_err=<..> core_err=<..>".
 * Never empty, so an empty result from the game means this code was never reached. */
const char *dnios_status(void);

/* exposed for the tests */
size_t dnios_base64_encode(const uint8_t *in, size_t n, char *out, size_t out_cap);
long   dnios_base64_decode(const char *in, uint8_t *out, size_t out_cap);

#ifdef __cplusplus
}
#endif

#endif /* DISNET_IOS_API_H */
