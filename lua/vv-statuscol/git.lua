-- 行级 git diff：同时显示 HEAD→index（staged）与 index→worktree（unstaged）
-- staged marker 经 vv-utils.git 映射到当前 worktree buffer 行号，二者独立渲染，不互相覆盖
-- 事件驱动刷新（BufReadPost / BufWritePost / FocusGained / TermClose / TermLeave /
-- User VVGitStatusChanged），不做 per-keystroke 增量
-- 非 git 仓库 / 未跟踪文件 → 返回空 markers，不打扰

local M = {}

local markers = {} --- @type table<integer, vv-utils.git.DiffLineSets>
local pending = {} --- @type table<integer, integer>
local revisions = {} --- @type table<integer, integer>
local queued = {} --- @type table<integer, boolean>
local single_source = {} --- @type table<integer, boolean>
local lifecycle_epoch = 0

-- text + hl 全部由 init.lua defaults.git 经 M.configure() 单向注入；
-- 未 configure 前 symbol() 返回 nil（不渲染）
local GLYPHS = {}  ---@type table<'A'|'C'|'D', {text:string, hl:string}>

---@param cfg { A: {text:string, hl:string}, C: {text:string, hl:string}, D: {text:string, hl:string} }
function M.configure(cfg)
  GLYPHS.A, GLYPHS.C, GLYPHS.D = cfg.A, cfg.C, cfg.D
end

---@param bufnr integer
---@param revision integer
---@param epoch integer
---@param apply fun()
local function complete(bufnr, revision, epoch, apply)
  if lifecycle_epoch ~= epoch then return end

  local owns_request = pending[bufnr] == revision
  if owns_request then pending[bufnr] = nil end
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    M.clear(bufnr)
    return
  end

  if revisions[bufnr] ~= revision then
    if owns_request and queued[bufnr] then
      queued[bufnr] = nil
      M.refresh(bufnr)
    end
    return
  end
  if not owns_request then return end

  queued[bufnr] = nil
  apply()
  require('vv-statuscol').refresh(bufnr)
end

---@param bufnr integer
function M.refresh(bufnr)
  if bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  if not vim.api.nvim_buf_is_loaded(bufnr) then return end

  local revision = (revisions[bufnr] or 0) + 1
  local epoch = lifecycle_epoch

  revisions[bufnr] = revision
  if pending[bufnr] then
    queued[bufnr] = true
    return
  end

  local source = vim.b[bufnr].vv_git_diff_source
  if type(source) == 'table' and type(source.path) == 'string' and source.path ~= '' then
    pending[bufnr] = revision
    require('vv-utils.git').diff_lines(source.path, function(result)
      complete(bufnr, revision, epoch, function()
        markers[bufnr] = { staged = {}, unstaged = result or {} }
        single_source[bufnr] = true
      end)
    end, source)
    return
  end

  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' or vim.fn.filereadable(path) == 0 then
    markers[bufnr] = nil
    single_source[bufnr] = nil
    return
  end
  pending[bufnr] = revision
  require('vv-utils.git').diff_line_sets(path, function(sets)
    complete(bufnr, revision, epoch, function()
      markers[bufnr] = sets
      single_source[bufnr] = nil
    end)
  end)
end

---@param buf integer
---@param lnum integer
---@param mode 'staged'|'unstaged'
---@return {text:string, hl:string}?
function M.symbol(buf, lnum, mode)
  local sets = markers[buf]
  local kind = sets and sets[mode] and sets[mode][lnum]
  return kind and GLYPHS[kind]
end

---buffer 是否存在任意行级 git 标记（有则 staged / unstaged 双轨共 2 列，无则 0）
---@param buf integer
---@return boolean
function M.has(buf)
  local sets = markers[buf]
  return sets ~= nil
    and (next(sets.staged or {}) ~= nil or next(sets.unstaged or {}) ~= nil)
end

---@param buf integer
---@return { staged: boolean, unstaged: boolean }
function M.channels(buf)
  if not M.has(buf) then return { staged = false, unstaged = false } end
  if single_source[buf] then return { staged = false, unstaged = true } end
  return { staged = true, unstaged = true }
end

---@param buf integer
function M.clear(buf)
  markers[buf] = nil
  pending[buf] = nil
  revisions[buf] = (revisions[buf] or 0) + 1
  queued[buf] = nil
  single_source[buf] = nil
end

-- 刷新当前 tab 内所有可见窗口的 buffer
-- 用于「焦点回到 nvim / 退出内嵌终端 / vv-git 广播状态变更」这类不针对单个 buffer 的事件：
-- 这些事件的 args.buf 可能是终端/面板 buffer，refresh(args.buf) 没意义；改为刷新可见文件 buffer
local function refresh_visible()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
      M.refresh(buf)
    end
  end
end

function M.attach()
  local g = vim.api.nvim_create_augroup('VVStatusColGit', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost' }, {
    group = g,
    callback = function(args) M.refresh(args.buf) end,
  })
  -- 外部 git 状态变更 → 刷新可见 buffer 的行级 diff
  --   * FocusGained ——————————— 切回 nvim（独立终端里跑 git；FocusGained 只覆盖此场景）
  --   * TermClose/TermLeave ————— 退出内嵌终端（ClaudeCode/Codex 在 :terminal 里直接跑 git，
  --                               焦点没离开 nvim 进程，FocusGained 不 fire）
  --   * User VVGitStatusChanged — vv-git 的 stage/commit/push 等操作完成后广播（即时）
  -- commit 移动 HEAD 后 staged / unstaged 两侧都会变化，订阅后 marker 能及时重算
  vim.api.nvim_create_autocmd({ 'FocusGained', 'TermClose', 'TermLeave' }, {
    group = g,
    callback = function() refresh_visible() end,
  })
  vim.api.nvim_create_autocmd('User', {
    group = g,
    pattern = 'VVGitStatusChanged',
    callback = function() refresh_visible() end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = g,
    callback = function(args) M.clear(args.buf) end,
  })
  -- 启动时刷一遍已打开的 listed buffer
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
      M.refresh(buf)
    end
  end
end

--- 卸下 attach() 注册的 autocmd（供父模块 disable 时停掉后台 git diff）
function M.detach()
  pcall(vim.api.nvim_del_augroup_by_name, 'VVStatusColGit')
  lifecycle_epoch = lifecycle_epoch + 1

  local buffers = {}
  for buf in pairs(pending) do buffers[#buffers + 1] = buf end

  for _, buf in ipairs(buffers) do
    pending[buf] = nil
    revisions[buf] = (revisions[buf] or 0) + 1
    queued[buf] = nil
  end
end

return M
