assert(vim.fn.exists(':VideOnboarding') == 2)
_G.open_vide_onboarding()
local buf = vim.api.nvim_get_current_buf()
assert(vim.bo[buf].filetype == 'vide-onboarding')
local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
for _, expected in ipairs({
  'Choose how editing should work', 'NORMAL', 'IDE', 'True color', 'Mouse',
  'Nerd Font', 'Clipboard', 'Shell', 'Six essentials', 'Ctrl+S',
  'Ctrl+F', 'Ctrl+Z', 'Ctrl+E', 'Ctrl+T', 'F11', 'language servers',
}) do
  assert(text:find(expected, 1, true), 'missing onboarding content: ' .. expected)
end
for _, key in ipairs({ 'n', 'i', 'l', 'q', '<Esc>' }) do
  assert(vim.fn.maparg(key, 'n', false, true).buffer == 1, 'missing onboarding key: ' .. key)
end
_G.vide_onboarding_choose('ide')
assert(vim.g.vide_ide_mode == true)
assert(vim.uv.fs_stat(vim.fn.stdpath('data') .. '/onboarding-complete'))
local settings = vim.fn.json_decode(table.concat(vim.fn.readfile(vim.fn.stdpath('data') .. '/settings.json'), '\n'))
assert(settings.mode == 'ide')
_G.open_vide_onboarding()
assert(vim.bo[vim.api.nvim_get_current_buf()].filetype == 'vide-onboarding')
_G.vide_onboarding_dismiss()
assert(vim.uv.fs_stat(vim.fn.stdpath('data') .. '/onboarding-complete'))
vim.cmd('qa!')
