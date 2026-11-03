//with(obj_netclient)
//{
//	if(!disnet_connect(ip, port))
//	{
//		global.errorCode = 0;
//		room_goto(room_message);
//		return;
//	}
//}

var _r = "";

try { _r += "status: [" + string(disnet_ios_status()) + "]\n"; }
catch(_e) { _r += "status FAILED: " + string(_e.message) + "\n"; }

try { var _c = net_dn_connect("127.0.0.1", 8606); _r += "connect -> " + string(_c) + "\n"; }
catch(_e) { _r += "connect FAILED: " + string(_e.message) + "\n"; }

try { _r += "status after: [" + string(disnet_ios_status()) + "]"; }
catch(_e) { _r += "status2 FAILED: " + string(_e.message); }

show_message_async(_r);