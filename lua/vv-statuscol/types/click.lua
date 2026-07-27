---@alias VVStatusColClickCallback fun(ctx: VVStatusColClickContext): boolean?

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

---@class VVStatusColClickListener
---@field callback VVStatusColClickCallback
---@field active boolean
