<div align="center">

<h1>vv-statuscol.nvim</h1>

<a href="./README.md">English</a> | 中文

<img src="./docs/assets/vv-statuscol.png" alt="vv-statuscol 演示" width="900" />

想要我的 Neovim 配置？查看 <a href="https://github.com/beixiyo/dotfiles">dotfiles</a>

  <em>轻量自定义状态列 — 按内容动态收宽、内建 git line-level diff</em>

<br />

  <img src="https://img.shields.io/badge/Neovim-0.10+-57A143?style=flat-square&logo=neovim&logoColor=white" alt="Requires Neovim 0.10+" />
  <img src="https://img.shields.io/badge/Lua-2C2D72?style=flat-square&logo=lua&logoColor=white" alt="Lua" />
</div>

---

## 依赖

- [vv-utils.nvim](https://github.com/beixiyo/vv-utils.nvim) — 必须，提供共享 Git diff 与高亮能力
- [Git](https://github.com/git/git) — 可选，仅 staged / unstaged 状态列轨道需要

## 为什么要这个插件

[statuscol.nvim](https://github.com/luukvbaal/statuscol.nvim) 支持 sign 段任意编排与多种 FFI 调用。本插件采用按职责拆分的模块结构，重点提供 **各段按内容动态收宽**、**可配置布局与点击事件**、以及不依赖 gitsigns 的 **内建 git line-level diff**。折叠栏直接复用 Neovim 原生 `%C`，不读取内部 ABI

## Git 双轨规则

普通文件窗口同时显示两套互不覆盖的行级状态：Git 区域左列表示
`HEAD → Index` 的 **staged** 改动，右列表示 `Index → Worktree` 的
**unstaged** 改动。同一行暂存后再次修改时两列可以同时染色；staged 行号会先映射到
当前 Worktree buffer，前方继续增删行也不会直接套用过期的 Index 行号

`vv-git` 的 diff / result 窗口会通过 window-local 标记隐藏这两列：面板内由滚动条
marker 与 diff 染色表达改动已经足够；同一 buffer 在普通编辑窗口中的双轨不受影响

### 核心特性：按内容动态收宽

与多数状态列（含 snacks）的「固定宽度、空槽填空格」不同，本插件把 mark / sign / git / fold **每一段都做成动态宽度**：

- 整个 buffer/窗口**没有**该类内容时，对应段**收成 0 宽**，statuscolumn 自动收窄
- 无标记、无诊断、无 git 改动、无折叠的干净文件，左栏**只剩行号**，不浪费一格
- 宽度判定是「整体级」恒定（mark/sign/git 按 buffer，fold 由 Neovim 按窗口管理），所以**同屏每行宽度一致**，右对齐的行号不会因个别行多/少一格而左右抖动

> mark、sign 与 Git 槽由插件渲染，建议把原生 `signcolumn` 设为 `"no"`。fold 槽使用 Neovim 原生 `%C`，`setup()` 会自动设置 `foldcolumn=auto:1`，无需外部配置

### 布局

```
[mark] [sign] %= [lnum] [ ] [staged][unstaged][fold] [ ]
```

fold 槽刻意放在 Git 槽之后。Neovim 达到 statuscolumn 最大宽度时会从左侧开始截断，因此空间不足时优先保留 fold 开合图标，Git 标记先让位

## 安装

```lua
{
  'beixiyo/vv-statuscol.nvim',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  event = { 'BufReadPost', 'BufNewFile' },
  opts = {
    enabled = true,
    ft_ignore = {},              -- 需要额外排除的 filetype
    bt_ignore = { 'help', 'nofile', 'prompt', 'quickfix', 'terminal' },
    refresh = 50,                -- sign 缓存 flush 周期（ms）
    fold = {
      open  = '',              -- 可折叠起始行图标（NerdFont caret-down）
      close = '',              -- 已折叠行图标（NerdFont caret-right）
      show_nested_level = false, -- 折叠栏过窄时显示嵌套层数数字
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
| `ft_ignore` | `string[]` | `{}` | 这些 filetype 的 buffer 不渲染状态列 |
| `bt_ignore` | `string[]` | `{ 'help', 'nofile', 'prompt', 'quickfix', 'terminal' }` | 同上，按 buftype |
| `refresh` | `integer` | `50` | sign 缓存 flush 周期（ms） |
| `fold.open` | `string` | `` | 可折叠起始行的图标 |
| `fold.close` | `string` | `` | 已折叠行的图标 |
| `fold.show_nested_level` | `boolean` | `false` | 折叠栏过窄时是否显示嵌套层数数字 |
| `layout.left` | `('mark'\|'sign'\|table)[]` | `{ 'mark', 'sign' }` | 左侧槽位顺序与可选点击回调 |
| `layout.right` | `('staged'\|'unstaged'\|'fold'\|table)[]` | `{ 'staged', 'unstaged', 'fold' }` | 右侧槽位顺序与可选点击回调 |
| `git.A` | `{ text, hl }` | `{ '▎', 'VVGitAdded' }` | 新增行 glyph + 高亮组 |
| `git.C` | `{ text, hl }` | `{ '▎', 'VVGitModified' }` | 修改行 |
| `git.D` | `{ text, hl }` | `{ '󰆐', 'VVGitDeleted' }` | 删除行 |

外部传入的 `ft_ignore` 与 `bt_ignore` 列表会整体覆盖默认值，不会与默认列表合并。默认按 buftype 覆盖 Neovim 的标准特殊 buffer，避免 vv-statuscol 依赖具体 UI 插件名称；仅在需要额外按 filetype 排除时配置 `ft_ignore`

layout 条目既可直接写槽位名，也可写成 `{ segment = '...', on_click = function(ctx) ... end }`。省略槽位即可隐藏它；外部传入的 `left` 或 `right` 列表会整体覆盖对应侧默认列表

`ctx` 包含 `segment`、`win`、`buf`、`line`、`column`、`clicks`、`button` 与 `mods`。其中 `button` 可区分 `l`、`r`、`m` 等鼠标按钮，`clicks` 可区分单击、双击或更多连续点击

事件依次经过槽位 `on_click`、`require('vv-statuscol').on_click(...)` 注册的全局监听器、最后是内建默认行为。任意回调返回 `true` 即停止后续传播；默认行为只响应左键单击，并在目标行存在折叠时切换开合。插件默认布局没有预置槽位回调

### 内建 Git diff

事件驱动：`BufReadPost` / `BufWritePost` / `FocusGained` 等事件并行解析
`git diff --cached` 与 `git diff`。非 Git 仓库 / 未跟踪文件静默不显示；编辑期间 gutter
不实时更新，直到 `:w`

### 关于动态收窄的实现

statuscolumn 的宽度「只随重绘自动**变宽**、不自动**变窄**」。因此**变宽**白嫖自然重绘（按需即时）

**收窄**则靠事件精确派发：git 刷新、`DiagnosticChanged`（经 `vv-utils.timer.debounce` 合并打字时 LSP 的成串 republish）、折叠开合（鼠标点击 + ufo `zR`/`zM`/`zr`/`zm`）后

显式 `nvim__redraw{statuscolumn}` 强制重算宽度。mark 无对应事件，由 `refresh` 周期（默认 50ms）的缓存心跳兜底

fold 槽由原生 `%C` 实时读取当前窗口的折叠状态，不扫描 buffer，也不缓存折叠结果，因此不受 buffer 切换或文件长度影响

直接放置 sign 的集成可调用 `require('vv-statuscol').refresh(buf)`，它会清除该 buffer 的 sign 缓存并立即刷新状态列
