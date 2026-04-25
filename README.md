# vv-statuscol.nvim

轻量自定义状态列，设计参考 [snacks.statuscolumn](https://github.com/folke/snacks.nvim/blob/main/lua/snacks/statuscolumn.lua)

## 布局

```
[mark 2w] [sign 2w] %= [lnum] [ ] [fold 1w] [git 1w]
```

| 段 | 内容 | 来源 |
|---|---|---|
| mark | a-zA-Z 字母（最高优先 buf-local） | `vim.fn.getmarklist` |
| sign | LSP 诊断 / DAP 断点 / 其它非 git 的 extmark sign | `nvim_buf_get_extmarks(type='sign')` |
| lnum | 行号（支持 `number` / `relativenumber` 混合模式） | 原生 |
| fold | NerdFont fold_open / fold_closed | FFI `fold_info` |
| git | 内建 line-level diff（新增/修改/删除），不依赖 gitsigns | `git diff -U0 HEAD -- <file>` async |

## 行为

- 每行一个 sign 槽位；同槽多 sign 按 `priority` 高者优先
- 点击 gutter 任意位置：若所在行 `foldlevel > 0` 则 `za` toggle 折叠
- virtnum（wrapped / virtual text 行）只保留右对齐锚点，不渲染任何内容
- `ft_ignore` / `bt_ignore` 命中的 buffer 直接返回空串（dashboard / explorer / terminal 等）
- 50ms 周期性 flush sign 缓存，兼顾性能与实时性

### Git 行级 diff

内建 `vv-statuscol.git` 子模块，**不依赖 gitsigns**：

- 事件驱动：`BufReadPost` / `BufWritePost` / `FocusGained` 触发 `git diff -U0 HEAD -- <path>`，异步
- 产出 per-line marker：`A`（新增）/ `C`（修改）/ `D`（删除）
- glyph 固定：`▎`（A/C）、`󰆐`（D）
- hl 走 `vv-utils.git` 的共享 VSCode Dark+ 调色板：`VVGitAdded` / `VVGitModified` / `VVGitDeleted`
- 非 git 仓库 / 未跟踪文件 → 静默不显示
- 编辑期间 gutter 不实时更新，直到 `:w`（简化实现，避免 per-keystroke 跑 git）

若用户同时启用 gitsigns 等外部插件：外部 sign 只会落在 `sign` 槽（左侧诊断位置），不会挤占 git 槽

## 安装

lazy.nvim：

```lua
{
  'beixiyo/vv-statuscol.nvim',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  opts = {},
}
```

带自定义 opts：

```lua
opts = {
  ft_ignore = { 'dashboard', 'trouble', 'qf' },
  fold = { open = '▾', close = '▸' },          -- 非 NerdFont 用户可改 Unicode 符号
  git  = {                                      -- 每个 kind 独立配 text + hl
    A = { text = '+', hl = 'DiagnosticOk' },
    D = { text = '-', hl = 'DiagnosticError' }, -- 只覆盖 A/D，C 用默认
  },
  refresh = 100,
}
```

## 配置项

| 字段 | 默认 | 说明 |
|---|---|---|
| `ft_ignore` | `{dashboard, vv-explorer, vv-task-panel, trouble, toggleterm, help, lazy, mason, checkhealth, qf}` | 这些 filetype 的 buffer 完全不渲染状态列 |
| `bt_ignore` | `{terminal, nofile, prompt}` | 同上，按 buftype |
| `refresh` | `50` | sign 缓存 flush 周期（ms） |
| `fold.open` | `` (NerdFont caret-down, U+F078) | 可折叠起始行的图标 |
| `fold.close` | `` (NerdFont caret-right, U+F054) | 已折叠行的图标 |
| `git.A` | `{ text='▎', hl='VVGitAdded' }` | 新增行 glyph 与高亮组 |
| `git.C` | `{ text='▎', hl='VVGitModified' }` | 修改行 |
| `git.D` | `{ text='󰆐', hl='VVGitDeleted' }` | 删除行 |

## 依赖

- Neovim 0.10+（`nvim_buf_get_extmarks(type='sign')` 语义、`foldinfo_T` ABI）
- `vv-utils.hl` + `vv-utils.git`（高亮注册 + VVGit* 调色板）
- NerdFont 字体（fold / git 默认图标是 PUA 码位；无 NerdFont 时传 `opts.fold` / `opts.git` 覆盖）

## 为什么不用 statuscol.nvim

statuscol.nvim（690 行）做了 sign 段的任意编排 + 多种 FFI 调用；本 vendor 的配置场景只需要固定 5 段布局 + catch-all sign 分流，~200 行 snacks-style 足够。

## 高亮

`vv-utils.hl` 注册 augroup `VVStatusColHL`：

| 组 | 默认 link | 用途 |
|---|---|---|
| `VVStatusColMark` | `DiagnosticHint` | mark 字母 |
| `VVStatusColFold` | `Folded` | fold 图标 |

Git 段统一 link 到 `vv-utils.git` 注册的 VSCode Dark+ 调色板：

| 组 | 颜色 | 对应 |
|---|---|---|
| `VVGitAdded` | `#81b88b`（灰绿） | 新增 |
| `VVGitModified` | `#e2c08d`（黄） | 修改 |
| `VVGitDeleted` | `#c74e39`（红） | 删除 |

sign 段（诊断 / DAP / 其它非 git 的 extmark sign）沿用各插件自带的 `sign_hl_group`（如 `DiagnosticSignError`），无需本 vendor 注册

## FFI 说明

`fold_info` 是 Neovim 内部符号，非公开 API。升级 nvim 若该结构体变化会炸；`statuscol.nvim` / `snacks.statuscolumn` 都用同样方式，属于社区既定做法

## Testing

Smoke test (zero deps, runs in `-u NONE`):

```bash
nvim --headless -u NONE -l tests/test_smoke.lua
```

Expected: trailing line `X passed, 0 failed`.
