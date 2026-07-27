-- 状态列布局：校验槽位配置、分配点击目标并按用户顺序拼接渲染结果

local M = {}

M.default_click_id = 1

local segments = {
  left = { mark = true, sign = true },
  right = { staged = true, unstaged = true, fold = true },
}

---@param layout VVStatusColLayout
---@return VVStatusColLayoutState
function M.configure(layout)
  if type(layout) ~= 'table' then error('vv-statuscol: layout must be a table') end

  for side in pairs(layout) do
    if not segments[side] then
      error('vv-statuscol: unknown layout section: ' .. tostring(side))
    end
  end

  ---@type VVStatusColLayoutState
  local state = {
    left = {},
    right = {},
    enabled = { left = {}, right = {} },
    targets = {
      [M.default_click_id] = { segment = 'gutter' },
    },
  }
  local click_id = M.default_click_id

  for _, side in ipairs({ 'left', 'right' }) do
    local entries = layout[side]
    if not vim.islist(entries) then
      error('vv-statuscol: layout.' .. side .. ' must be a list')
    end

    for _, entry in ipairs(entries) do
      local segment
      local on_click

      if type(entry) == 'string' then
        segment = entry
      elseif type(entry) == 'table' then
        segment = entry.segment
        on_click = entry.on_click
      end

      if not segments[side][segment] then
        error('vv-statuscol: invalid ' .. side .. ' segment: ' .. tostring(segment))
      end
      if state.enabled[side][segment] then
        error('vv-statuscol: duplicate ' .. side .. ' segment: ' .. segment)
      end
      if on_click ~= nil and type(on_click) ~= 'function' then
        error('vv-statuscol: on_click for ' .. segment .. ' must be a function')
      end

      click_id = click_id + 1
      local item = { segment = segment, click_id = click_id, on_click = on_click }
      state[side][#state[side] + 1] = item
      state.enabled[side][segment] = true
      state.targets[click_id] = item
    end
  end

  return state
end

---@param parts string[]
---@param items VVStatusColLayoutStateItem[]
---@param rendered table<string, string>
function M.append(parts, items, rendered)
  for _, item in ipairs(items) do
    local text = rendered[item.segment] or ''
    if text ~= '' then
      parts[#parts + 1] = M.clickable(text, item.click_id)
    end
  end
end

---@param text string
---@param click_id integer
---@return string
function M.clickable(text, click_id)
  if text == '' then return '' end

  return string.format(
    "%%%d@v:lua.require'vv-statuscol'.click@%s%%T",
    click_id,
    text
  )
end

return M
