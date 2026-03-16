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
    background = dark and '#000000' or '#ffffff',
    foreground = dark and '#eeeeee' or '#222222',
    -- Overrides the cell background color when the current cell is occupied by the
    -- cursor and the cursor style is set to Block
    cursor_bg = dark and '#555555' or '#777777',
    -- Overrides the text color when the current cell is occupied by the cursor
    cursor_fg = dark and '#eeeeee' or '#ffffff',
    -- Specifies the border color of the cursor when the cursor style is set to Block,
    -- or the color of the vertical or horizontal bar when the cursor style is set to
    -- Bar or Underline.
    cursor_border = dark and '#555555' or '#777777',

    -- the foreground color of selected text
    selection_fg = dark and 'white' or 'black',
    -- the background color of selected text
    selection_bg = dark and '#200' or '#fd0',

    -- The color of the scrollbar "thumb"; the portion that represents the current viewport
    scrollbar_thumb = dark and '#222222' or '#444444',

    -- The color of the split lines between panes
    split = dark and '#555555' or '#777777',

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
config.font = wezterm.font('Theia 0.3.500')
config.window_decorations = 'RESIZE | MACOS_FORCE_ENABLE_SHADOW'
config.window_frame = {
  border_left_width = 1,
  border_right_width = 1,
  border_bottom_height = 1,
  border_top_height = 1,
  border_left_color = dark and '#080808' or '#ffffff',
  border_right_color = dark and '#080808' or '#ffffff',
  border_bottom_color = dark and '#080808' or '#ffffff',
  border_top_color = dark and '#080808' or '#ffffff',
  font_size = 12,
  font = wezterm.font { family = 'Noname Sans', weight = 600 },
  active_titlebar_bg = dark and '#181818' or '#6699cc',
  inactive_titlebar_bg = dark and '#181818' or '#dddddd',
}

config.window_background_opacity = .75
config.macos_window_background_blur = 15

config.colors = {
  tab_bar = {
    inactive_tab_edge = dark and '#181818' or '#6699cc',
    active_tab = {
      bg_color = dark and '#000000' or 'red',
      fg_color = dark and '#ffffff' or '#000000',
      intensity = 'Normal',
      underline = 'None',
      italic = false,
      strikethrough = false,
    },
    inactive_tab = {
      bg_color = dark and '#181818' or '#6699cc',
      fg_color = dark and '#bbbbbb' or '#ffffff',
    },
  },
}

config.hide_tab_bar_if_only_one_tab = true
-- config.show_close_tab_button_in_tabs = false -- still only available in nightly
config.show_new_tab_button_in_tab_bar = false
config.tab_and_split_indices_are_zero_based = true
local SOLID_LEFT_ARROW = wezterm.nerdfonts.pl_right_hard_divider
local SOLID_RIGHT_ARROW = wezterm.nerdfonts.pl_left_hard_divider

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
        { Background = { Color = dark and '#000000' or '#ffffff' } },
        { Text = ' ' .. title },
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