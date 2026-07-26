-- vv-statuscol 对外入口：配置模块并管理后台资源生命周期

local click = require('vv-statuscol.click')
local git = require('vv-statuscol.git')
local layout = require('vv-statuscol.layout')
local renderer = require('vv-statuscol.renderer')
local signs = require('vv-statuscol.signs')

local M = {}

local defaults = {
  enabled = true,
  ft_ignore = {},
  bt_ignore = { 'help', 'nofile', 'prompt', 'quickfix', 'terminal' },
  refresh = 50,
  fold = {
    open = '',
    close = '',
    show_nested_level = false,
  },
  git = {
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

local function reset_caches()
  signs.reset()
  renderer.reset()
end

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

  vim.opt.foldcolumn = 'auto:1'
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

local function restore_options()
  if not saved_options then return end

  for name, value in pairs(saved_options) do
    if owned_options and vim.o[name] == owned_options[name] then vim.o[name] = value end
  end
  saved_options = nil
  owned_options = nil
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

---@param opts? VVStatusColConfig
function M.setup(opts)
  if enabled then M.disable() end

  config = vim.tbl_deep_extend('force', defaults, opts or {})
  layout_state = layout.configure(config.layout)

  click.configure(layout_state.targets)
  signs.configure(layout_state.enabled.left)
  renderer.configure(config, layout_state)
  require('vv-statuscol.hl').setup()
  git.configure(config.git)

  if config.enabled then M.enable() end

  vim.api.nvim_create_user_command('VVStatusColEnable', M.enable, { force = true })
  vim.api.nvim_create_user_command('VVStatusColDisable', M.disable, { force = true })
  vim.api.nvim_create_user_command('VVStatusColToggle', M.toggle, { force = true })
end

---@class VVStatusColConfig
---@field enabled? boolean 是否启用状态列 @default true
---@field ft_ignore? string[] 忽略的 filetype 列表；外部传入时整体覆盖默认值 @default {}
---@field bt_ignore? string[] 忽略的 buftype 列表；外部传入时整体覆盖默认值 @default { 'help', 'nofile', 'prompt', 'quickfix', 'terminal' }
---@field refresh? integer 缓存刷新间隔（ms） @default 50
---@field fold? VVStatusColFoldConfig 折叠栏配置 @default { open = '', close = '', show_nested_level = false }
---@field git? table<string, { text: string, hl: string }> Git 行级 diff 图标与高亮 @default 使用 VVGitAdded、VVGitModified 与 VVGitDeleted
---@field layout? VVStatusColLayout 内置槽位顺序与点击回调 @default { left = { 'mark', 'sign' }, right = { 'staged', 'unstaged', 'fold' } }

---@alias VVStatusColLeftSegment 'mark'|'sign'
---@alias VVStatusColRightSegment 'staged'|'unstaged'|'fold'
---@alias VVStatusColSegment 'gutter'|VVStatusColLeftSegment|VVStatusColRightSegment
---@alias VVStatusColClickCallback fun(ctx: VVStatusColClickContext): boolean?

---@class VVStatusColFoldConfig
---@field open? string 展开折叠图标 @default ''
---@field close? string 关闭折叠图标 @default ''
---@field show_nested_level? boolean 折叠栏过窄时显示嵌套层数数字 @default false

---@class VVStatusColLayout
---@field left (VVStatusColLeftSegment|VVStatusColLayoutItem)[] 左侧槽位
---@field right (VVStatusColRightSegment|VVStatusColLayoutItem)[] 右侧槽位

---@class VVStatusColLayoutItem
---@field segment VVStatusColLeftSegment|VVStatusColRightSegment 内置槽位名称
---@field on_click? VVStatusColClickCallback 点击该槽位时调用；返回 true 可停止事件传播

---@class VVStatusColClickTarget
---@field segment VVStatusColSegment
---@field on_click? VVStatusColClickCallback

---@class VVStatusColClickContext
---@field segment VVStatusColSegment 点击的槽位
---@field win integer 点击的窗口
---@field buf integer 点击窗口中的 buffer
---@field line integer 点击行号
---@field column integer 点击列号
---@field clicks integer 连续点击次数
---@field button string 鼠标按钮
---@field mods string 修饰键

return M
