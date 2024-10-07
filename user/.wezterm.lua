-- Pull in the wezterm API
local wezterm = require 'wezterm'

local function get_appearance()
  local handle = io.popen("defaults read -g AppleInterfaceStyle 2>/dev/null")
  if not handle then return 1 end
  local result = handle:read("*a")
  handle:close()

  -- If the result is empty, it's in light mode
  if result == "" then
    return 1
  else
    return 0
  end
end

local dark = get_appearance() == 0

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices

-- For example, changing the color scheme:
config.color_schemes = {
  ['Custom'] = {
    background = dark and '#000' or '#fff',
    foreground = dark and '#eee' or '#222',
    -- Overrides the cell background color when the current cell is occupied by the
  -- cursor and the cursor style is set to Block
  cursor_bg = dark and '#555' or '#777',
  -- Overrides the text color when the current cell is occupied by the cursor
  cursor_fg = dark and '#eee' or '#fff',
  -- Specifies the border color of the cursor when the cursor style is set to Block,
  -- or the color of the vertical or horizontal bar when the cursor style is set to
  -- Bar or Underline.
  cursor_border = dark and '#555' or '#777',

  -- the foreground color of selected text
  selection_fg = dark and 'white' or 'black',
  -- the background color of selected text
  selection_bg = dark and '#200' or '#fd0',

  -- The color of the scrollbar "thumb"; the portion that represents the current viewport
  scrollbar_thumb = dark and '#222222' or '#444444',

  -- The color of the split lines between panes
  split = dark and '#444444' or '#666666',

  ansi = dark and {
    '#333', -- black
    '#c55', -- red
    '#595', -- green
    '#dc3', -- yellow
    '#88f', -- blue
    '#c7f', -- magenta
    '#5af', -- cyan
    '#ddd', -- white
  } or {
    '#fff', --black
    '#700', --red
    '#050', --green
    '#540', --yellow
    '#349', --blue
    '#609', --magenta
    '#069', --cyan
    '#ccc', --white
  },
  brights = dark and {
    '#666', -- black
    '#f55', -- red
    '#5c5', -- green
    '#fc0', -- yellow
    '#67f', -- blue
    '#c5f', -- magenta
    '#3af', -- cyan
    '#fff', -- white
  } or {
    '#777', --gray
    '#c00', --red
    '#080', --green
    '#a80', --yellow
    '#03f', --blue
    '#90f', --magenta
    '#0af', --cyan
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
config.font_size = 13.5
config.font = wezterm.font('Theia 0.2.500')
config.window_decorations = 'RESIZE'
config.colors = {
  tab_bar = {
    -- The color of the inactive tab bar edge/divider
    inactive_tab_edge = '#222',
  },
}

config.window_frame = {
  -- The font used in the tab bar.
  -- Roboto Bold is the default; this font is bundled
  -- with wezterm.
  -- Whatever font is selected here, it will have the
  -- main font setting appended to it to pick up any
  -- fallback fonts you may have used there.
  font = wezterm.font { family = 'Fira Sans', weight = 600 },

  -- The size of the font in the tab bar.
  -- Default to 10.0 on Windows but 12.0 on other systems
  font_size = 10.5,

  -- The overall background color of the tab bar when
  -- the window is focused
  active_titlebar_bg = dark and '#222' or '#fff',

  -- The overall background color of the tab bar when
  -- the window is not focused
  inactive_titlebar_bg = dark and '#161616' or '#fff',
}

-- config.hide_tab_bar_if_only_one_tab = true
-- config.show_close_tab_button_in_tabs = false
config.show_new_tab_button_in_tab_bar = false
config.tab_and_split_indices_are_zero_based = true

-- The filled in variant of the < symbol
local SOLID_LEFT_ARROW = wezterm.nerdfonts.pl_right_hard_divider

-- The filled in variant of the > symbol
local SOLID_RIGHT_ARROW = wezterm.nerdfonts.pl_left_hard_divider
config.tab_bar_style = {}

-- This function returns the suggested title for a tab.
-- It prefers the title that was set via `tab:set_title()`
-- or `wezterm cli set-tab-title`, but falls back to the
-- title of the active pane in that tab.
function tab_title(tab_info)
  local title = tab_info.tab_title
  -- if the tab title is explicitly set, take that
  if title and #title > 0 then
    return title
  end
  -- Otherwise, use the title from the active pane
  -- in that tab
  return tab_info.active_pane.title
end

wezterm.on(
  'format-tab-title',
  function(tab, tabs, panes, config, hover, max_width)
    local title = tab_title(tab)
    if tab.is_active then
      return {
        { Background = { Color = dark and '#000' or '#fff' } },
        { Text = ' ' .. title .. ' ' },
      }
    end
    return title
  end
)

config.keys = {
  {
    key = 'LeftArrow',
    mods = 'ALT',
    action = wezterm.action.SendKey {
      key = 'b',
      mods = 'ALT',
    },
  },
  {
    key = 'RightArrow',
    mods = 'ALT',
    action = wezterm.action.SendKey {
      key = 'f',
      mods = 'ALT',
    },
  }
}

-- and finally, return the configuration to wezterm
return config