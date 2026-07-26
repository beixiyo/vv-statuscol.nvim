-- 点击分发：构造统一事件上下文，依次执行槽位回调、订阅回调和默认折叠行为

local M = {}

local targets = {} ---@type table<integer, VVStatusColClickTarget>
local listeners = {} ---@type VVStatusColClickListener[]
local dispatch_depth = 0
local needs_compaction = false

local function compact_listeners()
  if dispatch_depth > 0 then
    needs_compaction = true
    return
  end

  local active = {}
  for _, listener in ipairs(listeners) do
    if listener.active then
      active[#active + 1] = listener
    end
  end
  listeners = active
  needs_compaction = false
end

---@param value table<integer, VVStatusColClickTarget>
function M.configure(value)
  targets = value
end

---@param callback VVStatusColClickCallback
function M.on_click(callback)
  if type(callback) ~= 'function' then
    error('vv-statuscol: click listener must be a function')
  end

  local listener = {
    callback = callback,
    active = true,
  }
  listeners[#listeners + 1] = listener

  return function()
    if not listener.active then return end
    listener.active = false
    compact_listeners()
  end
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

  local handled = false
  dispatch_depth = dispatch_depth + 1
  for _, listener in ipairs(listeners) do
    if listener.active and run(listener.callback, ctx) then
      handled = true
      break
    end
  end
  dispatch_depth = dispatch_depth - 1
  if dispatch_depth == 0 and needs_compaction then compact_listeners() end

  if not handled then default(ctx) end
end

---@class VVStatusColClickListener
---@field callback VVStatusColClickCallback
---@field active boolean

return M
