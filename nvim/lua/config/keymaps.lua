-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
vim.keymap.set("n", "ya", ":%y+<CR>", { desc = "Yank all to system clipboard" })

-- jj as Esc in insert mode
vim.keymap.set("i", "jj", "<Esc>", { desc = "Esc" })

-- Disable arrow keys (force hjkl)
for _, key in ipairs({ "<Up>", "<Down>", "<Left>", "<Right>" }) do
  vim.keymap.set({ "n", "i", "v" }, key, "<Nop>", { desc = "Disabled arrow key" })
end
