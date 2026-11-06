global.tcp_buffer = buffer_create(256, buffer_fixed, 1);
global.udp_buffer = buffer_create(256, buffer_fixed, 1);

function cpacket_tcp(type, passtrough = false)
{
	buffer_seek(global.tcp_buffer, buffer_seek_start, 0);
	buffer_write(global.tcp_buffer, buffer_u8, passtrough);
	buffer_write(global.tcp_buffer, buffer_u8, real(type));
	
	return global.tcp_buffer;
}

function cpacket_udp(type, passtrough = false)
{
	buffer_seek(global.udp_buffer, buffer_seek_start, 0);
	buffer_write(global.udp_buffer, buffer_u8, passtrough);
	buffer_write(global.udp_buffer, buffer_u8, real(type));
		
	return global.udp_buffer;	
}

function send_server_tcp(buffer)
{
	with(obj_netclient)
	{
		var size = buffer_tell(buffer);
		net_dn_send(buffer, size, true);
	}
}

function send_server_udp(buffer, keepalive = false)
{
	with(obj_netclient)
	{
		var size = buffer_tell(buffer);
		net_dn_send(buffer, size, false, keepalive);
	}
}

// ---------------------------------------------------------------------------
// Platform networking layer.
// Windows / Android / Linux keep calling the original disnet_* functions.
// iOS uses the string based disnet_ios_* functions (the iOS extension cannot
// take a raw buffer pointer): packets travel as base64 text, see
// disnet_ios_api.h in the disnet-ios package for the exact formats.
// ---------------------------------------------------------------------------
function net_dn_connect(host, _port)
{
	if(os_type == os_ios)
		return disnet_ios_connect(host + ":" + string(_port));

	return disnet_connect(host, _port);
}

function net_dn_reset()
{
	if(os_type == os_ios)
	{
		disnet_ios_reset();
		return;
	}

	disnet_reset();
}

function net_dn_send(buffer, size, reliable, keepalive = false)
{
	if(os_type == os_ios)
	{
		var mode = reliable ? "1:" : (keepalive ? "2:" : "0:");
		disnet_ios_send(mode + buffer_base64_encode(buffer, 0, size));
		return;
	}

	disnet_send(buffer_get_address(buffer), size, reliable);
}

/// Same contract as disnet_poll(): returns a DisnetEvent and leaves the
/// payload (or the u32 disconnect code) at the start of `buffer`.
function net_dn_poll(buffer)
{
	if(os_type != os_ios)
		return disnet_poll(buffer_get_address(buffer));

	var msg = disnet_ios_poll();
	if(msg == "")
		return DisnetEvent.NONE;

	var event = real(string_char_at(msg, 1));
	switch(event)
	{
		case DisnetEvent.DISCONNECTED:
			buffer_seek(buffer, buffer_seek_start, 0);
			buffer_write(buffer, buffer_u32, real(string_delete(msg, 1, 2)));
			break;

		case DisnetEvent.RELIABLE:
		case DisnetEvent.UNRELIABLE:
			var tmp = buffer_base64_decode(string_delete(msg, 1, 2));
			buffer_copy(tmp, 0, min(buffer_get_size(tmp), buffer_get_size(buffer)), buffer, 0);
			buffer_delete(tmp);
			break;
	}

	return event;
}

function buffer_read_s(buffer, type)
{
	var sz = buffer_sizeof(type);
	if(buffer_tell(buffer) + sz > buffer_get_size(buffer))
	{		
		return -1;
	}
	
	return buffer_read(buffer, type);
}
