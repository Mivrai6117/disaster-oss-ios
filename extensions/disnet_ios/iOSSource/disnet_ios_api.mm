#include "disnet_ios_api.h"
#include "disnet_core.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DNIOS_DEFAULT_PORT 8606
#define DNIOS_MAX_SEND     2048
#define DNIOS_B64_LEN(n)   ((((n) + 2) / 3) * 4)

static const char B64_TABLE[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

size_t dnios_base64_encode(const uint8_t *in, size_t n, char *out, size_t out_cap)
{
	size_t need = DNIOS_B64_LEN(n);
	if (out_cap < need + 1)
		return 0;

	size_t o = 0;
	size_t i = 0;
	for (; i + 2 < n; i += 3)
	{
		uint32_t v = ((uint32_t)in[i] << 16) | ((uint32_t)in[i + 1] << 8) | in[i + 2];
		out[o++] = B64_TABLE[(v >> 18) & 63];
		out[o++] = B64_TABLE[(v >> 12) & 63];
		out[o++] = B64_TABLE[(v >> 6) & 63];
		out[o++] = B64_TABLE[v & 63];
	}

	if (n - i == 1)
	{
		uint32_t v = (uint32_t)in[i] << 16;
		out[o++] = B64_TABLE[(v >> 18) & 63];
		out[o++] = B64_TABLE[(v >> 12) & 63];
		out[o++] = '=';
		out[o++] = '=';
	}
	else if (n - i == 2)
	{
		uint32_t v = ((uint32_t)in[i] << 16) | ((uint32_t)in[i + 1] << 8);
		out[o++] = B64_TABLE[(v >> 18) & 63];
		out[o++] = B64_TABLE[(v >> 12) & 63];
		out[o++] = B64_TABLE[(v >> 6) & 63];
		out[o++] = '=';
	}

	out[o] = '\0';
	return o;
}

static int b64_value(int c)
{
	if (c >= 'A' && c <= 'Z') return c - 'A';
	if (c >= 'a' && c <= 'z') return c - 'a' + 26;
	if (c >= '0' && c <= '9') return c - '0' + 52;
	if (c == '+') return 62;
	if (c == '/') return 63;
	return -1;
}

/* Accepts padded or unpadded input and ignores whitespace.
 * Returns the decoded size, or -1 on a bad character / overflow. */
long dnios_base64_decode(const char *in, uint8_t *out, size_t out_cap)
{
	uint32_t acc = 0;
	int bits = 0;
	size_t o = 0;

	for (; *in; in++)
	{
		unsigned char c = (unsigned char)*in;

		if (c == '=')
			break;

		if (c == ' ' || c == '\n' || c == '\r' || c == '\t')
			continue;

		int v = b64_value(c);
		if (v < 0)
			return -1;

		acc = (acc << 6) | (uint32_t)v;
		bits += 6;

		if (bits >= 8)
		{
			bits -= 8;
			if (o >= out_cap)
				return -1;

			out[o++] = (uint8_t)((acc >> bits) & 0xFF);
		}
	}

	return (long)o;
}

/* diagnostics, see dnios_status() */
static unsigned g_connect_calls = 0;
static double   g_last_rc       = -1.0;
static char     g_parse_err[96] = "";

static double connect_impl(const char *hostport)
{
	if (!hostport || !hostport[0])
	{
		snprintf(g_parse_err, sizeof(g_parse_err), "empty host:port");
		return 0.0;
	}

	char host[256];
	long port = DNIOS_DEFAULT_PORT;

	const char *colon = strrchr(hostport, ':');
	size_t host_len = colon ? (size_t)(colon - hostport) : strlen(hostport);
	if (host_len == 0 || host_len >= sizeof(host))
	{
		snprintf(g_parse_err, sizeof(g_parse_err), "bad host in '%.60s'", hostport);
		return 0.0;
	}

	memcpy(host, hostport, host_len);
	host[host_len] = '\0';

	if (colon)
	{
		char *end = NULL;
		port = strtol(colon + 1, &end, 10);
		if (end == colon + 1 || *end != '\0' || port < 0 || port > 65535)
		{
			snprintf(g_parse_err, sizeof(g_parse_err), "bad port in '%.60s'", hostport);
			return 0.0;
		}
	}

	return disnet_core_connect(host, (double)port);
}

double dnios_connect(const char *hostport)
{
	g_connect_calls++;
	g_parse_err[0] = '\0';

	g_last_rc = connect_impl(hostport);
	return g_last_rc;
}

const char *dnios_status(void)
{
	static char out[560];

	snprintf(out, sizeof(out),
		"dnios build=%s %s connect_calls=%u last_rc=%.0f parse_err=%s core_err=%s %s",
		__DATE__, __TIME__, g_connect_calls, g_last_rc,
		g_parse_err[0] ? g_parse_err : "none", disnet_core_last_error(),
		disnet_core_bg_stats());

	return out;
}

const char *dnios_poll(void)
{
	/* "3:" + base64(256 bytes) + NUL */
	static char out[2 + DNIOS_B64_LEN(DISNET_BUFFER_SIZE) + 16];

	uint8_t raw[DISNET_BUFFER_SIZE];
	size_t n = 0;
	int ev = disnet_core_poll(raw, sizeof(raw), &n);

	out[0] = '\0';

	switch (ev)
	{
		case DISNET_EVENT_CONNECTED:
			snprintf(out, sizeof(out), "1");
			break;

		case DISNET_EVENT_DISCONNECTED:
		{
			uint32_t code = 0;
			if (n >= 4)
				code = (uint32_t)raw[0] | ((uint32_t)raw[1] << 8) | ((uint32_t)raw[2] << 16) | ((uint32_t)raw[3] << 24);

			snprintf(out, sizeof(out), "2:%u", (unsigned)code);
			break;
		}

		case DISNET_EVENT_RELIABLE:
		case DISNET_EVENT_UNRELIABLE:
			out[0] = (char)('0' + ev);
			out[1] = ':';
			dnios_base64_encode(raw, n, out + 2, sizeof(out) - 2);
			break;

		default:
			break;
	}

	return out;
}

double dnios_send(const char *message)
{
	/* "<r>:<base64>"  r = 1 reliable, 0 unreliable, 2 unreliable and remembered as the keepalive packet */
	if (!message || (message[0] != '0' && message[0] != '1' && message[0] != '2') || message[1] != ':')
		return 0.0;

	uint8_t raw[DNIOS_MAX_SEND];
	long n = dnios_base64_decode(message + 2, raw, sizeof(raw));
	if (n <= 0)
		return 0.0;

	if (message[0] == '2')
		disnet_core_set_keepalive(raw, (size_t)n);

	disnet_core_send(raw, (size_t)n, message[0] == '1');
	return 1.0;
}

void dnios_background_begin(void)
{
	disnet_core_bg_start();
}

void dnios_background_end(void)
{
	disnet_core_bg_stop();
}

double dnios_reset(void)
{
	disnet_core_reset();
	return 0.0;
}
