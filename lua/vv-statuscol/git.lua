-- 行级 git diff：按 buffer 跑 `git diff -U0 -- <path>`（工作树 vs 暂存区，即未暂存改动；
-- 故 stage 后该文件标记即清），产出 [lnum] -> 'A'|'C'|'D'
-- 事件驱动刷新（BufReadPost / BufWritePost / FocusGained / TermClose / TermLeave /
-- User VVGitStatusChanged），不做 per-keystroke 增量
-- 非 git 仓库 / 未跟踪文件 → 返回空 markers，不打扰

local M = {}

local markers = {} --- @type table<integer, table<integer, 'A'|'C'|'D'>>
local pending = {} --- @type table<integer, boolean>

-- text + hl 全部由 init.lua defaults.git 经 M.configure() 单向注入；
-- 未 configure 前 symbol() 返回 nil（不渲染）
local GLYPHS = {}  ---@type table<'A'|'C'|'D', {text:string, hl:string}>

---@param cfg { A: {text:string, hl:string}, C: {text:string, hl:string}, D: {text:string, hl:string} }
function M.configure(cfg)
  GLYPHS.A, GLYPHS.C, GLYPHS.D = cfg.A, cfg.C, cfg.D
end

-- unified diff hunk header → 每行标记
-- 规则：
--   old=0, new>0  → 纯新增：new_start..new_start+new_len-1 标 A
--   new=0, old>0  → 纯删除：在 max(new_start,1) 标 D
--   old>0, new>0  → 修改：前 min 行标 C，超出部分按 new>old 补 A（new<old 的删除合并到最后 C）
---@param diff string
---@return table<integer, 'A'|'C'|'D'>
function M.parse(diff)
  local out = {}
  for line in (diff or ''):gmatch('[^\n]+') do
    local o_len_s, n_start_s, n_len_s =
      line:match('^@@ %-%d+,?(%d*) %+(%d+),?(%d*) @@')
    if n_start_s then
      local old_len = tonumber(o_len_s == '' and '1' or o_len_s) or 1
      local new_start = tonumber(n_start_s) or 0
      local new_len = tonumber(n_len_s == '' and '1' or n_len_s) or 1

      if new_len == 0 and old_len > 0 then
        out[math.max(new_start, 1)] = 'D'
      elseif new_len > 0 and old_len == 0 then
        for i = new_start, new_start + new_len - 1 do out[i] = 'A' end
      elseif new_len > 0 and old_len > 0 then
        local overlap = math.min(old_len, new_len)
        for i = new_start, new_start + overlap - 1 do out[i] = 'C' end
        if new_len > old_len then
          for i = new_start + overlap, new_start + new_len - 1 do out[i] = 'A' end
        end
      end
    end
  end
  return out
end

---@param bufnr integer
function M.refresh(bufnr)
  if bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  if pending[bufnr] then return end
  if not vim.api.nvim_buf_is_loaded(bufnr) then return end

  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' or vim.fn.filereadable(path) == 0 then
    markers[bufnr] = nil
    return
  end
  local root = vim.fs.dirname(path)
  pending[bufnr] = true

  require('vv-utils.git').root_async(root, function(toplevel)
    -- buffer 可能在 rev-parse 在途时被 wipe：失效则清理并退出，勿再 spawn diff
    if not vim.api.nvim_buf_is_loaded(bufnr) then
      pending[bufnr] = nil
      markers[bufnr] = nil
      return
    end
    if not toplevel then
      pending[bufnr] = nil
      markers[bufnr] = nil
      return
    end
    vim.system(
      { 'git', '-C', root, '--no-pager', 'diff', '-U0', '--no-color',
        '--no-ext-diff', '--', path },
      { text = true },
      vim.schedule_wrap(function(d)
        pending[bufnr] = nil
        -- diff 在途时 buffer 已 wipe：清理 markers 后退出，避免写回陈旧数据 / 复用 bufnr 脏读
        if not vim.api.nvim_buf_is_loaded(bufnr) then
          markers[bufnr] = nil
          return
        end
        if d.code ~= 0 then
          markers[bufnr] = nil
          return
        end
        markers[bufnr] = M.parse(d.stdout or '')
        -- 让父模块 flush 字符串缓存，再触发 statuscolumn 重绘
        local ok, parent = pcall(require, 'vv-statuscol')
        if ok and parent._flush_cache then parent._flush_cache(bufnr) end
        if vim.api.nvim_buf_is_loaded(bufnr) then
          pcall(vim.api.nvim__redraw, { buf = bufnr, statuscolumn = true })
        end
      end))
  end)
end

---@param buf integer
---@param lnum integer
---@return {text:string, hl:string}?
function M.symbol(buf, lnum)
  local m = markers[buf]
  if not m then return nil end
  local kind = m[lnum]
  return kind and GLYPHS[kind]
end

--- buffer 是否存在任意行级 git 标记（供 statuscolumn 决定 git 段宽度：有则 1 列，无则 0）
---@param buf integer
---@return boolean
function M.has(buf)
  local m = markers[buf]
  return m ~= nil and next(m) ~= nil
end

---@param buf integer
function M.clear(buf)
  markers[buf] = nil
  pending[buf] = nil
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
  -- commit 移动 HEAD 后 `git diff HEAD` 才会变，故订阅这些事件后 commit 的标记能及时清
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
end

return M
