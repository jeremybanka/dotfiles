-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices

-- For example, changing the color scheme:
config.color_schemes = {
  ['Custom'] = {
    background = '#fff',
    foreground = '#222',
    -- Overrides the cell background color when the current cell is occupied by the
  -- cursor and the cursor style is set to Block
  cursor_bg = '#777',
  -- Overrides the text color when the current cell is occupied by the cursor
  cursor_fg = 'white',
  -- Specifies the border color of the cursor when the cursor style is set to Block,
  -- or the color of the vertical or horizontal bar when the cursor style is set to
  -- Bar or Underline.
  cursor_border = '#777',

  -- the foreground color of selected text
  selection_fg = 'black',
  -- the background color of selected text
  selection_bg = '#fd0',

  -- The color of the scrollbar "thumb"; the portion that represents the current viewport
  scrollbar_thumb = '#222222',

  -- The color of the split lines between panes
  split = '#444444',

  ansi = {
    'white', --black
    '#700', --red
    '#050', --green
    '#540', --yellow
    '#349', --blue
    '#60a', --cyan
    '#069', --magenta
    '#ccc', --white
  },
  brights = {
    '#777', --gray
    '#c00', --red
    '#080', --green
    '#a80', --yellow
    '#03f', --blue
    '#90f', --cyan
    '#0af', --magenta
    'white', --white
  },

  -- Arbitrary colors of the palette in the range from 16 to 255
  indexed = { [136] = '#af8700' },

  -- Since: 20220319-142410-0fcdea07
  -- When the IME, a dead key or a leader key are being processed and are effectively
  -- holding input pending the result of input composition, change the cursor
  -- to this color to give a visual cue about the compose state.
  compose_cursor = 'orange',

  -- Colors for copy_mode and quick_select
  -- available since: 20220807-113146-c2fee766
  -- In copy_mode, the color of the active text is:
  -- 1. copy_mode_active_highlight_* if additional text was selected using the mouse
  -- 2. selection_* otherwise
  copy_mode_active_highlight_bg = { AnsiColor = 'Black' },
  -- use `AnsiColor` to specify one of the ansi color palette values
  -- (index 0-15) using one of the names "Black", "Maroon", "Green",
  --  "Olive", "Navy", "Purple", "Teal", "Silver", "Grey", "Red", "Lime",
  -- "Yellow", "Blue", "Fuchsia", "Aqua" or "White".
  copy_mode_active_highlight_fg = { Color = '#ffffff' },
  copy_mode_inactive_highlight_bg = {AnsiColor = 'Black' },
  copy_mode_inactive_highlight_fg = {  Color = '#fd0' },

  quick_select_label_bg = { Color = 'peru' },
  quick_select_label_fg = { Color = '#ffffff' },
  quick_select_match_bg = { AnsiColor = 'Navy' },
  quick_select_match_fg = { Color = '#ffffff' },
  }
}
config.color_scheme = 'Custom'
config.font_size = 17
config.window_decorations = 'RESIZE'

config.hide_tab_bar_if_only_one_tab = true

-- and finally, return the configuration to wezterm
return config