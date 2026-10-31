# vim-spotlight

[![CI](https://github.com/arthurdaquinosilva/vim-spotlight/actions/workflows/ci.yml/badge.svg)](https://github.com/arthurdaquinosilva/vim-spotlight/actions/workflows/ci.yml)

> Dim everything outside what you're looking at.

A Vim plugin that puts a literal spotlight on your code. Select a region by motion, text object, Visual selection, or Ex range, and everything else fades to a muted color. Stop scanning a 600-line file for the 12 lines that matter.

## Features

- **Works with any motion or text object**: `<leader>h9j`, `<leader>hi{`, `<leader>hit`, `<leader>hap`, … and repeats with `.`
- **Ex-range support**: `:5,20Spotlight`, `:.,+9Spotlight`
- **Visual mode**: char-wise, line-wise, and block-wise
- **Block-column spotlight**: `<Ctrl-v>` a column to light just that rectangle, lined up by screen column (tabs and wide characters included)
- **Several regions at once**: keep pressing `<leader>h` to add more places, switch one off with `<leader>hx` or remove it with `<leader>hd`, and step the focus through them with `<leader>hn` / `<leader>hb`. No Shift needed
- **Follows your edits**: the region moves with the text as you insert, delete, and undo
- **Every window, every tab**: splits on the same buffer stay in sync; each buffer keeps its own spotlight
- **Leaves your state alone**: no marks, no `:match`, no `'eventignore'` changes
- **Light and dark themes**: picks a dim color that fits `'background'`
- **Lazy**: nothing beyond a few autocommands loads until you use it
- **No dependencies**: pure Vimscript, tested on Vim and Neovim

## Requirements

- Vim 8.2+ or Neovim 0.5+
- In Vim, `+textprop` lets the region follow edits (check with `:echo has('textprop')`). Without it the plugin still works, but the region stays on fixed coordinates.

## Installation

### [vim-plug](https://github.com/junegunn/vim-plug)
```vim
Plug 'arthurdaquinosilva/vim-spotlight'
```

### [lazy.nvim](https://github.com/folke/lazy.nvim)
```lua
{ 'arthurdaquinosilva/vim-spotlight' }
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)
```lua
use 'arthurdaquinosilva/vim-spotlight'
```

### Native packages
```sh
git clone https://github.com/arthurdaquinosilva/vim-spotlight \
    ~/.vim/pack/plugins/start/vim-spotlight
vim -u NONE -c 'helptags ~/.vim/pack/plugins/start/vim-spotlight/doc' -c q
```

## Usage

### Default mappings

| Mode   | Keystroke                        | Action                                                  |
| ------ | -------------------------------- | ------------------------------------------------------- |
| Normal | `<leader>h{motion}`              | Spotlight the motion / text object (adds when one is on) |
| Visual | `<leader>h`                      | Spotlight the selection (adds when one is on)           |
| Visual | `<Ctrl-v>{select}` → `<leader>h` | Spotlight the selected column block                     |
| Normal | `<leader>hc`                     | Clear everything                                        |
| Normal | `<leader>hd`                     | Remove one region (focused, or under the cursor)        |
| Normal | `<leader>hx`                     | Switch the region under the cursor off/on               |
| Normal | `<leader>hn` / `<leader>hb`      | Light only the next / previous region                   |
| Normal | `<leader>hm`                     | Follow mode on/off: keep lighting the block under the cursor as you move |

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

Any motion or text object you'd hand to `d` or `y` works here. That's the whole point of building it as an operator.

### Block-column selection

Enter blockwise Visual mode with `<Ctrl-v>`, select a rectangle, then press `<leader>h`. The dim covers the columns *outside* the block on **every** line in the range, leaving a vertical band of code lit. Great for one aligned column: a list of values, a table field, an indentation level. Extend the block with `$` to keep everything right of the left edge lit.

```vim
<Ctrl-v>5j6l<leader>h    " light a 6-line × 7-column block
```

### Several regions

While something is lit, `<leader>h` *adds* another region (same motions, text objects and Visual selections), so you can light a function and the place that calls it at the same time:

```vim
<leader>hip         " light this paragraph
<leader>h}          " ...and also up to the next blank line over there
<leader>hi{         " ...and also the inside of these braces
```

Everything outside all of them is dimmed. Overlapping regions merge, and each one follows your edits.

- `<leader>hx` switches the region under the cursor **off** (dimmed but remembered) or back **on**.
- `<leader>hd` **removes one region** and keeps the rest: the one you focused with `<leader>hn` / `<leader>hb`, or else the one under the cursor. Removing the last one clears the spotlight.
- `<leader>hn` lights **only the next region** and puts the cursor on its first character; keep pressing to walk through them, and past the last one everything is lit again. `<leader>hb` goes back. Switched-off regions are visited too, so you can select a region, park it with `<leader>hx`, select another, and cycle between them.
- `<leader>hm` turns on **follow mode**: the block of code under the cursor, found by indentation (works in any language, no language server needed), is lit automatically wherever you move; `<leader>hm` again (or `<leader>hc`) turns it off. Works per buffer, and alongside `g:spotlight_suppress_cursor_events`.
- `<leader>hc` or `:SpotlightClear` removes every region. To start over with one region, clear first or use `:Spotlight` with a range.

### Commands

```vim
:5,20Spotlight      " keep lines 5–20 bright, dim the rest
:.,+9Spotlight      " current line + 9 below
:Spotlight          " current line only
:10,20SpotlightAdd  " add lines 10–20 as another region
:SpotlightToggleRegion  " switch the region under the cursor off/on
:SpotlightDeleteRegion  " remove the focused region, or the one under the cursor
:SpotlightNext      " light only the next region (:SpotlightPrev for previous)
:Spotlight!         " clear
:SpotlightClear     " clear
```

## Configuration

| Option                               | Default       | Description                                                       |
| ------------------------------------ | ------------- | ----------------------------------------------------------------- |
| `g:spotlight_mapping`                | `'<leader>h'` | Key for the default mappings                                      |
| `g:spotlight_clear_mapping`          | key + `c`     | Clear every region                                                |
| `g:spotlight_delete_mapping`         | key + `d`     | Remove one region                                                 |
| `g:spotlight_toggle_mapping`         | key + `x`     | Switch the region under the cursor off/on                         |
| `g:spotlight_next_mapping`           | key + `n`     | Light only the next region                                        |
| `g:spotlight_prev_mapping`           | key + `b`     | Light only the previous region                                    |
| `g:spotlight_no_default_mappings`    | `0`           | Set to `1` to define no mappings                                  |
| `g:spotlight_priority`               | `100`         | Match priority; raise it if other highlights show through the dim |
| `g:spotlight_suppress_cursor_events` | `0`           | Silence cursor events while a spotlight is on (see below)         |
| `g:spotlight_hide_search`            | `0`           | Hide the search highlight while a spotlight is on                 |

### Custom colors

`SpotlightDim` is defined with `:highlight default`, so your colorscheme or vimrc wins:

```vim
highlight SpotlightDim ctermfg=240 guifg=#3a3a3a
" or
highlight link SpotlightDim Comment
```

Most colorschemes clear every group when they load. To keep your color across `:colorscheme`, set it from a `ColorScheme` autocommand:

```vim
augroup my_spotlight
    autocmd!
    autocmd ColorScheme * highlight SpotlightDim ctermfg=240 guifg=#3a3a3a
augroup END
```

### Custom mappings

```vim
let g:spotlight_mapping = '<leader>s'       " change the key (and sc, sx, sn, sb)
" or take full control:
let g:spotlight_no_default_mappings = 1
nmap ,s  <Plug>(SpotlightAddOperator)
xmap ,s  <Plug>(SpotlightAddVisual)
nmap ,sc <Plug>(SpotlightClear)
```

Prefer one region at a time, the 1.x way (the key replaces the spotlight, and pressed alone clears it)? Map `<Plug>(SpotlightOperator)` and `<Plug>(SpotlightVisual)` instead:

```vim
nmap <leader>h <Plug>(SpotlightOperator)
xmap <leader>h <Plug>(SpotlightVisual)
```

### Mapping conflicts

Other mappings that start with the same key (vim-gitgutter's `<leader>hp`, `<leader>hs`, … for example) coexist fine: `<leader>h{motion}` and `<leader>hc` / `hd` / `hx` / `hn` / `hb` resolve as soon as you type the next key. A mapping you already have for one of these exact keys is never overwritten; pick other keys with the options above.

### Cursor-highlight plugins (coc.nvim etc.)

Plugins and scripts that highlight the word under the cursor can draw over the dim. Setting `g:spotlight_suppress_cursor_events = 1` adds `CursorMoved`, `CursorMovedI`, `CursorHold` and `CursorHoldI` to `'eventignore'` while the current buffer has a spotlight. It also hides cursor-driven highlights already on screen: the window's `:match` (which most cursor-word scripts use), matchparen and vim-matchup's pair highlights, and coc.nvim's document highlight, including a language-server reply that arrives just after the spotlight went on. The `:match` is restored when the spotlight ends. This is global, and matchparen stops updating while it's in effect, so it's opt-in.

### Search highlight

With `'hlsearch'`, matches inside the spotlight stay highlighted (matches outside are dimmed). Set `g:spotlight_hide_search = 1` to hide the search highlight while a spotlight is on. `*`, `n` and `N` still work, and `'hlsearch'` is restored when the spotlight ends.

## How it works

Vim's [`matchadd()`](https://vimhelp.org/builtin.txt.html#matchadd%28%29) attaches a highlight group to a pattern in one window. The plugin builds patterns for everything *outside* your region (earlier lines, later lines, and the partial first/last line or the columns left and right of a block) and gives them the `SpotlightDim` highlight. The region itself gets no pattern, so it keeps its normal colors.

The region is stored per buffer and anchored with a text property (Vim) or an extmark (Neovim), which move with the text as you edit. After each change the patterns are rebuilt from the anchor in every window showing the buffer.

For the full picture: `:help spotlight`.

## Development

```sh
make test        # run the suite in Vim and Neovim
make test-vim    # or one editor; override the binary with VIM=/path/to/vim
make lint        # vint
```

Tests are plain Vimscript (`test/test_*.vim`, no dependencies). Run a subset with `SPOTLIGHT_TEST_FILTER=block make test-vim`.

## License

[MIT](LICENSE) © Arthur D'Aquino
