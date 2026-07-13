assert(type(_G.vide_enable_ide_mode) == 'function')
assert(type(_G.vide_disable_ide_mode) == 'function')
assert(type(_G.vide_ide_action) == 'function')
assert(type(_G.vide_close_buffer) == 'function')
assert(type(_G.vide_close_floating_windows) == 'function')
assert(vim.fn.maparg(' ot', 'n') ~= '', 'missing bottom terminal split mapping: <Space> o t')
assert(vim.fn.maparg(' oT', 'n') ~= '', 'missing vertical terminal split mapping: <Space> o T')

_G.open_help_menu()
vim.api.nvim_feedkeys('2', 'x', false)
local help_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
for _, expected in ipairs({
  '<Space> o t            Toggle Bottom Terminal Split',
  '<Space> o T            Toggle Vertical Terminal Split',
  '<C-w> s / <C-w> v      Horizontal / Vertical Editor Split',
}) do
  assert(help_text:find(expected, 1, true), 'missing help text: ' .. expected)
end
vim.api.nvim_win_close(0, true)

vim.cmd('enew!')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha beta', 'gamma' })

-- Repeating a global shortcut while a modified prompt-like float has focus
-- must not raise E37 or damage the edited file underneath it.
local edited_buffer = vim.api.nvim_get_current_buf()
local floating_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(floating_buffer, 0, -1, false, { 'query' })
vim.bo[floating_buffer].modified = true
local floating_window = vim.api.nvim_open_win(floating_buffer, true, {
  relative = 'editor', row = 1, col = 1, width = 20, height = 1, style = 'minimal',
})
_G.vide_close_floating_windows()
_G.vide_close_floating_windows()
assert(not vim.api.nvim_win_is_valid(floating_window))
assert(vim.api.nvim_get_current_buf() == edited_buffer)
assert(vim.bo[edited_buffer].modified == true)

_G.vide_enable_ide_mode()
assert(vim.g.vide_ide_mode == true)

for _, lhs in ipairs({ '<Esc>', '<Home>', '<End>', '<C-Left>', '<C-Right>', '<D-Left>', '<D-Right>',
    '<S-Left>', '<S-Right>', '<S-Home>', '<S-End>', '<C-S-Left>', '<C-S-Right>' }) do
  if lhs == '<Home>' or lhs == '<End>' then
    -- Neovim supplies these familiar defaults; the rest are IDE-owned.
    assert(vim.fn.maparg(lhs, 'i') == '')
  else
  assert(vim.fn.maparg(lhs, 'i') ~= '', 'missing insert mapping: ' .. lhs)
  end
end
for _, lhs in ipairs({ '<C-s>', '<C-z>', '<C-y>', '<C-a>', '<C-c>', '<C-x>', '<C-v>', '<C-f>', '<C-h>' }) do
  assert(vim.fn.maparg(lhs, 'i') ~= '', 'missing IDE shortcut: ' .. lhs)
end

_G.vide_ide_action('select_all')
assert(vim.api.nvim_get_mode().mode:match('[vV\22]'))
vim.cmd('normal! \27')
_G.vide_ide_action('undo')
_G.vide_ide_action('redo')

vim.cmd('stopinsert')
vim.fn.setreg('"', { 'pasted from IDE' }, 'l')
_G.vide_ide_action('paste')
assert(vim.api.nvim_get_current_line() == 'pasted from IDE')

local first_buffer = vim.api.nvim_get_current_buf()
_G.vide_ide_action('new')
assert(vim.api.nvim_get_current_buf() ~= first_buffer)
_G.vide_ide_action('previous_buffer')
assert(vim.api.nvim_get_current_buf() == first_buffer)
_G.vide_ide_action('next_buffer')
assert(vim.api.nvim_get_current_buf() ~= first_buffer)

local disposable_buffer = vim.api.nvim_get_current_buf()
assert(_G.vide_close_buffer(disposable_buffer) == true)
assert(not vim.api.nvim_buf_is_valid(disposable_buffer))
assert(vim.api.nvim_get_current_buf() == first_buffer)

_G.vide_disable_ide_mode()
assert(vim.g.vide_ide_mode == false)
assert(vim.fn.maparg('<S-Left>', 'i') == '')
vim.cmd('qa!')
