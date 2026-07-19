-- 点击分发：构造统一事件上下文，依次执行槽位回调、订阅回调和默认折叠行为

local M = {}

local targets = {} ---@type table<integer, VVStatusColClickTarget>
local listeners = {} ---@type VVStatusColClickCallback[]

---@param value table<integer, VVStatusColClickTarget>
function M.configure(value)
  targets = value
end

---@param callback VVStatusColClickCallback
function M.on_click(callback)
  if type(callback) ~= 'function' then
    error('vv-statuscol: click listener must be a function')
  end

  listeners[#listeners + 1] = callback
end

---@param callback VVStatusColClickCallback
---@param ctx VVStatusColClickContext
---@return boolean
local function run(callback, ctx)
  local ok, handled = pcall(callback, ctx)
  if ok then return handled == true end

  vim.notify('vv-statuscol: click callback failed: ' .. tostring(handled), vim.log.levels.ERROR)
  return true
end

---@param minwid integer
---@param clicks integer
---@param button string
---@param mods string
---@return VVStatusColClickContext?
local function context(minwid, clicks, button, mods)
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 then return end
  if not vim.api.nvim_win_is_valid(pos.winid) then return end

  vim.api.nvim_win_set_cursor(pos.winid, { pos.line, 0 })
  local target = targets[minwid] or targets[1] or { segment = 'gutter' }

  return {
    segment = target.segment,
    win = pos.winid,
    buf = vim.api.nvim_win_get_buf(pos.winid),
    line = pos.line,
    column = pos.column,
    clicks = clicks,
    button = button,
    mods = mods,
  }
end

---@param ctx VVStatusColClickContext
local function default(ctx)
  if ctx.button ~= 'l' or ctx.clicks ~= 1 then return end

  vim.api.nvim_win_call(ctx.win, function()
    if vim.fn.foldlevel(ctx.line) > 0 then
      vim.cmd('silent! normal! za')
    end
  end)
  pcall(vim.api.nvim__redraw, { win = ctx.win, statuscolumn = true })
end

---@param minwid integer
---@param clicks integer
---@param button string
---@param mods string
function M.dispatch(minwid, clicks, button, mods)
  local ctx = context(minwid, clicks, button, mods)
  if not ctx then return end

  local target = targets[minwid]
  if target and target.on_click and run(target.on_click, ctx) then return end

  for _, listener in ipairs(listeners) do
    if run(listener, ctx) then return end
  end

  default(ctx)
end

return M
