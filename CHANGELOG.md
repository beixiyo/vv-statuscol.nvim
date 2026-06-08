# Changelog

## [Unreleased]

### Fixed

- **行级 diff 不刷新（外部变更）**：commit 移动 HEAD 后 `git diff HEAD` 才变，但此前只在 `FocusGained` 刷新——外部工具（ClaudeCode/Codex 等）在 nvim 内嵌终端里跑 git 时焦点没离开 nvim 进程，`FocusGained` 不触发，标记滞留。现增订 `TermClose`/`TermLeave` 与 vv-git 的 `User VVGitStatusChanged`，统一经新增的 `refresh_visible()` 刷新当前 tab 内所有可见 buffer

- git 异步回调（rev-parse / `git diff -U0`）在 buffer 已 wipe 后仍写回 `markers[bufnr]`，导致已关闭 buffer 的标记复活、随开关文件单调泄漏、复用 bufnr 时 gutter 串显上一个文件的 diff；两个回调写入前均加 `nvim_buf_is_loaded(bufnr)` 守卫，失效则清 markers 并退出
- `result_cache` 键此前只含 `win:buf:lnum:virtnum:relnum`，未纳入影响渲染的窗口选项（`signcolumn` / `number` / `relativenumber` / `foldcolumn`），切换这些选项后最长 50ms 渲染陈旧串；现把四项折进缓存键，切换即时生效
- `disable()` 此前只清空 `statuscolumn`，未停掉 `VVStatusColGit` autocmd 与 50ms 刷新 timer，禁用后每次读写/聚焦仍 spawn git 子进程跑 diff 并对已无状态列的窗口做无意义重绘；现 `enable()`/`disable()` 统一管理后台资源（git autocmd、刷新 timer、`BufWipeout` augroup）的挂载与释放

### Refactored

- git 根探测改用 vv-utils.git.root_async
