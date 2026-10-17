-- 状态列宽度变化通知：每个窗口在重绘后读取真实 textoff，与上次不同才通知订阅者
-- 状态列宽度在渲染之后才可能变化（git / sign 异步到达、行号位数增长），原生不会为此触发 WinResized

local M = {}

local textoffs = {} ---@type table<integer, integer>
local pending = {} ---@type table<integer, true>
local listeners = {} ---@type VVStatusColWidthListener[]

---分发给当前仍有效的订阅者；回调报错只通知，不影响其余订阅者
---@param ctx VVStatusColWidthContext
local function dispatch(ctx)
  for _, listener in ipairs(vim.list_slice(listeners)) do
    if listener.active then
      local ok, err = pcall(listener.callback, ctx)
      if not ok then
        vim.notify('vv-statuscol: width callback failed: ' .. tostring(err), vim.log.levels.ERROR)
      end
    end
  end
end

---重绘结束后读取窗口真实 textoff；覆盖槽位列数、行号位数、numberwidth、foldcolumn 等一切来源
---@param win integer
---@param buf integer
local function check(win, buf)
  pending[win] = nil
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then return end

  local textoff = vim.fn.getwininfo(win)[1].textoff
  if textoffs[win] == textoff then return end

  textoffs[win] = textoff
  dispatch({ win = win, buf = buf })
end

---statuscolumn 求值时调用：同一窗口合并成一次 vim.schedule，延后到重绘之后再比较 textoff
---（求值期间不能改窗口与 buffer，且此时 textoff 可能还是旧值）
---@param win integer
---@param buf integer
function M.track(win, buf)
  if pending[win] then return end

  pending[win] = true
  vim.schedule(function()
    check(win, buf)
  end)
end

---@param win integer
function M.forget(win)
  textoffs[win] = nil
  pending[win] = nil
end

---清空所有基线；下一次观察会把当前宽度视为变化并通知一次
function M.reset()
  textoffs = {}
  pending = {}
end

---@param callback VVStatusColWidthCallback
---@return fun() disposer 可安全重复调用
function M.on_change(callback)
  if type(callback) ~= 'function' then
    error('vv-statuscol: width listener must be a function')
  end

  local listener = { callback = callback, active = true }
  listeners[#listeners + 1] = listener

  return function()
    if not listener.active then return end
    listener.active = false
    listeners = vim.tbl_filter(function(item) return item.active end, listeners)
  end
end

return M
