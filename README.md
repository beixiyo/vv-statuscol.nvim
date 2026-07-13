<div align="center">

# vv-statuscol.nvim

English | <a href="./README.zh-CN.md">中文</a>

<img src="./docs/assets/vv-statuscol.png" alt="vv-statuscol demo" width="900" />

Want my Neovim config? See <a href="https://github.com/beixiyo/dotfiles">dotfiles</a>.

<em>A lightweight custom status column with content-aware width and built-in line-level Git diffs</em>

<br />

<img src="https://img.shields.io/badge/Neovim-0.10+-57A143?style=flat-square&logo=neovim&logoColor=white" alt="Requires Neovim 0.10+" />
<img src="https://img.shields.io/badge/Lua-2C2D72?style=flat-square&logo=lua&logoColor=white" alt="Lua" />

</div>

---

## Requirements

- [vv-utils.nvim](https://github.com/beixiyo/vv-utils.nvim) — required for shared Git diff and highlight utilities
- [Git](https://github.com/git/git) — optional; required only for staged and unstaged status-column tracks

## Why this plugin

[statuscol.nvim](https://github.com/luukvbaal/statuscol.nvim) uses about 690 lines to provide arbitrary sign-segment composition and several FFI calls. This plugin takes a roughly 200-line, snacks-style approach and adds content-aware segment widths plus built-in line-level Git diffs without gitsigns.

## Dual Git tracks

Normal file windows show two independent line-level states. The left Git column represents staged changes from `HEAD` to the index; the right column represents unstaged changes from the index to the worktree. Both columns can be colored on the same line. Staged line numbers are mapped onto the current worktree buffer, so earlier insertions and deletions do not leave stale index coordinates.

`vv-git` diff and result windows hide these tracks through a window-local flag because scrollbar markers and diff coloring already represent the changes there. The same buffer still shows both tracks in normal editing windows.

### Content-aware width

Unlike status columns that reserve fixed blank slots, every mark, sign, Git, and fold segment has dynamic width:

- A segment collapses to zero when the entire buffer or window has no content of that kind
- A clean file with no marks, diagnostics, Git changes, or folds shows only line numbers
- Width is stable across the whole buffer or window, so right-aligned line numbers do not jump between rows

Set native `signcolumn` to `no` and `foldcolumn` to `0`, because they render outside `statuscolumn` and otherwise reserve extra columns. `setup()` sets `foldcolumn` to `0` automatically.

### Layout

```text
[mark] [sign] %= [lnum] [ ] [fold] [staged][unstaged] [ ]
```

## Installation

```lua
{
  'beixiyo/vv-statuscol.nvim',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  event = { 'BufReadPost', 'BufNewFile' },
  opts = {
    enabled = true,
    ft_ignore = {
      'dashboard', 'vv-explorer', 'vv-task-panel', 'trouble',
      'toggleterm', 'help', 'lazy', 'mason', 'checkhealth', 'qf',
    },
    bt_ignore = { 'terminal', 'nofile', 'prompt' },
    refresh = 50,
    fold = { open = '', close = '' },
    git = {
      A = { text = '▎', hl = 'VVGitAdded' },
      C = { text = '▎', hl = 'VVGitModified' },
      D = { text = '󰆐', hl = 'VVGitDeleted' },
    },
  },
}
```

## Configuration

| Option | Type | Default | Description |
|---|---|---|---|
| `enabled` | `boolean` | `true` | Global switch |
| `ft_ignore` | `string[]` | `{ 'dashboard', ... }` | Filetypes that do not render the status column |
| `bt_ignore` | `string[]` | `{ 'terminal', 'nofile', 'prompt' }` | Buftypes that do not render it |
| `refresh` | `integer` | `50` | Sign-cache flush interval in milliseconds |
| `fold.open` | `string` | `` | Icon for a foldable start line |
| `fold.close` | `string` | `` | Icon for a closed fold |
| `git.A` | `{ text, hl }` | `{ '▎', 'VVGitAdded' }` | Added-line glyph and highlight |
| `git.C` | `{ text, hl }` | `{ '▎', 'VVGitModified' }` | Changed-line glyph and highlight |
| `git.D` | `{ text, hl }` | `{ '󰆐', 'VVGitDeleted' }` | Deleted-line glyph and highlight |

### Built-in Git diff

On `BufReadPost`, `BufWritePost`, `FocusGained`, and related events, the plugin parses `git diff --cached` and `git diff` concurrently. Non-Git repositories and untracked files are ignored silently. The gutter does not update continuously while typing; save with `:w` to refresh it.

### How shrinking works

Neovim automatically grows a status column during redraw but does not shrink it. Growth therefore uses normal redraws. Shrinking is dispatched precisely after Git refreshes, `DiagnosticChanged` events debounced through `vv-utils.timer.debounce`, and fold changes caused by mouse actions or ufo mappings such as `zR`, `zM`, `zr`, and `zm`.

Those events call `nvim__redraw{statuscolumn}` to force width recalculation. Marks have no corresponding event, so the sign-cache heartbeat controlled by `refresh` provides the fallback.
