with(obj_netclient)
{
	if(!net_dn_connect(ip, port))
	{
		global.errorCode = 0;
		room_goto(room_message);
		return;
	}
}