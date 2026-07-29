---@class VVStatusColConfig
---@field enabled? boolean 是否启用状态列 @default true
---@field ft_ignore? string[] 忽略的 filetype 列表；外部传入时整体覆盖默认值 @default {}
---@field bt_ignore? string[] 忽略的 buftype 列表；外部传入时整体覆盖默认值 @default { 'help', 'nofile', 'prompt', 'quickfix', 'terminal' }
---@field refresh? integer 缓存刷新间隔（ms） @default 50
---@field fold? VVStatusColFoldConfig 折叠栏配置 @default { open = '', close = '', show_nested_level = false }
---@field git? VVStatusColGitConfig Git 行级 diff 图标、高亮与暂存轨道暗淡比例
---@field layout? VVStatusColLayout 内置槽位顺序与点击回调 @default { left = { 'mark', 'sign' }, right = { 'staged', 'unstaged', 'fold' } }

---@class VVStatusColFoldConfig
---@field open? string 展开折叠图标 @default ''
---@field close? string 关闭折叠图标 @default ''
---@field show_nested_level? boolean 折叠栏过窄时显示嵌套层数数字 @default false

---@class VVStatusColGitConfig
---@field staged_dim? number 暂存轨道向 StatusColumn 背景混合的比例，0 为原色，1 为完全融入背景 @default 0.7
---@field A? { text: string, hl: string } 新增行图标与高亮 @default { text = '▎', hl = 'VVGitAdded' }
---@field C? { text: string, hl: string } 修改行图标与高亮 @default { text = '▎', hl = 'VVGitModified' }
---@field D? { text: string, hl: string } 删除行图标与高亮 @default { text = '󰆐', hl = 'VVGitDeleted' }
