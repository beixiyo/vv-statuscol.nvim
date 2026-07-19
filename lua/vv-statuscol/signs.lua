-- 标记数据：收集 buffer mark 与 extmark sign，并维护按 buffer 缓存

local M = {}

local cache = {}
local enabled = { mark = true, sign = true }
local empty = { map = {}, has_mark = false, has_sign = false }

---@param buf integer
---@return table<integer, table<string, table>>
local function collect(buf)
  local result = {}

  if enabled.mark then
    for _, list in ipairs({ vim.fn.getmarklist(buf), vim.fn.getmarklist() }) do
      for _, mark in ipairs(list) do
        if mark.pos[1] == buf and mark.mark:match("^'[a-zA-Z]$") then
          local lnum = mark.pos[2]
          if lnum > 0 then
            result[lnum] = result[lnum] or {}
            result[lnum].mark = result[lnum].mark or {
              text = mark.mark:sub(2, 2),
              hl = 'VVStatusColMark',
            }
          end
        end
      end
    end
  end

  if enabled.sign then
    local extmarks = vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, {
      details = true,
      type = 'sign',
    })
    for _, extmark in ipairs(extmarks) do
      local lnum = extmark[2] + 1
      local details = extmark[4]
      local text = details.sign_text
      if text and text ~= '' then
        local entry = {
          text = text:gsub('%s', ''),
          hl = details.sign_hl_group,
          priority = details.priority or 0,
        }
        result[lnum] = result[lnum] or {}
        local current = result[lnum].sign
        if not current or (current.priority or 0) < entry.priority then
          result[lnum].sign = entry
        end
      end
    end
  end

  return result
end

---@param value table<string, boolean>
function M.configure(value)
  enabled = value
  M.reset()
end

---@param buf integer
---@return { map: table, has_mark: boolean, has_sign: boolean }
function M.data(buf)
  if not enabled.mark and not enabled.sign then return empty end

  local data = cache[buf]
  if data then return data end

  local map = collect(buf)
  local has_mark = false
  local has_sign = false
  for _, entry in pairs(map) do
    if entry.mark then has_mark = true end
    if entry.sign then has_sign = true end
    if has_mark and has_sign then break end
  end

  data = { map = map, has_mark = has_mark, has_sign = has_sign }
  cache[buf] = data
  return data
end

---@param buf integer
function M.clear(buf)
  cache[buf] = nil
end

function M.reset()
  cache = {}
end

return M
