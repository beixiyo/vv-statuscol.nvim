<h1 align="center">vv-statuscol.nvim</h1>

<p align="center">
  <em>轻量自定义状态列 — 固定五段布局、内建 git line-level diff</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Neovim-0.10+-57A143?style=flat-square&logo=neovim&logoColor=white" alt="Requires Neovim 0.10+" />
  <img src="https://img.shields.io/badge/Lua-2C2D72?style=flat-square&logo=lua&logoColor=white" alt="Lua" />
</p>

---

## 为什么要这个插件

[statuscol.nvim](https://github.com/luukvbaal/statuscol.nvim)（690 行）做了 sign 段的任意编排 + 多种 FFI 调用。本插件只需固定五段布局，~200 行 snacks-style 足够，且**内建 git line-level diff**（不依赖 gitsigns）

### 布局

```
[mark 2w] [sign 2w] %= [lnum] [ ] [fold 1w] [git 1w]
```

## 安装

```lua
{
  'beixiyo/vv-statuscol.nvim',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  event = { 'BufReadPost', 'BufNewFile' },
  opts = {
    enabled = true,
    ft_ignore = {                -- 不渲染状态列的 filetype
      'dashboard', 'vv-explorer', 'vv-task-panel', 'trouble',
      'toggleterm', 'help', 'lazy', 'mason', 'checkhealth', 'qf',
    },
    bt_ignore = { 'terminal', 'nofile', 'prompt' },
    refresh = 50,                -- sign 缓存 flush 周期（ms）
    fold = {
      open  = '',              -- 可折叠起始行图标（NerdFont caret-down）
      close = '',              -- 已折叠行图标（NerdFont caret-right）
    },
    git = {
      A = { text = '▎', hl = 'VVGitAdded' },    -- 新增行
      C = { text = '▎', hl = 'VVGitModified' },  -- 修改行
      D = { text = '󰆐', hl = 'VVGitDeleted' },   -- 删除行
    },
  },
}
```

## 配置

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | `boolean` | `true` | 全局开关 |
| `ft_ignore` | `string[]` | `{ 'dashboard', ... }` | 这些 filetype 的 buffer 不渲染状态列 |
| `bt_ignore` | `string[]` | `{ 'terminal', 'nofile', 'prompt' }` | 同上，按 buftype |
| `refresh` | `integer` | `50` | sign 缓存 flush 周期（ms） |
| `fold.open` | `string` | `` | 可折叠起始行的图标 |
| `fold.close` | `string` | `` | 已折叠行的图标 |
| `git.A` | `{ text, hl }` | `{ '▎', 'VVGitAdded' }` | 新增行 glyph + 高亮组 |
| `git.C` | `{ text, hl }` | `{ '▎', 'VVGitModified' }` | 修改行 |
| `git.D` | `{ text, hl }` | `{ '󰆐', 'VVGitDeleted' }` | 删除行 |

### 内建 Git diff

事件驱动：`BufReadPost` / `BufWritePost` / `FocusGained` 触发 `git diff -U0 HEAD` 异步解析。非 git 仓库 / 未跟踪文件静默不显示。编辑期间 gutter 不实时更新，直到 `:w`
