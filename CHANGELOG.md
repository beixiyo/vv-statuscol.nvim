# Changelog

## 0.1.5 - 2026-10-07

### Changed

- 折叠列默认固定一格（`foldcolumn=1`），避免原生 `auto:1` 反复扫描折叠树拖慢长文件滚动；新增 `fold.auto_width`

## 0.1.4 - 2026-07-29

### Changed

- staged Git 轨道默认向状态列背景混合 70%，与保持原色的 unstaged 轨道形成清晰层级

## 0.1.3 - 2026-07-26

### Added

- `on_click()` 返回可重复调用的 disposer，可在重新配置或禁用时释放点击订阅

### Fixed

- 禁用时恢复原有 `statuscolumn`、`foldcolumn` 与 `fillchars`，已被其他插件接管的选项保留新值
- 重复 `setup()` 完整释放旧资源后应用新配置，并安全重建命令
- Git 查询期间的新刷新不再丢失，旧结果作废并按最新 buffer 来源重新查询
- 点击监听器可在事件分发期间安全释放自身或其他监听器，剩余监听器保持顺序
- 自定义渲染错误不再被静默转换为空状态列

## 0.1.2 - 2026-07-19

### Fixed

- 折叠栏改用 Neovim 原生 `%C` 与 `foldcolumn=auto:1`，不再依赖内部 ABI，修复切换 buffer 后折叠栏误隐藏及 2000 行之后折叠不显示

### Added

- 新增 `fold.show_nested_level`，控制折叠栏过窄时显示嵌套层数数字，默认关闭

## 0.1.1 - 2026-07-19

### Changed

- `ft_ignore` 默认改为空列表，`bt_ignore` 默认覆盖 `help`、`nofile`、`prompt`、`quickfix`、`terminal`；自定义列表整体替换默认值
- 特殊 buffer 跳过状态列扫描，fold 槽移至 Git 槽之后以在窄栏优先保留折叠图标

### Added

- 新增 `layout.left` / `layout.right`，支持排序、隐藏槽位及通过 `{ segment, on_click }` 设置槽位点击回调
- 点击事件提供位置、窗口、buffer 与鼠标上下文；返回 `true` 停止传播，默认折叠行为仅响应左键单击

### Breaking

- 删除旧内部入口 `click_fold()` / `_flush_cache()`，外部集成改用 `on_click()` / `refresh()`

## 0.1.0 - 2026-07-13

### Changed

- mark / sign / Git / fold 段无内容时收为零宽，诊断、Git 或折叠变化后及时收窄；配合原生 `signcolumn=no`、`foldcolumn=0` 避免额外空槽
- 状态列末尾固定留一格，避免折叠或 Git 图标贴住正文
- fold 槽按整窗折叠结构保持恒定宽度，避免同屏行号跳动
- `zR` / `zM` / `zr` / `zm`（ufo）后即时刷新折叠图标

### Fixed

- 新增 `refresh_visible()`，在 `TermClose`、`TermLeave` 或 `User VVGitStatusChanged` 后刷新当前 tab 的可见 buffer，避免外部 Git 变更后标记滞留
- buffer 销毁后 Git 异步结果不再写回，避免标记泄漏及 buffer 编号复用时串显
- 切换状态列相关窗口选项及原生折叠开合后即时更新，不再显示陈旧内容
- 禁用插件时停止 Git 监听与刷新计时器，不再执行后台查询和无效重绘
