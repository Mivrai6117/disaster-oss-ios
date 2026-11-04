// iOS: the on-screen Return key types a newline into keyboard_string instead of sending Enter.
if(os_type == os_ios)
{
	if(!variable_instance_exists(id, "enterHold"))
		enterHold = 0;

	if(enterHold > 0)
	{
		enterHold--;
		if(enterHold == 0)
			keyboard_key_release(vk_enter);
	}
	else if(string_pos("\n", keyboard_string) > 0 || string_pos("\r", keyboard_string) > 0)
	{
		keyboard_string = string_replace_all(string_replace_all(keyboard_string, "\r", ""), "\n", "");
		keyboard_key_press(vk_enter);
		enterHold = 2;
	}
}



if(instance_exists(obj_level) && keyboard_check_pressed(global.KeyHide))
	global.showHud = !global.showHud;

if(isMobile)
	scr_controls_update_touch();
if(gamepadSupport)
	scr_controls_update_gamepad();
	
if(keyboard_check_pressed(vk_f4))
{
	if(window_get_fullscreen())
	{
		obj_config.screenMode = prevScreenMode;
		obj_config.applyRes();
		obj_config.save();
	}
	else
	{
		prevScreenMode = obj_config.screenMode;
		obj_config.screenMode = 3;
		obj_config.applyRes();
		obj_config.save();
	}
}