# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.1.2] - 2026-10-19

### Changed

- Dimmed text is now barely visible by default: `ctermfg=234 guifg=#1c1c1c` on dark backgrounds (was `235` / `#262626`) and `ctermfg=255 guifg=#eeeeee` on light ones (was `254` / `#e4e4e4`). If it disappears completely on your background, set your own color (`:help hl-SpotlightDim`).

## [2.1.1] - 2026-10-19

### Changed

- Dimmed text is a step closer to the background by default: `ctermfg=235 guifg=#262626` on dark backgrounds (was `236` / `#282828`) and `ctermfg=254 guifg=#e4e4e4` on light ones (was `253` / `#dadada`). Colors you set yourself are unaffected.

## [2.1.0] - 2026-10-17

### Added

- `<leader>hd` (`:SpotlightBlocks`): light the indented block of code around the cursor (with its closing `}` / `</tag>` line), found by indentation in any language. Chunks of lines between blank lines count as blocks too. Then `<leader>hn` / `<leader>hb` walk through every block inside it (nested ones too), wrapping back to the whole block. Blocks lit this way keep following the indentation as you edit (a line added after the last line of a Python block joins it). Option `g:spotlight_blocks_mapping`.
- `<leader>hm` (`:SpotlightFollow`): follow mode, lighting the block under the cursor automatically as it moves, until `<leader>hm` or `<leader>hc`. While following, `<leader>hn` / `<leader>hb` walk the blocks inside the lit one. Option `g:spotlight_follow_mapping`.

## [2.0.0] - 2026-10-15

### Changed

- **Breaking: `<leader>h` now adds while a spotlight is on.** `<leader>h{motion}` and Visual `<leader>h` light a region when nothing is lit and *add* another region when something is. Clearing moved from a bare `<leader>h` to **`<leader>hc`**. The 1.x behavior (replace, bare key clears) is still available by mapping `<Plug>(SpotlightOperator)` / `<Plug>(SpotlightVisual)`.
- A region whose text is deleted entirely is dropped (when other regions remain), instead of staying lit on a neighbouring line.

### Added

- **Several regions at once.** Everything outside all lit regions is dimmed; character, line and block regions can share lines. `:[range]SpotlightAdd` adds lines.
- `<leader>hx` (`:SpotlightToggleRegion`) switches the region under the cursor off and on.
- `<leader>hn` / `<leader>hb` (`:SpotlightNext` / `:SpotlightPrev`) light only the next / previous region and jump to it, cycling back to all regions.
- Options `g:spotlight_clear_mapping`, `g:spotlight_toggle_mapping`, `g:spotlight_next_mapping`, `g:spotlight_prev_mapping`; `<Plug>` targets `SpotlightAddOperator`, `SpotlightAddVisual`, `SpotlightClear`, `SpotlightToggleRegion`, `SpotlightNext`, `SpotlightPrev`; `spotlight#add_lines()`.

## [1.1.0] - 2026-10-15

### Added

- `g:spotlight_hide_search`: hide the search highlight (`'hlsearch'`) while a spotlight is on, restoring it afterwards.

## [1.0.1] - 2026-10-14

### Fixed

- With `g:spotlight_suppress_cursor_events`, matching-pair highlights (vim-matchup's `MatchWord`/`MatchParen`, matchparen's `:3match`) stayed frozen, as did a coc.nvim document highlight whose language-server reply arrived after the spotlight went on (common in JSX/HTML).

## [1.0.0] - 2026-10-14

First tagged release. Changes since the initial version:

### Changed

- **Visual-mode `<leader>h` now replaces** an existing spotlight instead of toggling it off. The old behavior is still available as `<Plug>(SpotlightToggle)`.
- Cursor-event suppression (the coc.nvim workaround) is now **opt-in** via `g:spotlight_suppress_cursor_events`. It used to be always on, which disabled `CursorMoved`/`CursorHold` for every plugin and matchparen. When on, it also hides a word-under-cursor highlight already on screen (`:match`, coc.nvim) and restores the `:match` afterwards.
- Visual mappings use `xmap` instead of `vmap`, so typing over a Select-mode selection (snippet placeholders) no longer triggers the plugin.
- The default dim color follows `'background'`; light themes get `ctermfg=253 guifg=#dadada`.
- Requires Vim 8.2+ or Neovim 0.5+.

### Added

- `:Spotlight!` clears; both commands accept `|`.
- `g:spotlight_mapping`, `g:spotlight_priority`.
- `<Plug>(SpotlightVisual)`.
- `spotlight#is_active()`, `spotlight#lines()`, `spotlight#clear()` as public functions.
- Block mode follows `$` (lit to the end of every line).
- Matches are kept in sync in every window showing the buffer, including when the buffer is edited from another window.
- Test suite for Vim and Neovim, CI, and vint linting.

### Fixed

- The plugin no longer overwrites or deletes the user's `s` and `e` marks, including the `delmarks s e` that ran on every exit. Regions are now tracked with text properties (Vim) or extmarks (Neovim).
- The plugin no longer clears the user's `:match` highlight.
- Text typed at the end of a line-wise spotlight (`:Spotlight`, `<leader>hj`, `V`) was dimmed.
- Block mode used byte columns, so blocks were ragged with tabs or multibyte characters. It now uses screen columns.
- Deleting the first or last line of the region left the dim frozen at the old position.
- `selection=exclusive` lit one character too many.
- Per-buffer state was never released; it now lives in `b:spotlight`.
- The autoload script was loaded on the first `BufEnter`, defeating lazy loading.
- Scripts failed to load when `'cpoptions'` contained `C`.
- The help file had no `*spotlight*` tag, and documented the wrong default colors.

## Initial version

- Released as commit `7960f6f` (untagged).

[Unreleased]: https://github.com/arthurdaquinosilva/vim-spotlight/compare/v2.1.2...HEAD
[2.1.2]: https://github.com/arthurdaquinosilva/vim-spotlight/compare/v2.1.1...v2.1.2
[2.1.1]: https://github.com/arthurdaquinosilva/vim-spotlight/compare/v2.1.0...v2.1.1
[2.1.0]: https://github.com/arthurdaquinosilva/vim-spotlight/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/arthurdaquinosilva/vim-spotlight/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/arthurdaquinosilva/vim-spotlight/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/arthurdaquinosilva/vim-spotlight/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/arthurdaquinosilva/vim-spotlight/compare/7960f6f...v1.0.0
