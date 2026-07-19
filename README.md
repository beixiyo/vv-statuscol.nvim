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

[statuscol.nvim](https://github.com/luukvbaal/statuscol.nvim) provides arbitrary sign-segment composition and several FFI calls. This plugin uses responsibility-focused modules to provide content-aware segment widths, configurable layouts and click events, plus built-in line-level Git diffs without gitsigns. Its fold segment uses Neovim's native `%C` item and does not access internal ABI.

## Dual Git tracks

Normal file windows show two independent line-level states. The left Git column represents staged changes from `HEAD` to the index; the right column represents unstaged changes from the index to the worktree. Both columns can be colored on the same line. Staged line numbers are mapped onto the current worktree buffer, so earlier insertions and deletions do not leave stale index coordinates.

`vv-git` diff and result windows hide these tracks through a window-local flag because scrollbar markers and diff coloring already represent the changes there. The same buffer still shows both tracks in normal editing windows.

### Content-aware width

Unlike status columns that reserve fixed blank slots, every mark, sign, Git, and fold segment has dynamic width:

- A segment collapses to zero when the entire buffer or window has no content of that kind
- A clean file with no marks, diagnostics, Git changes, or folds shows only line numbers
- Width is stable across the whole buffer or window, with Neovim managing fold width per window, so right-aligned line numbers do not jump between rows

Set native `signcolumn` to `no` because the plugin renders mark, sign, and Git cells itself. The fold segment uses Neovim's native `%C` item, and `setup()` sets `foldcolumn=auto:1` automatically.

### Layout

```text
[mark] [sign] %= [lnum] [ ] [staged][unstaged][fold] [ ]
```

The fold cell is intentionally placed after the Git cells. When Neovim reaches the maximum status-column width, content is truncated from the left, so the fold open/close icon remains visible before Git markers.

## Installation

```lua
{
  'beixiyo/vv-statuscol.nvim',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  event = { 'BufReadPost', 'BufNewFile' },
  opts = {
    enabled = true,
    ft_ignore = {},
    bt_ignore = { 'help', 'nofile', 'prompt', 'quickfix', 'terminal' },
    refresh = 50,
    fold = {
      open = '',
      close = '',
      show_nested_level = false,
    },
    layout = {
      left = { 'mark', 'sign' },
      right = {
        'staged',
        'unstaged',
        {
          segment = 'fold',
          on_click = function(ctx)
            print(ctx.segment, ctx.win, ctx.buf, ctx.line)
          end,
        },
      },
    },
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
| `ft_ignore` | `string[]` | `{}` | Filetypes that do not render the status column |
| `bt_ignore` | `string[]` | `{ 'help', 'nofile', 'prompt', 'quickfix', 'terminal' }` | Buftypes that do not render it |
| `refresh` | `integer` | `50` | Sign-cache flush interval in milliseconds |
| `fold.open` | `string` | `` | Icon for a foldable start line |
| `fold.close` | `string` | `` | Icon for a closed fold |
| `fold.show_nested_level` | `boolean` | `false` | Show numeric nesting levels when the fold column is too narrow |
| `layout.left` | `('mark'\|'sign'\|table)[]` | `{ 'mark', 'sign' }` | Left-side segment order and optional click callbacks |
| `layout.right` | `('staged'\|'unstaged'\|'fold'\|table)[]` | `{ 'staged', 'unstaged', 'fold' }` | Right-side segment order and optional click callbacks |
| `git.A` | `{ text, hl }` | `{ '▎', 'VVGitAdded' }` | Added-line glyph and highlight |
| `git.C` | `{ text, hl }` | `{ '▎', 'VVGitModified' }` | Changed-line glyph and highlight |
| `git.D` | `{ text, hl }` | `{ '󰆐', 'VVGitDeleted' }` | Deleted-line glyph and highlight |

User-provided `ft_ignore` and `bt_ignore` lists replace their defaults rather than extending them. The default buftype filter covers standard special buffers without coupling vv-statuscol to specific UI plugins; use `ft_ignore` only for additional filetype-specific exceptions.

Each layout entry can be a segment name or `{ segment = '...', on_click = function(ctx) ... end }`. A side can omit a segment to hide it, and a user-provided `left` or `right` list replaces that side's default list.

`ctx` contains `segment`, `win`, `buf`, `line`, `column`, `clicks`, `button`, and `mods`. `button` distinguishes `l`, `r`, `m`, and other mouse buttons; `clicks` distinguishes single, double, and further consecutive clicks.

Events flow through the segment `on_click`, global listeners registered with `require('vv-statuscol').on_click(...)`, and finally the built-in default behavior. Returning `true` from any callback stops propagation. The default behavior responds only to a single left click and toggles a fold when one exists on the target line. The default layout does not install segment callbacks.

### Built-in Git diff

On `BufReadPost`, `BufWritePost`, `FocusGained`, and related events, the plugin parses `git diff --cached` and `git diff` concurrently. Non-Git repositories and untracked files are ignored silently. The gutter does not update continuously while typing; save with `:w` to refresh it.

### How shrinking works

Neovim automatically grows a status column during redraw but does not shrink it. Growth therefore uses normal redraws. Shrinking is dispatched precisely after Git refreshes, `DiagnosticChanged` events debounced through `vv-utils.timer.debounce`, and fold changes caused by mouse actions or ufo mappings such as `zR`, `zM`, `zr`, and `zm`.

Those events call `nvim__redraw{statuscolumn}` to force width recalculation. Marks have no corresponding event, so the sign-cache heartbeat controlled by `refresh` provides the fallback.

The fold segment reads the current window state live through native `%C`. It does not scan buffers or cache fold results, so buffer switches and folds below an arbitrary line limit cannot leave it stale.

Integrations that place signs directly can call `require('vv-statuscol').refresh(buf)`. It invalidates the buffer's sign cache and flushes the status-column redraw immediately.
