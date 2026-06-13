-- vv-statuscol: 自定义状态列（mark / sign / 行号 / fold / git）
--
-- 布局：[mark][sign][%= lnum][ ][fold][git][ ]
--   各槽「按内容动态收宽」：整 buffer/窗口无该类内容时收成 0 宽（statuscolumn 自动收窄），
--   无标记/诊断/改动/折叠的文件左栏只剩行号。原生 signcolumn/foldcolumn 均设为 no/0（不走
--   statuscolumn 渲染，开着只白占列）。宽度判定都是「整体级」恒定（mark/sign/git 按 buffer、
--   fold 按窗口折叠结构），故同屏每行宽度一致，右对齐行号不会因个别行多/少一格而抖动
--
-- 设计参考 snacks.statuscolumn，但更进一步（独立各段 + 动态收宽 + 内建 git）：
--   * 每行按 type 分槽（mark / sign / git），同 type 多 sign 取 priority 最高
--   * sign 段是 catch-all：诊断 / DAP / 任意 extmark sign 都落这里
--   * git 段由 vv-statuscol.git 独占（内建行级 diff，不依赖 gitsigns）
--   * fold 通过 FFI 读 fold_info，绕开 foldcolumn 渲染依赖
--   * 点击 gutter 任意位置：foldlevel > 0 则 toggle 折叠
--   * statuscolumn 宽度「只随重绘自动变宽、不自动变窄」，故收窄靠事件精确派发：
--     git 刷新 / DiagnosticChanged（debounce）/ 折叠开合 后显式 nvim__redraw{statuscolumn}

local M = {}

-- ======================= FFI =======================
local ffi_lib
local ffi_ready

local function ffi_init()
  if ffi_ready ~= nil then return ffi_ready end
  ffi_ready = false
  local ok, ffi = pcall(require, 'ffi')
  if not ok then return false end
  local okd = pcall(ffi.cdef, [[
    typedef struct {} Error;
    typedef struct {} win_T;
    typedef struct {
      int start;
      int level;
      int llevel;
      int lines;
    } foldinfo_T;
    foldinfo_T fold_info(win_T* wp, int lnum);
    win_T *find_window_by_handle(int Window, Error *err);
  ]])
  if not okd then return false end
  ffi_lib = ffi
  ffi_ready = true
  return true
end

local function fold_info(win, lnum)
  if not ffi_init() then return nil end
  local err = ffi_lib.new('Error')
  local wp = ffi_lib.C.find_window_by_handle(win, err)
  if wp == nil then return nil end
  return ffi_lib.C.fold_info(wp, lnum)
end

-- ======================= Config =======================
-- NerdFont 默认图标：fold_open / fold_closed 用 FontAwesome 的 caret-down/right（最通用）
-- Git delete 用 nf-md-minus（和 gitsigns 一致的视觉）；add/change 用 U+258E 竖条（非 PUA）

---@class VVStatusColConfig
---@field enabled boolean 是否启用状态列 @default true
---@field ft_ignore string[] 忽略的文件类型列表 @default { 'dashboard', 'vv-explorer', ... }
---@field bt_ignore string[] 忽略的 buftype 列表 @default { 'terminal', 'nofile', 'prompt' }
---@field refresh integer 缓存刷新间隔（ms） @default 50
---@field fold { open: string, close: string } 折叠图标 @default { open = '', close = '' }
---@field git table<string, { text: string, hl: string }> Git 行级 diff 图标与高亮 @default { A = { text = '▎', hl = 'VVGitAdded' }, ... }

local defaults = {
  enabled = true,
  ft_ignore = {
    'dashboard', 'vv-explorer', 'vv-task-panel', 'trouble',
    'toggleterm', 'help', 'lazy', 'mason', 'checkhealth', 'qf',
  },
  bt_ignore = { 'terminal', 'nofile', 'prompt' },
  refresh = 50,
  fold = {
    open  = '',
    close = '',
  },
  git = {
    A = { text = '▎', hl = 'VVGitAdded' },    -- 新增
    C = { text = '▎', hl = 'VVGitModified' }, -- 修改
    D = { text = '󰆐', hl = 'VVGitDeleted' },  -- 删除
  },
}

local config = vim.deepcopy(defaults)
local sign_cache = {}
local result_cache = {}
local click_hooks = {}
local did_setup = false
local enabled = false
local stc_expr = "%!v:lua.require'vv-statuscol'.get()"

-- enable() 时创建、disable() 时释放的运行期资源（缓存刷新 timer + BufWipeout 清理 augroup）
local refresh_timer
local statuscol_augroup
-- DiagnosticChanged 防抖重绘的取消句柄（debounce 内部常驻 uv timer，disable 时须 cancel 防泄漏）
local diag_redraw_cancel

-- ======================= Signs =======================
local function build_buf_signs(buf)
  local out = {}
  -- marks: buf-local first（优先级更高），再补 global
  for _, lst in ipairs({ vim.fn.getmarklist(buf), vim.fn.getmarklist() }) do
    for _, m in ipairs(lst) do
      if m.pos[1] == buf and m.mark:match("^'[a-zA-Z]$") then
        local lnum = m.pos[2]
        if lnum > 0 then
          out[lnum] = out[lnum] or {}
          out[lnum].mark = out[lnum].mark or {
            text = m.mark:sub(2, 2),
            hl = 'VVStatusColMark',
          }
        end
      end
    end
  end

  -- extmark signs：全部进 sign 槽（诊断 / DAP / 其它）。git 槽由 vv-statuscol.git 独占
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, {
    details = true, type = 'sign',
  })
  for _, em in ipairs(extmarks) do
    local lnum = em[2] + 1
    local d = em[4]
    local text = d.sign_text
    if text and text ~= '' then
      local entry = {
        text = (text:gsub('%s', '')),
        hl = d.sign_hl_group,
        priority = d.priority or 0,
      }
      out[lnum] = out[lnum] or {}
      local cur = out[lnum].sign
      if not cur or (cur.priority or 0) < entry.priority then
        out[lnum].sign = entry
      end
    end
  end

  return out
end

-- buffer 级缓存：行 -> sign 映射 + 整 buffer 是否含 mark / sign 的标志位
-- 标志位让 statuscolumn 按「整个 buffer 有没有」决定槽宽（满宽 or 0），而非逐行/逐屏，
-- 这样不会因滚动到无标记区域就抖动，符合「出现才变宽、消失才收窄」
---@param buf integer
---@return { map: table, has_mark: boolean, has_sign: boolean }
local function buf_data(buf)
  local d = sign_cache[buf]
  if not d then
    local map = build_buf_signs(buf)
    local has_mark, has_sign = false, false
    for _, e in pairs(map) do
      if e.mark then has_mark = true end
      if e.sign then has_sign = true end
      if has_mark and has_sign then break end
    end
    d = { map = map, has_mark = has_mark, has_sign = has_sign }
    sign_cache[buf] = d
  end
  return d
end

local function line_signs(buf, lnum)
  return buf_data(buf).map[lnum] or {}
end

-- 暴露给 git 子模块：内部 markers 变化后 flush 字符串缓存 + 重绘
---@param buf? integer
function M._flush_cache(buf)
  if buf then sign_cache[buf] = nil end
  result_cache = {}
end

-- ======================= Renderers =======================
---@param entry? {text:string, hl?:string}
---@param width integer
local function icon(entry, width)
  if not entry then return string.rep(' ', width) end
  local text = vim.fn.strcharpart(entry.text or '', 0, width)
  local w = vim.fn.strchars(text)
  if w < width then text = text .. string.rep(' ', width - w) end
  if entry.hl and entry.hl ~= '' then
    return '%#' .. entry.hl .. '#' .. text .. '%*'
  end
  return text
end

-- fold 段直接由 FFI 读折叠状态自绘（不依赖原生 foldcolumn，故全局 foldcolumn 设 '0' 省掉那一列）
-- 无折叠的行返回 ''（而非空格），让 statuscolumn 在整屏都无折叠时把 fold 列收成 0 宽
local function render_fold(win, lnum)
  local info = fold_info(win, lnum)
  if not info or info.level == 0 then return '' end
  if info.lines > 0 then
    return '%#VVStatusColFold#' .. (config.fold.close or '') .. '%*'
  elseif info.start == lnum then
    return '%#VVStatusColFold#' .. (config.fold.open or '') .. '%*'
  end
  return ''
end

-- buffer 是否存在折叠「结构」（与开合无关：fold_info.level>0 在折叠展开时同样为真）
-- 有结构 → 整窗每行恒定预留 1 格 fold 槽（无字形的行填空格），否则「只有折叠起始行多出一格」
-- 会把右对齐的行号往左挤 → 同屏行号参差。早退 + 上限扫描：代码文件通常前几行就命中折叠；
-- 纯无折叠的大文件最多扫 FOLD_PROBE_MAX 行就判定为无。按 win + changedtick 缓存，每帧只扫一次
local FOLD_PROBE_MAX = 2000
local fold_has_cache = {} --- @type table<integer, { tick: integer, has: boolean }>
local function win_has_fold(win)
  if not vim.wo[win].foldenable then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  local tick = vim.b[buf].changedtick
  local c = fold_has_cache[win]
  if c and c.tick == tick then return c.has end

  local has = false
  local n = math.min(vim.api.nvim_buf_line_count(buf), FOLD_PROBE_MAX)
  for l = 1, n do
    local info = fold_info(win, l)
    if info and info.level > 0 then
      has = true
      break
    end
  end
  fold_has_cache[win] = { tick = tick, has = has }
  return has
end

local function render_lnum(win)
  local nu = vim.wo[win].number
  local rnu = vim.wo[win].relativenumber
  if not (nu or rnu) then return '' end
  local num
  if rnu and nu and vim.v.relnum == 0 then
    num = vim.v.lnum
  elseif rnu then
    num = vim.v.relnum
  else
    num = vim.v.lnum
  end
  return '%=' .. num
end

local function is_ignored(buf)
  local ft, bt = vim.bo[buf].filetype, vim.bo[buf].buftype
  for _, f in ipairs(config.ft_ignore) do
    if f == ft then return true end
  end
  for _, b in ipairs(config.bt_ignore) do
    if b == bt then return true end
  end
  return false
end

-- ======================= Entry =======================
function M._get()
  local win = vim.g.statusline_winid
  local buf = vim.api.nvim_win_get_buf(win)
  if is_ignored(buf) then return '' end

  local data = buf_data(buf)
  local git = require('vv-statuscol.git')
  local git_has = git.has(buf)

  -- 动态槽宽：整 buffer/窗口无该类内容时收成 0 宽，statuscolumn 自动收窄（避免空文件白占左栏）
  -- 四段宽度都是「整体级」恒定（mark/sign/git 按 buffer、fold 按窗口折叠结构），故同屏每行宽度一致，
  -- 右对齐的行号不会因个别行多/少一格而左右跳
  local mark_w = data.has_mark and 2 or 0
  local sign_w = data.has_sign and 2 or 0
  local git_w  = git_has and 1 or 0
  local fold_w = win_has_fold(win) and 1 or 0

  -- wrapped / virtual line：只保留右对齐锚点 + 与正常行一致的左右留白（末尾留白同正常行）
  if vim.v.virtnum ~= 0 then
    return string.rep(' ', mark_w + sign_w) .. '%= ' .. string.rep(' ', fold_w + git_w) .. ' '
  end

  local s = data.map[vim.v.lnum] or {}
  local git_entry = git_has and git.symbol(buf, vim.v.lnum) or nil

  -- fold 槽恒定 1 格（有折叠结构时）：本行有字形则画字形，无则填空格，保证行号右侧宽度稳定
  -- 末尾恒留 1 格：fold/git 动态收 0 后原本靠 git 段空格充当的「字形↔正文」间距会消失，补一格右留白
  local fold_part = ''
  if fold_w > 0 then
    local g = render_fold(win, vim.v.lnum)
    fold_part = g ~= '' and g or ' '
  end

  local parts = {
    mark_w > 0 and icon(s.mark, mark_w) or '',
    sign_w > 0 and icon(s.sign, sign_w) or '',
    render_lnum(win),
    ' ',
    fold_part,
    git_w > 0 and icon(git_entry, git_w) or '',
    ' ',
  }
  return "%@v:lua.require'vv-statuscol'.click_fold@" .. table.concat(parts) .. '%T'
end

local function cached_get()
  local win = vim.g.statusline_winid
  local buf = vim.api.nvim_win_get_buf(win)
  -- 渲染宽度依赖：number/relativenumber（行号段）+ 各槽是否有内容（mark/sign/git/fold 决定满宽 or 0）
  -- 不纳入键会在内容增减后命中陈旧串、宽度算错，直到 50ms timer 整体清空缓存才纠正
  local wo = vim.wo[win]
  local data = buf_data(buf)
  local git_has = require('vv-statuscol.git').has(buf)
  local opt_flags = string.format('%d%d%d%d%d%d',
    wo.number and 1 or 0,
    wo.relativenumber and 1 or 0,
    data.has_mark and 1 or 0,
    data.has_sign and 1 or 0,
    git_has and 1 or 0,
    win_has_fold(win) and 1 or 0)
  local key = string.format('%d:%d:%d:%d:%d:%s',
    win, buf, vim.v.lnum, vim.v.virtnum ~= 0 and 1 or 0, vim.v.relnum, opt_flags)
  local hit = result_cache[key]
  if hit then return hit end
  local ok, ret = pcall(M._get)
  if not ok then return '' end
  result_cache[key] = ret
  return ret
end

function M.get() return cached_get() end

---@param fn fun(pos: { winid: integer, line: integer }): boolean
function M.on_click(fn)
  click_hooks[#click_hooks + 1] = fn
end

function M.click_fold()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 then return end
  vim.api.nvim_win_set_cursor(pos.winid, { pos.line, 0 })

  for _, fn in ipairs(click_hooks) do
    if fn(pos) then return end
  end

  vim.api.nvim_win_call(pos.winid, function()
    if vim.fn.foldlevel(pos.line) > 0 then
      vim.cmd('silent! normal! za')
    end
  end)
  -- 折叠开合后 fold 列可能整屏消失，显式重算 statuscolumn 宽度让它收窄
  pcall(vim.api.nvim__redraw, { win = pos.winid, statuscolumn = true })
end

-- 挂载后台资源：git autocmd（异步 diff 刷新）、缓存刷新 timer、BufWipeout 清理 augroup
local function start_resources()
  require('vv-statuscol.git').attach()

  refresh_timer = assert((vim.uv or vim.loop).new_timer())
  refresh_timer:start(config.refresh, config.refresh, function()
    sign_cache, result_cache, fold_has_cache = {}, {}, {}
  end)

  statuscol_augroup = vim.api.nvim_create_augroup('VVStatusCol', { clear = true })

  -- 诊断增减会改变 sign 段宽度。statuscolumn 宽度「只随重绘自动变宽、不自动变窄」，
  -- 诊断清空后必须显式 nvim__redraw{statuscolumn} 才会把 sign 列收回去（否则卡在宽态）
  -- 变宽本就随自然重绘按需发生，这里只为「收窄」兜底，故用 debounce 合并打字时 LSP 成串
  -- 重发诊断的抖动——延迟收窄完全无感，却省掉每次 republish 都重算一遍 gutter 宽度
  local diag_redraw
  diag_redraw, diag_redraw_cancel = require('vv-utils.timer').debounce(function()
    result_cache = {}
    pcall(vim.api.nvim__redraw, { statuscolumn = true })
  end, 80)
  vim.api.nvim_create_autocmd('DiagnosticChanged', {
    group = statuscol_augroup,
    callback = function(args)
      sign_cache[args.buf] = nil
      diag_redraw()
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = statuscol_augroup,
    callback = function(args)
      sign_cache[args.buf] = nil
      local prefix = ':' .. args.buf .. ':'
      for k in pairs(result_cache) do
        if k:find(prefix, 1, true) then
          result_cache[k] = nil
        end
      end
    end,
  })
end

-- 释放后台资源：否则 disable 后每次读写/聚焦仍会 spawn git 子进程跑 diff 并对
-- 已无自定义状态列的窗口做无意义重绘，50ms timer 也仍在空转清缓存
local function stop_resources()
  require('vv-statuscol.git').detach()

  if diag_redraw_cancel then
    diag_redraw_cancel()
    diag_redraw_cancel = nil
  end

  if refresh_timer then
    refresh_timer:stop()
    if not refresh_timer:is_closing() then refresh_timer:close() end
    refresh_timer = nil
  end

  if statuscol_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, statuscol_augroup)
    statuscol_augroup = nil
  end

  sign_cache, result_cache, fold_has_cache = {}, {}, {}
end

function M.enable()
  if enabled then return end
  enabled = true
  start_resources()
  vim.o.statuscolumn = stc_expr
end

function M.disable()
  if not enabled then return end
  enabled = false
  vim.o.statuscolumn = ''
  stop_resources()
end

function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
end

function M.setup(opts)
  if did_setup then return end
  config = vim.tbl_deep_extend('force', defaults, opts or {})

  require('vv-statuscol.hl').setup()
  require('vv-statuscol.git').configure(config.git)

  -- fold 段由 statuscolumn 内 FFI 自绘，原生 foldcolumn 不参与渲染只会白占 1 列，故关掉
  vim.opt.foldcolumn = '0'

  -- 后台资源（git autocmd / 刷新 timer / BufWipeout augroup）的挂载与释放统一交给
  -- enable()/disable() 管理，确保 disable 后真正停掉 git diff 与重绘（见 #71）
  M.enable()
  did_setup = true

  vim.api.nvim_create_user_command('VVStatusColEnable', function() M.enable() end, {})
  vim.api.nvim_create_user_command('VVStatusColDisable', function() M.disable() end, {})
  vim.api.nvim_create_user_command('VVStatusColToggle', function() M.toggle() end, {})
end

return M
