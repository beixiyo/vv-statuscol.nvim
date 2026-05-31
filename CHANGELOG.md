# Changelog

## [Unreleased]

### Fixed

- git 异步回调（rev-parse / `git diff -U0`）在 buffer 已 wipe 后仍写回 `markers[bufnr]`，导致已关闭 buffer 的标记复活、随开关文件单调泄漏、复用 bufnr 时 gutter 串显上一个文件的 diff；两个回调写入前均加 `nvim_buf_is_loaded(bufnr)` 守卫，失效则清 markers 并退出
- `result_cache` 键此前只含 `win:buf:lnum:virtnum:relnum`，未纳入影响渲染的窗口选项（`signcolumn` / `number` / `relativenumber` / `foldcolumn`），切换这些选项后最长 50ms 渲染陈旧串；现把四项折进缓存键，切换即时生效
- `disable()` 此前只清空 `statuscolumn`，未停掉 `VVStatusColGit` autocmd 与 50ms 刷新 timer，禁用后每次读写/聚焦仍 spawn git 子进程跑 diff 并对已无状态列的窗口做无意义重绘；现 `enable()`/`disable()` 统一管理后台资源（git autocmd、刷新 timer、`BufWipeout` augroup）的挂载与释放

### Refactored

- git 根探测改用 vv-utils.git.root_async
