draw_self();

if(os_type == os_ios && (global.errorCode == 4 || global.errorCode == 7))
{
	var _lines;
	if(global.errorCode == 7)
	{
		_lines = [
			"you were kicked for being inactive.",
			"ios pauses games in the background.",
			"stay in the game during a match."
		];
	}
	else
	{
		_lines = [
			"the connection to the server was lost.",
			"on ios this can happen if the app was",
			"in the background for too long."
		];
	}
	
	for(var i = 0; i < array_length(_lines); i++)
	{
		var _l = _lines[i];
		var _w = 0;
		for(var j = 1; j <= string_length(_l); j++)
		{
			_w += 6;
			if(string_pos(string_char_at(_l, j), "wmxn") > 0)
				_w += 2;
		}
		
		scr_text_spr(240 - _w / 2, 182 + i * 10, _l, c_ltgray);
	}
}