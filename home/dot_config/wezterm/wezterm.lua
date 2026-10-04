local wezterm = require 'wezterm'

local scheme_light = 'Catppuccin Latte'
local scheme_dark = 'Catppuccin Mocha'

local appearance = wezterm.gui and wezterm.gui.get_appearance() or 'Dark'

return {
	-- Remote hosts lack wezterm terminfo; xterm-256color is the portable fallback
	term = 'xterm-256color',
	color_scheme = appearance:find 'Dark' and scheme_dark or scheme_light,
	font_size = 12,
	default_prog = { "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", "-NoLogo" }
}
