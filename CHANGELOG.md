# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

Changes since the initial version.

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
