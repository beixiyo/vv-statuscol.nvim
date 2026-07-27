---@alias VVStatusColLeftSegment 'mark'|'sign'
---@alias VVStatusColRightSegment 'staged'|'unstaged'|'fold'
---@alias VVStatusColSegment 'gutter'|VVStatusColLeftSegment|VVStatusColRightSegment

---@class VVStatusColLayout
---@field left (VVStatusColLeftSegment|VVStatusColLayoutItem)[] 左侧槽位
---@field right (VVStatusColRightSegment|VVStatusColLayoutItem)[] 右侧槽位

---@class VVStatusColLayoutItem
---@field segment VVStatusColLeftSegment|VVStatusColRightSegment 内置槽位名称
---@field on_click? VVStatusColClickCallback 点击该槽位时调用；返回 true 可停止事件传播

---@class VVStatusColLayoutState
---@field left VVStatusColLayoutStateItem[]
---@field right VVStatusColLayoutStateItem[]
---@field enabled table<'left'|'right', table<string, boolean>>
---@field targets table<integer, VVStatusColClickTarget>

---@class VVStatusColLayoutStateItem: VVStatusColClickTarget
---@field click_id integer
