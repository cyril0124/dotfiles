# Neovim Configuration

Personal Neovim configuration using [lazy.nvim](https://github.com/folke/lazy.nvim) as the plugin manager.

## Keybindings

> Leader key: `<Space>` | Local leader: `-`

### Navigation

| Key | Mode | Description |
|-----|------|-------------|
| `<C-h/j/k/l>` | Normal | Window navigation (left/down/up/right) |
| `<C-Up/Down>` | Normal | Resize window vertically |
| `<C-Left/Right>` | Normal | Resize window horizontally |
| `<Tab>` | Normal | Next buffer |
| `<S-Tab>` | Normal | Previous buffer |
| `<leader>x` | Normal | Close current buffer |
| `f` / `F` | Normal | Jump forward / backward to character (mini.jump) |
| `t` / `T` | Normal | Jump forward / backward till character |
| `;` | Normal | Repeat last jump |
| `zR` / `zM` | Normal | Open / Close all folds (nvim-ufo) |

### File & Search

| Key | Mode | Description |
|-----|------|-------------|
| `<leader>ff` | Normal | Find files (Telescope) |
| `<leader>fw` | Normal | Live grep (Telescope) |
| `<leader>gs` | Normal | Grep word under cursor (whole word) |
| `<leader>gS` | Normal | Grep word under cursor |
| `<leader>gs` | Visual | Grep selected text |
| `<leader>sr` | Normal | Search & replace (GrugFar) |
| `<leader>sr` | Visual | Search & replace in selection |
| `<leader>e` | Normal | Toggle NeoTree (float) |
| `<leader>E` | Normal | Toggle NeoTree (left side) |
| `<leader>o` | Normal | Toggle code outline |
| `<leader>pa` | Normal | Print absolute file path |

### Code & LSP

| Key | Mode | Description |
|-----|------|-------------|
| `<leader>f` | Normal | Format code (conform.nvim) |
| `<leader>/` | Normal/Visual | Toggle comment |
| `K` | Normal | Hover info (hover.nvim) |
| `<leader>k` | Normal | Hover info (hover.nvim) |
| `gK` | Normal | Enter hover window |
| `gd` | Normal | Go to definition |
| `gr` | Normal | Show references |
| `<leader>rn` | Normal | LSP rename |
| `<leader>ds` | Normal | LSP diagnostics (Telescope) |
| `<leader>dS` | Normal | LSP diagnostics (warning+ only) |
| `<leader>T` | Normal | Trouble diagnostics toggle |
| `sa` + char | Normal | Add surround (mini.surround) |
| `sd` + char | Normal | Delete surround |
| `sr` + old + new | Normal | Replace surround |

### Git

| Key | Mode | Description |
|-----|------|-------------|
| `<leader>gD` | Normal | Toggle Diffview |
| `<leader>gl` | Normal | Last commit diff (incremental depth) |
| `]h` / `[h` | Normal | Next / Previous git hunk |

### Terminal

| Key | Mode | Description |
|-----|------|-------------|
| `<leader>t` | Normal | Toggle terminal (float) |
| `<leader>dt` | Normal | Toggle terminal (bottom) |
| `<Esc>` | Terminal | Exit terminal insert mode |

### Other

| Key | Mode | Description |
|-----|------|-------------|
| `<leader>w` | Normal | Save file |
| `<leader>q` | Normal | Quit nvim (blocked when quit lock is enabled) |
| `<leader>m` | Normal/Visual | Open context menu |
| `<leader>wk` | Normal | Show all keymaps (WhichKey) |
| `<leader>?` | Normal | Buffer local keymaps (WhichKey) |
| `<` / `>` | Visual | Indent and keep selection |

## Commands

| Command | Description |
|---------|-------------|
| `:F` | Format code |
| `:FF` / `:FW` | Format and save |
| `:TS` | Trim trailing whitespace |
| `:WW` | Enable line wrapping |
| `:NW` | Disable line wrapping |
| `:AnsiEnable` | Enable ANSI color rendering |
| `:AnsiToggle` | Toggle ANSI color rendering |

## Menu Items

Open the context menu with `<leader>m`. The menu adapts to the current filetype and includes:

**Default Menu:** Trim spaces, Format, Find files/words (no-ignore), Search & replace, LSP Actions submenu, Git Actions submenu, Edit Config

**Shared Items (all menus):** Notification history, Lock/Unlock quit, DiffviewOpen, DiffviewFileHistory, Toggle git blame, Last commit diff (incremental), Reset commit depth, Switch colorscheme

## Installed Plugins

| Plugin | Purpose |
|--------|---------|
| [lazy.nvim](https://github.com/folke/lazy.nvim) | Plugin manager |
| [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | Fuzzy finder |
| [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) | File explorer |
| [bufferline.nvim](https://github.com/akinsho/bufferline.nvim) | Buffer tabs |
| [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) | Status line |
| [which-key.nvim](https://github.com/folke/which-key.nvim) | Keybinding hints |
| [mini.nvim](https://github.com/echasnovski/mini.nvim) | Pairs, surround, jump, trailspace, cursorword, git, notify, animate, hipatterns |
| [snacks.nvim](https://github.com/folke/snacks.nvim) | Big file detection |
| [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | Syntax highlighting |
| [conform.nvim](https://github.com/stevearc/conform.nvim) | Code formatting |
| [grug-far.nvim](https://github.com/MagicDuck/grug-far.nvim) | Search & replace |
| [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) | Terminal integration |
| [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) | Git signs & blame |
| [diffview.nvim](https://github.com/sindrets/diffview.nvim) | Git diff viewer |
| [trouble.nvim](https://github.com/folke/trouble.nvim) | Diagnostics list |
| [outline.nvim](https://github.com/hedyhli/outline.nvim) | Code outline |
| [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo) | Modern folding |
| [hover.nvim](https://github.com/lewis6991/hover.nvim) | Hover info |
| [lsp_signature.nvim](https://github.com/ray-x/lsp_signature.nvim) | Function signature hints |
| [blink-cmp](https://github.com/Saghen/blink.cmp) | Completion |
| [markview.nvim](https://github.com/OXY2DEV/markview.nvim) | Markdown preview |
| [dropbar.nvim](https://github.com/Bekaboo/dropbar.nvim) | Breadcrumbs winbar |
| [smear-cursor.nvim](https://github.com/sphamba/smear-cursor.nvim) | Animated cursor |
| [satellite.nvim](https://github.com/lewis6991/satellite.nvim) | Scrollbar decorations |
| [reactive.nvim](https://github.com/rasulomaroff/reactive.nvim) | Mode-based cursorline |
| [colorful-winsep.nvim](https://github.com/nvim-zh/colorful-winsep.nvim) | Window separator colors |
| [indent-blankline.nvim](https://github.com/lukas-reineke/indent-blankline.nvim) | Indent guides |
| [tiny-inline-diagnostic.nvim](https://github.com/rachartier/tiny-inline-diagnostic.nvim) | Inline diagnostics |
| [nvzone/menu](https://github.com/nvzone/menu) | Context menu |
| [ansi.nvim](https://github.com/0xferrous/ansi.nvim) | ANSI color code rendering |

## Color Themes

Available themes (switch via menu or `:colorscheme`):
- kanagawa (default)
- tokyonight
- catppuccin
- rose-pine
