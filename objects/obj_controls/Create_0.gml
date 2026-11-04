depth = -1001;
isMobile = os_type == os_ios;
gamepadSupport = gamepad_is_supported();
prevScreenMode = 0;

if(isMobile)
	scr_controls_init_touch();
if(gamepadSupport)
	scr_controls_init_gamepad();
	
buttonSetProp = function(_btn,  _scale, _opacity)
{
	switch(_btn)
	{
		case 0:
			obj_config.jScale = _scale
			obj_config.jOpacity = _opacity;
			break;
			
		case 1:
			obj_config.bAScale = _scale
			obj_config.bAOpacity = _opacity;
			break;
			
		case 2:
			obj_config.bBScale = _scale
			obj_config.bBOpacity = _opacity;
			break;
			
		case 3:
			obj_config.bCScale = _scale
			obj_config.bCOpacity = _opacity;
			break;
			
		case 4:
			obj_config.bDScale = _scale
			obj_config.bDOpacity = _opacity;
			break;
			
		case 5:
			obj_config.bEScale = _scale
			obj_config.bEOpacity = _opacity;
			break;
			
		case 6:
			obj_config.bFScale = _scale
			obj_config.bFOpacity = _opacity;
			break;
			
		case 7:
			obj_config.bGScale = _scale
			obj_config.bGOpacity = _opacity;
			break;
			
		case 8:
			obj_config.bWScale = _scale
			obj_config.bWOpacity = _opacity;
			break;
			
	}
	
	obj_config.save();
}

buttonSetPos = function(_btn, _x, _y)
{
	switch(_btn)
	{
		case 0:
			obj_config.dpadX = _x;
			obj_config.dpadY = _y;
			break;
			
		case 1:
			obj_config.bAX = _x;
			obj_config.bAY = _y;
			break;
			
		case 2:
			obj_config.bBX = _x;
			obj_config.bBY = _y;
			break;
			
		case 3:
			obj_config.bCX = _x;
			obj_config.bCY = _y;
			break;
			
		case 4:
			obj_config.bDX = _x;
			obj_config.bDY = _y;
			break;
			
		case 5:
			obj_config.bEX = _x;
			obj_config.bEY = _y;
			break;
			
		case 6:
			obj_config.bFX = _x;
			obj_config.bFY = _y;
			break;
			
		case 7:
			obj_config.bGX = _x;
			obj_config.bGY = _y;
			break;
			
		case 8:
			obj_config.bWX = _x;
			obj_config.bWY = _y;
			break;
	}
	
	obj_config.save();
}

// Low-effects mode for old iPhones (below iOS 16). Defaults to ON if the version can't be read.
global.lowFx = false;
if(os_type == os_ios)
{
	global.lowFx = true;
	var _info = os_get_info();
	if(ds_map_exists(_info, "systemVersion"))
	{
		var _s = string(_info[? "systemVersion"]);
		var _p = string_pos(".", _s);
		var _major = string_digits(_p > 0 ? string_copy(_s, 1, _p - 1) : _s);
		if(string_length(_major) > 0)
			global.lowFx = real(_major) < 16;
	}
	ds_map_destroy(_info);
}