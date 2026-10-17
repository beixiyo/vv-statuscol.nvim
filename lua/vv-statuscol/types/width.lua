---@alias VVStatusColWidthCallback fun(ctx: VVStatusColWidthContext)

---@class VVStatusColWidthContext
---@field win integer 状态列宽度发生变化的窗口
---@field buf integer 该窗口中的 buffer

---@class VVStatusColWidthListener
---@field callback VVStatusColWidthCallback
---@field active boolean
