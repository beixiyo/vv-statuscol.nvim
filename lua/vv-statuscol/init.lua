-- vv-statuscol 对外入口：配置模块并管理后台资源生命周期

local click = require('vv-statuscol.click')
local git = require('vv-statuscol.git')
local layout = require('vv-statuscol.layout')
local renderer = require('vv-statuscol.renderer')
local signs = require('vv-statuscol.signs')
local width = require('vv-statuscol.width')

local M = {}
require('vv-statuscol.types')

---@type VVStatusColConfig
local defaults = {
  enabled = true,
  ft_ignore = {},
  bt_ignore = { 'help', 'nofile', 'prompt', 'quickfix', 'terminal' },
  refresh = 50,
  fold = {
    auto_width = false,
    open = '',
    close = '',
    show_nested_level = false,
  },
  git = {
    staged_dim = 0.7,
    A = { text = '▎', hl = 'VVGitAdded' },
    C = { text = '▎', hl = 'VVGitModified' },
    D = { text = '󰆐', hl = 'VVGitDeleted' },
  },
  layout = {
    left = { 'mark', 'sign' },
    right = { 'staged', 'unstaged', 'fold' },
  },
}

local config = vim.deepcopy(defaults) ---@type VVStatusColConfig
local layout_state ---@type VVStatusColLayoutState
local enabled = false
local refresh_timer
local statuscol_augroup
local diagnostic_cancel
local statuscolumn = "%!v:lua.require'vv-statuscol'.get()"
local saved_options
local owned_options
local released_windows = {} ---@type integer[] 上次禁用时被还原的非当前窗口

local function reset_caches()
  signs.reset()
  renderer.reset()
end

---配置原生折叠槽；默认固定一格，避免行高计算反复遍历折叠树
local function configure_fold_column()
  if not layout_state.enabled.right.fold then
    vim.opt.foldcolumn = '0'
    return
  end

  local function normalize(value)
    if value == '' then return ' ' end
    if vim.fn.strdisplaywidth(value) ~= 1 then
      error('vv-statuscol: fold icons must occupy exactly one display cell')
    end
    return value
  end

  vim.opt.foldcolumn = config.fold.auto_width and 'auto:1' or '1'
  local fold_chars = {
    foldopen = normalize(config.fold.open),
    foldclose = normalize(config.fold.close),
    foldsep = ' ',
  }
  if config.fold.show_nested_level then
    vim.opt.fillchars:remove('foldinner')
  else
    fold_chars.foldinner = ' '
  end
  vim.opt.fillchars:append(fold_chars)
end

local function save_options()
  if saved_options then return end
  saved_options = {
    statuscolumn = vim.o.statuscolumn,
    foldcolumn = vim.o.foldcolumn,
    fillchars = vim.o.fillchars,
  }
end

-- 'statuscolumn' 与 'foldcolumn' 是窗口局部选项：vim.o 只写全局值和当前窗口，
-- 其余窗口各自持有创建时复制的值，必须逐个处理
local WINDOW_OPTIONS = { 'statuscolumn', 'foldcolumn' }

---@param win integer
---@param from table<string, string> 仅当窗口当前值与之一致才改写，保留用户或其它插件单独设置的窗口
---@param to table<string, string>
---@return boolean changed
local function swap_window_options(win, from, to)
  local changed = false
  for _, name in ipairs(WINDOW_OPTIONS) do
    if vim.wo[win][name] == from[name] and from[name] ~= to[name] then
      vim.wo[win][name] = to[name]
      changed = true
    end
  end
  return changed
end

local function restore_options()
  if not saved_options then return end

  local current = vim.api.nvim_get_current_win()
  if owned_options then
    -- 记下被还原的窗口，重新启用时原样接回；禁用期间新开的窗口只能随当前窗口或全局值走
    released_windows = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if win ~= current and swap_window_options(win, owned_options, saved_options) then
        released_windows[#released_windows + 1] = win
      end
    end
  end

  for name, value in pairs(saved_options) do
    if owned_options and vim.o[name] == owned_options[name] then vim.o[name] = value end
  end
  saved_options = nil
  owned_options = nil
end

---把禁用时还原过的窗口重新接回；期间被改成别的值的窗口不动
local function reclaim_windows()
  for _, win in ipairs(released_windows) do
    if vim.api.nvim_win_is_valid(win) then swap_window_options(win, saved_options, owned_options) end
  end
  released_windows = {}
end

local function start_resources()
  if layout_state.enabled.right.staged or layout_state.enabled.right.unstaged then
    git.attach()
  end

  refresh_timer = assert(vim.uv.new_timer())
  refresh_timer:start(config.refresh, config.refresh, reset_caches)

  statuscol_augroup = vim.api.nvim_create_augroup('VVStatusCol', { clear = true })

  if layout_state.enabled.left.sign then
    local redraw
    redraw, diagnostic_cancel = require('vv-utils.timer').debounce(function()
      renderer.reset()
      pcall(vim.api.nvim__redraw, { statuscolumn = true })
    end, 80)

    vim.api.nvim_create_autocmd('DiagnosticChanged', {
      group = statuscol_augroup,
      callback = function(args)
        signs.clear(args.buf)
        redraw()
      end,
    })
  end

  vim.api.nvim_create_autocmd('WinClosed', {
    group = statuscol_augroup,
    callback = function(args)
      width.forget(tonumber(args.match))
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = statuscol_augroup,
    callback = function(args)
      signs.clear(args.buf)
      renderer.clear_buffer(args.buf)
    end,
  })
end

local function stop_resources()
  git.detach()

  if diagnostic_cancel then
    diagnostic_cancel()
    diagnostic_cancel = nil
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

  reset_caches()
  width.reset()
end

---清除指定 buffer 的渲染缓存并立即刷新状态列
---@param buf? integer @default 当前 buffer
function M.refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  signs.clear(buf)
  renderer.clear_buffer(buf)
  pcall(vim.api.nvim__redraw, {
    buf = buf,
    statuscolumn = true,
    flush = true,
  })
end

---@return string
function M.get()
  return renderer.get()
end

---@param minwid integer
---@param clicks integer
---@param button string
---@param mods string
function M.click(minwid, clicks, button, mods)
  click.dispatch(minwid, clicks, button, mods)
end

---订阅所有状态列点击；回调返回 true 可停止后续监听器与默认行为
---@param callback VVStatusColClickCallback
---@return fun() disposer 可安全重复调用
function M.on_click(callback)
  return click.on_click(callback)
end

---订阅状态列宽度变化（sign、git 轨道异步出现或消失、行号选项切换）
---回调在重绘之后异步执行，此时 `getwininfo(win)[1].textoff` 已是新值；首次渲染只建立基线，不触发
---依赖 textoff 做布局的虚拟文本（如 render-markdown 的表格换行）可在此触发重渲
---@param callback VVStatusColWidthCallback
---@return fun() disposer 可安全重复调用
function M.on_width_change(callback)
  return width.on_change(callback)
end

function M.enable()
  if enabled then return end

  enabled = true
  save_options()
  configure_fold_column()
  start_resources()
  vim.o.statuscolumn = statuscolumn
  owned_options = {
    statuscolumn = vim.o.statuscolumn,
    foldcolumn = vim.o.foldcolumn,
    fillchars = vim.o.fillchars,
  }
  reclaim_windows()
end

function M.disable()
  if not enabled then return end

  enabled = false
  stop_resources()
  restore_options()
end

function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
end

---@param opts? VVStatusColOpts
function M.setup(opts)
  if enabled then M.disable() end

  config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  if type(config.git.staged_dim) ~= 'number'
      or config.git.staged_dim < 0
      or config.git.staged_dim > 1 then
    error('vv-statuscol: git.staged_dim must be a number between 0 and 1')
  end
  layout_state = layout.configure(config.layout)

  click.configure(layout_state.targets)
  signs.configure(layout_state.enabled.left)
  renderer.configure(config, layout_state)

  require('vv-statuscol.hl').setup(config.git)
  git.configure(config.git)

  if config.enabled then M.enable() end

  vim.api.nvim_create_user_command('VVStatusColEnable', M.enable, { force = true })
  vim.api.nvim_create_user_command('VVStatusColDisable', M.disable, { force = true })
  vim.api.nvim_create_user_command('VVStatusColToggle', M.toggle, { force = true })
end

---读取当前生效配置的副本；修改返回值不影响插件内部状态
---@return VVStatusColConfig
function M.get_config()
  return vim.deepcopy(config)
end

return M
