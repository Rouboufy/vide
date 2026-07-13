assert(type(_G.vide_enable_ide_mode) == 'function')
assert(type(_G.vide_disable_ide_mode) == 'function')
assert(type(_G.vide_ide_action) == 'function')

vim.cmd('enew!')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha beta', 'gamma' })
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

_G.vide_disable_ide_mode()
assert(vim.g.vide_ide_mode == false)
assert(vim.fn.maparg('<S-Left>', 'i') == '')
vim.cmd('qa!')
