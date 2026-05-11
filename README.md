# vim-spotlight

> Dim everything outside what you're looking at.

A Vim plugin that puts a literal spotlight on your code. Select a region — by motion, text object, visual selection, or ex-range — and everything else fades to a muted color. Stop scanning a 600-line file for the 12 lines that matter.

## Features

- **Works with any motion or text object** — `<leader>h9j`, `<leader>hi{`, `<leader>hit`, `<leader>hap`, …
- **Ex-range support** — `:5,20Spotlight`, `:.,+9Spotlight`
- **Visual-mode toggle** — select, then `<leader>h`
- **Block-column spotlight** — `<Ctrl-v>` select a column, then `<leader>h` to light just that rectangle
- **Per-buffer state** — switch windows or tabs, your spotlight stays put
- **Edit-aware** — adapts as the buffer's text shifts
- **CoC-friendly** — temporarily silences cursor-hold highlights while a spotlight is active, so they don't bleed through the dim
- **No dependencies** — pure Vimscript, ~200 lines

## Requirements

- Vim 8.0+ or Neovim

## Installation

### [vim-plug](https://github.com/junegunn/vim-plug)
```vim
Plug 'arthurdaquinosilva/vim-spotlight'
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)
```lua
use 'arthurdaquinosilva/vim-spotlight'
```

### [lazy.nvim](https://github.com/folke/lazy.nvim)
```lua
{ 'arthurdaquinosilva/vim-spotlight' }
```

### Native packages (Vim 8 / Neovim)
```sh
git clone https://github.com/arthurdaquinosilva/vim-spotlight \
    ~/.vim/pack/plugins/start/vim-spotlight
```

## Usage

### Default mappings

| Mode   | Keystroke                       | Action                                  |
| ------ | ------------------------------- | --------------------------------------- |
| Normal | `<leader>h{motion}`             | Spotlight the motion / text object      |
| Normal | `<leader>h` *(spotlight on)*    | Clear                                   |
| Visual | `<leader>h`                     | Toggle on the current selection         |
| Visual | `<Ctrl-v>{select}` → `<leader>h`| Toggle on the selected column block     |

### Operator examples

```vim
<leader>h9j         " current line + 9 below
<leader>h5k         " 5 lines above + current
<leader>h}          " up to the next blank line
<leader>hi{         " content inside braces
<leader>ha(         " around parens (including them)
<leader>hit         " inside HTML tag
<leader>hi"         " inside quoted string
<leader>hap         " a paragraph
<leader>hiw         " inner word
```

Any motion or text object you'd hand to `d` or `y` works here — that's the whole point of building it as an operator.

### Block-column selection

Enter blockwise visual mode with `<Ctrl-v>`, select a rectangular column, then press `<leader>h`. Instead of dimming only the partial first and last lines (as a char-wise selection does), the dim covers the columns *outside* the block on **every** line in the range — leaving a vertical band of code lit. Great for focusing on one aligned column: a list of values, a table field, an indentation level.

```vim
<Ctrl-v>5j6l<leader>h    " light a 6-line × 7-column block
```

### Commands

```vim
:5,20Spotlight      " keep lines 5–20 bright, dim the rest
:.,+9Spotlight      " current line + 9 below
:.,$Spotlight       " current line to end of file
:Spotlight          " current line only
:SpotlightClear     " clear
```

## Configuration

### Custom colors

The plugin defines `SpotlightDim` with `:highlight default`, so anything in your colorscheme wins:

```vim
highlight SpotlightDim ctermfg=240 guifg=#3a3a3a
```

If you want a custom dim color to survive `:colorscheme` changes, set it in a `ColorScheme` autocmd of your own:

```vim
augroup my_spotlight_color
    autocmd!
    autocmd ColorScheme * highlight SpotlightDim ctermfg=240 guifg=#3a3a3a
augroup END
```

### Custom mappings

Disable defaults and map your own keys to the `<Plug>` targets:

```vim
let g:spotlight_no_default_mappings = 1

vmap <silent> ,s <Plug>(SpotlightToggle)
nmap <silent> ,s <Plug>(SpotlightOperator)
```

## How it works

Vim's [`matchadd()`](https://vimhelp.org/eval.txt.html#matchadd%28%29) attaches a highlight group to a regex pattern across the current window. The plugin builds patterns that match everything *outside* your region — earlier lines, later lines, the partial first/last lines for char-wise selections, or the left/right column bands for block-wise selections — and assigns each one the `SpotlightDim` highlight. The region itself gets no pattern, so it shows in your normal colors.

State (active flag, selection bounds, position-tracking marks) lives in a per-buffer dictionary. Because `matchadd` IDs are window-local but state is per-buffer, the plugin re-runs its match logic on `BufEnter` / `WinEnter`, clearing any stale `SpotlightDim` matches in the current window first. That keeps splits and tabs in sync.

For the full picture: `:help spotlight`.

## License

[MIT](LICENSE) © Arthur D'Aquino
