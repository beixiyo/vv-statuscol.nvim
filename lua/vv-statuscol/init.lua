-- vv-statuscol: 自定义状态列（mark / sign / 行号 / fold / git）
--
-- 布局：[mark 2w][sign 2w][%= lnum][ ][fold 1w][git 1w]
--
-- 设计参考 snacks.statuscolumn：
--   * 每行按 type 分槽（mark / sign / git），同 type 多 sign 取 priority 最高
--   * sign 段是 catch-all：诊断 / DAP / 任意 extmark sign 都落这里
--   * git 段由 vv-statuscol.git 独占（内建行级 diff，不依赖 gitsigns）
--   * fold 通过 FFI 读 fold_info，绕开 foldcolumn 渲染依赖
--   * 点击 gutter 任意位置：foldlevel > 0 则 toggle 折叠

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
local did_setup = false

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

local function line_signs(buf, lnum)
  local bs = sign_cache[buf]
  if not bs then
    bs = build_buf_signs(buf)
    sign_cache[buf] = bs
  end
  return bs[lnum] or {}
end

-- 暴露给 git 子模块：内部 markers 变化后 flush 字符串缓存 + 重绘
---@param buf? integer
function M.flush_cache(buf)
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

local function render_fold(win, lnum)
  if vim.wo[win].foldcolumn == '0' then return ' ' end
  local info = fold_info(win, lnum)
  if not info or info.level == 0 then return ' ' end
  if info.lines > 0 then
    return '%#VVStatusColFold#' .. (config.fold.close or '') .. '%*'
  elseif info.start == lnum then
    return '%#VVStatusColFold#' .. (config.fold.open or '') .. '%*'
  end
  return ' '
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

  -- wrapped / virtual line：只保留右对齐锚点，不渲染内容
  if vim.v.virtnum ~= 0 then
    return '    %= '
  end

  local show_signs = vim.wo[win].signcolumn ~= 'no'
  local s = line_signs(buf, vim.v.lnum)

  -- git 槽由内建 vv-statuscol.git 独占（不依赖 gitsigns 等外部插件）
  local git_entry = require('vv-statuscol.git').symbol(buf, vim.v.lnum)

  local parts = {
    icon(s.mark, 2),
    show_signs and icon(s.sign, 2) or '  ',
    render_lnum(win),
    ' ',
    render_fold(win, vim.v.lnum),
    show_signs and icon(git_entry, 1) or ' ',
  }
  return "%@v:lua.require'vv-statuscol'.click_fold@" .. table.concat(parts) .. '%T'
end

local function cached_get()
  local win = vim.g.statusline_winid
  local buf = vim.api.nvim_win_get_buf(win)
  local key = string.format('%d:%d:%d:%d:%d',
    win, buf, vim.v.lnum, vim.v.virtnum ~= 0 and 1 or 0, vim.v.relnum)
  local hit = result_cache[key]
  if hit then return hit end
  local ok, ret = pcall(M._get)
  if not ok then return '' end
  result_cache[key] = ret
  return ret
end

function M.get() return cached_get() end

function M.click_fold()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 then return end
  vim.api.nvim_win_set_cursor(pos.winid, { pos.line, 0 })
  vim.api.nvim_win_call(pos.winid, function()
    if vim.fn.foldlevel(pos.line) > 0 then
      vim.cmd('silent! normal! za')
    end
  end)
end

function M.setup(opts)
  if did_setup then return end
  config = vim.tbl_deep_extend('force', defaults, opts or {})

  require('vv-statuscol.hl').setup()
  require('vv-statuscol.git').configure(config.git)
  require('vv-statuscol.git').attach()

  -- foldcolumn='1' 作为 fold 段的启用 flag（FFI 已绕开实际渲染依赖）
  if vim.o.foldcolumn == '0' then vim.opt.foldcolumn = '1' end

  local timer = assert((vim.uv or vim.loop).new_timer())
  timer:start(config.refresh, config.refresh, function()
    sign_cache, result_cache = {}, {}
  end)

  local aug = vim.api.nvim_create_augroup('VVStatusCol', { clear = true })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = aug,
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

  vim.o.statuscolumn = "%!v:lua.require'vv-statuscol'.get()"
  did_setup = true
end

return M
