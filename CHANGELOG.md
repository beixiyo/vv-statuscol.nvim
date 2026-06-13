# Changelog

## [Unreleased]

### Changed

- **左侧栏按内容动态收宽**：mark / sign / git 三段改为「整 buffer 有内容才占满宽、否则收成 0 宽」，无标记/诊断/改动的文件左栏只剩行号；fold 段无折叠时同样收 0。配合把原生 `signcolumn` 设 `no`、`foldcolumn` 设 `0`（两者不走 statuscolumn 渲染，置位只会各白占 2 列 / 1 列）。statuscolumn 宽度「只随重绘自动变宽、不自动变窄」，故诊断清空（`DiagnosticChanged`，经 80ms `vv-utils.timer.debounce` 合并打字时的成串 republish）、git 标记变化、折叠开合后均显式 `nvim__redraw{statuscolumn}` 把列收回。`result_cache` 键随之从「窗口选项」改为「`number`/`relativenumber` + 各段是否有内容（`has_mark`/`has_sign`/git）」
- **末尾恒留 1 格右留白**：动态收宽后 git 段收 0，原本靠 git 段空格充当的「字形↔正文」间距消失，导致折叠三角 / git 竖条贴住正文；现在 statuscolumn 末尾固定补 1 格
- **fold 段改为「窗口折叠结构」级恒定宽度**：此前 fold 字形逐行出现（只折叠起始行有），而行号经 `%=` 右对齐，导致折叠行的行号被往左挤、同屏行号参差。现按 `fold_info.level > 0`（与开合无关，仅看是否有折叠结构，早退 + 上限 2000 行扫描、按 win+changedtick 缓存）判定整窗是否预留 1 格 fold 槽：有结构则每行恒留 1 格（无字形行填空格），行号右侧宽度稳定不跳；无折叠文件该列收 0
- **键盘开合折叠即时刷新**：`zR`/`zM`/`zr`/`zm`（ufo）执行后调用 `vv-statuscol._flush_cache()` + `nvim__redraw{statuscolumn}`，折叠三角字形立即更新，不必等 50ms 缓存心跳

### Fixed

- **行级 diff 不刷新（外部变更）**：commit 移动 HEAD 后 `git diff HEAD` 才变，但此前只在 `FocusGained` 刷新——外部工具（ClaudeCode/Codex 等）在 nvim 内嵌终端里跑 git 时焦点没离开 nvim 进程，`FocusGained` 不触发，标记滞留。现增订 `TermClose`/`TermLeave` 与 vv-git 的 `User VVGitStatusChanged`，统一经新增的 `refresh_visible()` 刷新当前 tab 内所有可见 buffer

- git 异步回调（rev-parse / `git diff -U0`）在 buffer 已 wipe 后仍写回 `markers[bufnr]`，导致已关闭 buffer 的标记复活、随开关文件单调泄漏、复用 bufnr 时 gutter 串显上一个文件的 diff；两个回调写入前均加 `nvim_buf_is_loaded(bufnr)` 守卫，失效则清 markers 并退出
- `result_cache` 键此前只含 `win:buf:lnum:virtnum:relnum`，未纳入影响渲染的窗口选项（`signcolumn` / `number` / `relativenumber` / `foldcolumn`），切换这些选项后最长 50ms 渲染陈旧串；现把四项折进缓存键，切换即时生效
- `disable()` 此前只清空 `statuscolumn`，未停掉 `VVStatusColGit` autocmd 与 50ms 刷新 timer，禁用后每次读写/聚焦仍 spawn git 子进程跑 diff 并对已无状态列的窗口做无意义重绘；现 `enable()`/`disable()` 统一管理后台资源（git autocmd、刷新 timer、`BufWipeout` augroup）的挂载与释放

### Refactored

- git 根探测改用 vv-utils.git.root_async
