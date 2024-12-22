-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
-- Import plenary.job
local Job = require("plenary.job")

-- Function to get the current macOS appearance
local function get_appearance()
  local result = Job:new({
    command = "defaults",
    args = { "read", "-g", "AppleInterfaceStyle" },
  }):sync()

  -- If the result is empty, it's in light mode
  if next(result) == nil then
    return "Light"
  else
    return result[1]
  end
end

-- Set the color scheme based on the appearance
local appearance = get_appearance()
if appearance == "Dark" then
  vim.cmd("colorscheme gruvbox")
else
  vim.cmd("colorscheme solarized")
end
vim.cmd([[
  highlight LazyUpdateNotification guifg=#ffffff guibg=#000000
  highlight LazyUpdateTitle guifg=#ffffff guibg=#000000
]])

-- Automatically set the working directory to the current file's directory
vim.api.nvim_exec(
  [[
  autocmd BufEnter * silent! lcd %:p:h
]],
  false
)

-- init.lua example for toggling neo-tree
vim.api.nvim_set_keymap("n", "<leader>e", ":Neotree toggle<CR>", { noremap = true, silent = true })

-- Set the leader key to space
vim.g.mapleader = " "
