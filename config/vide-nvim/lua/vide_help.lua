local VIM_MOTIONS = {
    "  ╭──────────────────────────────────────────────────────────────╮",
    "  │               ⚡  VIM MOTIONS REFERENCE CARD                │",
    "  ╰──────────────────────────────────────────────────────────────╯",
    "",
    "  ── MODES ──────────────────────────────────────────────────────",
    "  i / I      Insert mode (before cursor / at line start)",
    "  a / A      Append mode (after cursor / at line end)",
    "  o / O      Open new line below / above and insert",
    "  v / V      Visual mode / Visual Line mode",
    "  <C-v>      Visual Block mode (column editing)",
    "  Esc        Return to Normal mode",
    "  R          Replace mode (overwrite text)",
    "",
    "  ── NAVIGATION ─────────────────────────────────────────────────",
    "  h j k l    Left / Down / Up / Right",
    "  w / W      Jump to next word start (word / WORD)",
    "  e / E      Jump to next word end   (word / WORD)",
    "  b / B      Jump back word start    (word / WORD)",
    "  0 / ^      Start of line / First non-blank char",
    "  $          End of line",
    "  gg / G     First line / Last line of file",
    "  {N}G       Jump to line N (e.g. 42G)",
    "  <C-d>      Scroll down half a page (cursor stays centered)",
    "  <C-u>      Scroll up half a page   (cursor stays centered)",
    "  <C-f>/<C-b>  Scroll full page down / up",
    "  %          Jump to matching bracket/paren/brace",
    "  *          Search forward for word under cursor",
    "  #          Search backward for word under cursor",
    "  n / N      Next / Previous search match",
    "  ''         Jump back to previous position",
    "  zz         Center screen on cursor",
    "  zt / zb    Scroll so cursor is at Top / Bottom",
    "",
    "  ── TEXT OBJECTS ────────────────────────────────────────────────",
    "  iw / aw    Inner word / A word (incl. surrounding space)",
    "  i\" / a\"    Inside quotes / Including quotes",
    "  i( / a(    Inside parens / Including parens",
    "  i{ / a{    Inside braces / Including braces",
    "  i[ / a[    Inside brackets / Including brackets",
    "  it / at    Inside tag / Including tag (HTML/XML)",
    "  ip / ap    Inner paragraph / A paragraph",
    "  is / as    Inner sentence / A sentence",
    "",
    "  ── OPERATORS (combine with motion or text object) ───────────────",
    "  d{motion}  Delete  (e.g. dw, d$, dip, d3j)",
    "  c{motion}  Change  (delete + insert mode)",
    "  y{motion}  Yank    (copy)",
    "  >{motion}  Indent right",
    "  <{motion}  Indent left",
    "  ={motion}  Auto-indent",
    "  gU{motion} Uppercase",
    "  gu{motion} Lowercase",
    "  g~{motion} Toggle case",
    "",
    "  ── EDITING SHORTCUTS ───────────────────────────────────────────",
    "  x / X      Delete char under cursor / before cursor",
    "  s / S      Substitute char / whole line",
    "  dd / D     Delete line / Delete to end of line",
    "  yy / Y     Yank line / Yank to end of line",
    "  p / P      Paste after cursor / before cursor",
    "  u          Undo",
    "  <C-r>      Redo",
    "  .          Repeat last change",
    "  J          Join line below to current line",
    "  r{char}    Replace single character with {char}",
    "  ~          Toggle case of character under cursor",
    "  >>  /  <<  Indent / Unindent current line",
    "  =G         Auto-indent from cursor to end of file",
    "",
    "  ── SEARCH & REPLACE ────────────────────────────────────────────",
    "  /pattern   Search forward  (n=next, N=prev)",
    "  ?pattern   Search backward",
    "  :%s/old/new/g      Replace all in file",
    "  :%s/old/new/gc     Replace all with confirmation",
    "  :s/old/new/g       Replace all in current line",
    "",
    "  ── MARKS & JUMPS ───────────────────────────────────────────────",
    "  m{a-z}     Set local mark  (m{A-Z} for global mark)",
    "  `{mark}    Jump to exact mark position",
    "  '{mark}    Jump to mark's line start",
    "  <C-o>      Jump to previous location in jump list",
    "  <C-i>      Jump to next location in jump list",
    "",
    "  ── MACROS ──────────────────────────────────────────────────────",
    "  q{a-z}     Start recording macro into register {a-z}",
    "  q          Stop recording macro",
    "  @{a-z}     Replay macro from register {a-z}",
    "  @@         Repeat last macro",
    "  {N}@{a-z}  Replay macro N times",
    "",
    "  ── WINDOWS & SPLITS ────────────────────────────────────────────",
    "  <C-w>s     Horizontal split",
    "  <C-w>v     Vertical split",
    "  <C-w>h/j/k/l   Move between splits",
    "  <C-w>q     Close current split",
    "  <C-w>=     Equalize all split sizes",
    "  <C-w>|     Maximize current split width",
    "  <C-w>_     Maximize current split height",
    "",
    "  ── COMMAND MODE ────────────────────────────────────────────────",
    "  :w         Save file",
    "  :q         Quit",
    "  :wq / :x   Save and quit",
    "  :q!        Quit without saving",
    "  :e {file}  Open file",
    "  :bn / :bp  Next / Previous buffer",
    "  :bd        Delete (close) buffer",
    "  :noh       Clear search highlight",
    "  :set nu    Toggle line numbers",
    "  :!{cmd}    Run shell command",
}

local VIDE_KEYS = {
    "  ╭──────────────────────────────────────────────────────────────╮",
    "  │                ⚙  VIDE CUSTOM KEYBINDINGS                   │",
    "  ╰──────────────────────────────────────────────────────────────╯",
    "  Leader key = <Space>",
    "",
    "  ── VIDE & WORKSPACE ────────────────────────────────────────────",
    "  <Space> e              Toggle Left File Tree (Yazi/Neo-tree)",
    "  <Space> m t            Toggle IDE / Zen Mode",
    "  <Space> j              Toggle Bottom Terminal Split",
    "  <Space> ?              Show Vide Quickstart Guide",
    "  <Space> ,              Open Settings",
    "",
    "  ── TTY & KEYBOARD NAVIGATION ───────────────────────────────────",
    "  Ctrl+E                 Toggle and focus File Tree",
    "  Ctrl+T                 Toggle and focus Terminal panel",
    "  <Esc>                  Return focus to Editor from panels",
    "  <Alt> h/j/k/l          Navigate splits & WezTerm panes seamlessly",
    "",
    "  ── TELESCOPE & SEARCH ──────────────────────────────────────────",
    "  <Space> <Space>        Telescope: Show All Commands",
    "  <Space> f f            Telescope: Find Files",
    "  <Space> f r            Telescope: Open Recent Files",
    "  Ctrl+F                 Telescope / Search",
    "",
    "  ── VSCODE-LIKE ESSENTIALS ──────────────────────────────────────",
    "  Ctrl+S                 Save file",
    "  Ctrl+Q                 Force quit Vide",
    "  Ctrl+W                 Close current Tab/Buffer",
    "  Ctrl+N / Ctrl+T        Open new Tab/Buffer",
    "  Ctrl+Tab               Next Tab",
    "  Ctrl+Shift+Tab         Previous Tab",
    "  Ctrl+Z                 Undo",
    "  Ctrl+Y                 Redo",
    "  Ctrl+C                 Copy selection to system clipboard",
    "  Ctrl+X                 Cut selection to system clipboard",
    "  Ctrl+V                 Paste from system clipboard",
    "  Ctrl+A                 Select all text",
    "",
    "  ── PORTED NMUX42 KEYS ──────────────────────────────────────────",
    "  J / K (Visual)         Move selected lines down / up",
    "  J (Normal)             Join lines without moving cursor",
    "  Ctrl+D / Ctrl+U        Scroll half page and keep cursor centered",
    "  n / N                  Next / Prev search match and keep centered",
    "  <Space> p (Visual)     Paste over selection without yanking it",
    "  <Space> d              Delete to black hole (without yanking)",
    "  <Space> s              Substitute word under cursor everywhere",
    "  <Space> x              Make current file executable (chmod +x)",
}

local state = { active_tab = "vim", buf = nil, win = nil }

local function open_bindings_window()
    local width  = math.min(74, vim.o.columns - 4)
    local height = math.floor(vim.o.lines * 0.85)
    local row    = math.floor((vim.o.lines - height) / 2)
    local col    = math.floor((vim.o.columns - width) / 2)

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative    = "editor",
        width       = width,
        height      = height,
        row         = row,
        col         = col,
        style       = "minimal",
        border      = "rounded",
        title       = "  Vide Help Reference ",
        title_pos   = "center",
    })
    return buf, win
end

local function render()
    if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end

    local tab_vim  = state.active_tab == "vim"
    local tab1_lbl = tab_vim and "●[1] Vim Motions " or "  [1] Vim Motions "
    local tab2_lbl = tab_vim and "  [2] Vide Keys  " or "●[2] Vide Keys  "

    local header = {
        "  " .. tab1_lbl .. " │ " .. tab2_lbl,
        "  ────────────────────────────────────────────────────────────",
        "",
    }

    local content = tab_vim and VIM_MOTIONS or VIDE_KEYS
    local lines = {}
    for _, l in ipairs(header) do table.insert(lines, l) end
    for _, l in ipairs(content) do table.insert(lines, l) end
    table.insert(lines, "")
    table.insert(lines, "  [Tab]/[1]/[2] Switch tab  │  [/] Search  │  [q/Esc] Close")

    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.bo[state.buf].modifiable = false
    vim.api.nvim_win_set_cursor(state.win, { 1, 0 })

    -- Highlight header
    local ns = vim.api.nvim_create_namespace("vimbindings_hl")
    vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
    vim.api.nvim_buf_add_highlight(state.buf, ns, "Title",   0, 0, -1)
    vim.api.nvim_buf_add_highlight(state.buf, ns, "Comment", 1, 0, -1)
    -- Highlight section headers
    for i, l in ipairs(lines) do
        if l:match("^%s+──") then
            vim.api.nvim_buf_add_highlight(state.buf, ns, "Special", i - 1, 0, -1)
        elseif l:match("^%s+╭") or l:match("^%s+│") or l:match("^%s+╰") then
            vim.api.nvim_buf_add_highlight(state.buf, ns, "DiagnosticInfo", i - 1, 0, -1)
        elseif l:match("^%s+%[") and i == #lines then
            vim.api.nvim_buf_add_highlight(state.buf, ns, "Comment", i - 1, 0, -1)
        end
    end
end

_G.open_help_menu = function()
    -- Stop insert mode if we are in it
    if vim.fn.mode() == 'i' then vim.cmd("stopinsert") end

    state.buf, state.win = open_bindings_window()
    vim.bo[state.buf].buftype   = "nofile"
    vim.bo[state.buf].bufhidden = "wipe"
    vim.bo[state.buf].swapfile  = false
    vim.bo[state.buf].filetype = "vimbindings"

    local map = function(k, fn, desc)
        vim.keymap.set({"n", "i"}, k, fn, { buffer = state.buf, silent = true, desc = desc })
    end

    map("q",     function() pcall(vim.api.nvim_win_close, state.win, true) end, "Close")
    map("<Esc>", function() pcall(vim.api.nvim_win_close, state.win, true) end, "Close")
    map("<C-c>", function() pcall(vim.api.nvim_win_close, state.win, true) end, "Close")

    map("<Tab>", function()
        state.active_tab = state.active_tab == "vim" and "vide" or "vim"
        render()
    end, "Switch tab")
    map("1", function() state.active_tab = "vim";  render() end, "Vim Motions tab")
    map("2", function() state.active_tab = "vide"; render() end, "Vide Keys tab")

    -- Search within the buffer using built-in /
    map("/", function()
        vim.api.nvim_feedkeys("/", "n", false)
    end, "Search in buffer")

    render()
end

return {
    setup = function()
        -- Keymap to open
        -- We bind to normal and visual mode as well. But wait, since vide forces insert mode,
        -- if the user hits <space> in insert mode it types a space. So we should create a user command.
        vim.api.nvim_create_user_command("HelpMenu", _G.open_help_menu, {})
        vim.keymap.set({ "n", "i", "v" }, "<leader>hk", _G.open_help_menu, { desc = "Show Help Menu" })

        -- Setup a persistent floating widget instead of statusline
        -- because vide's Zig core explicitly hides the statusline in IDE mode.
        local function create_floating_widget()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { " 󰋖 Help " })
            
            local width = 8
            local height = 1
            
            local function get_pos()
                return {
                    row = vim.o.lines - 2,
                    col = vim.o.columns - width - 2
                }
            end

            local pos = get_pos()
            local win = vim.api.nvim_open_win(buf, false, {
                relative = 'editor',
                width = width,
                height = height,
                row = pos.row,
                col = pos.col,
                style = 'minimal',
                border = 'none',
                focusable = true,
                zindex = 100,
            })

            vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
            vim.api.nvim_set_option_value("filetype", "helpwidget", { buf = buf })
            
            vim.cmd("highlight default HelpWidgetBtn guibg=#3b4252 guifg=#81a1c1 gui=bold")
            vim.api.nvim_buf_add_highlight(buf, 0, "HelpWidgetBtn", 0, 0, -1)

            -- Handle clicks
            local function on_click()
                if vim.fn.mode() == 'i' then vim.cmd("stopinsert") end
                -- Try to return focus to main window
                pcall(vim.cmd, "wincmd p")
                _G.open_help_menu()
            end

            vim.keymap.set('n', '<LeftMouse>', on_click, { buffer = buf })
            vim.keymap.set('i', '<LeftMouse>', on_click, { buffer = buf })
            
            -- Re-anchor on resize
            vim.api.nvim_create_autocmd("VimResized", {
                callback = function()
                    if vim.api.nvim_win_is_valid(win) then
                        local new_pos = get_pos()
                        vim.api.nvim_win_set_config(win, {
                            relative = 'editor',
                            row = new_pos.row,
                            col = new_pos.col,
                        })
                    end
                end
            })
        end
        
        -- Delay widget creation slightly so it computes correct screen dimensions
        vim.defer_fn(create_floating_widget, 100)
    end
}
