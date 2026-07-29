-- 状态列渲染：组合布局槽位并缓存最终 statuscolumn 字符串

local git = require('vv-statuscol.git')
local hl = require('vv-statuscol.hl')
local layout = require('vv-statuscol.layout')
local signs = require('vv-statuscol.signs')

local M = {}

local config = {}
local layout_state ---@type VVStatusColLayoutState
local result_cache = {}

---@param entry? { text: string, hl?: string }
---@param width integer
---@return string
local function icon(entry, width)
  if not entry then return string.rep(' ', width) end

  local text = vim.fn.strcharpart(entry.text or '', 0, width)
  local current_width = vim.fn.strchars(text)
  if current_width < width then
    text = text .. string.rep(' ', width - current_width)
  end
  if entry.hl and entry.hl ~= '' then
    return '%#' .. entry.hl .. '#' .. text .. '%*'
  end

  return text
end

---@param entry? { text: string, hl?: string }
---@return { text: string, hl?: string }?
local function staged_icon(entry)
  if not entry then return nil end
  return { text = entry.text, hl = entry.hl and hl.staged(entry.hl) or nil }
end

---@param win integer
---@return string
local function line_number(win)
  local number = vim.wo[win].number
  local relative = vim.wo[win].relativenumber
  if not number and not relative then return '' end

  local value
  if number and relative and vim.v.relnum == 0 then
    value = vim.v.lnum
  elseif relative then
    value = vim.v.relnum
  else
    value = vim.v.lnum
  end

  return '%=' .. value
end

---@param buf integer
---@return boolean
local function is_ignored(buf)
  local filetype = vim.bo[buf].filetype
  local buftype = vim.bo[buf].buftype

  for _, ignored in ipairs(config.ft_ignore) do
    if ignored == filetype then return true end
  end
  for _, ignored in ipairs(config.bt_ignore) do
    if ignored == buftype then return true end
  end

  return false
end

---@param ctx VVStatusColRenderContext
---@return string
local function render(ctx)
  local mark_width = layout_state.enabled.left.mark and ctx.data.has_mark and 2 or 0
  local sign_width = layout_state.enabled.left.sign and ctx.data.has_sign and 2 or 0
  local staged_width = layout_state.enabled.right.staged and ctx.git_channels.staged and 1 or 0
  local unstaged_width = layout_state.enabled.right.unstaged and ctx.git_channels.unstaged and 1 or 0
  local parts = {}

  if vim.v.virtnum ~= 0 then
    layout.append(parts, layout_state.left, {
      mark = string.rep(' ', mark_width),
      sign = string.rep(' ', sign_width),
    })
    parts[#parts + 1] = layout.clickable('%= ', layout.default_click_id)
    layout.append(parts, layout_state.right, {
      staged = string.rep(' ', staged_width),
      unstaged = string.rep(' ', unstaged_width),
      fold = '%C',
    })
    parts[#parts + 1] = layout.clickable(' ', layout.default_click_id)
    return table.concat(parts)
  end

  local line = ctx.data.map[vim.v.lnum] or {}
  local staged = ctx.git_has and git.symbol(ctx.buf, vim.v.lnum, 'staged') or nil
  local unstaged = ctx.git_has and git.symbol(ctx.buf, vim.v.lnum, 'unstaged') or nil

  layout.append(parts, layout_state.left, {
    mark = mark_width > 0 and icon(line.mark, mark_width) or '',
    sign = sign_width > 0 and icon(line.sign, sign_width) or '',
  })
  parts[#parts + 1] = layout.clickable(line_number(ctx.win), layout.default_click_id)
  parts[#parts + 1] = layout.clickable(' ', layout.default_click_id)
  layout.append(parts, layout_state.right, {
    staged = staged_width > 0 and icon(staged_icon(staged), 1) or '',
    unstaged = unstaged_width > 0 and icon(unstaged, 1) or '',
    fold = '%C',
  })
  parts[#parts + 1] = layout.clickable(' ', layout.default_click_id)

  return table.concat(parts)
end

---@return string
local function cached()
  local win = vim.g.statusline_winid
  local buf = vim.api.nvim_win_get_buf(win)
  if is_ignored(buf) then return '' end

  local window_options = vim.wo[win]
  local data = signs.data(buf)

  local git_enabled = layout_state.enabled.right.staged == true
    or layout_state.enabled.right.unstaged == true
  local git_has = git_enabled
    and not vim.w[win].vv_statuscol_git_disabled
    and git.has(buf)
    or false

  local git_channels = git_has
    and git.channels(buf)
    or { staged = false, unstaged = false }

  local ctx = {
    win = win,
    buf = buf,
    data = data,
    git_has = git_has,
    git_channels = git_channels,
  }

  local option_flags = string.format(
    '%d%d%d%d%d',
    window_options.number and 1 or 0,
    window_options.relativenumber and 1 or 0,
    layout_state.enabled.left.mark and data.has_mark and 1 or 0,
    layout_state.enabled.left.sign and data.has_sign and 1 or 0,
    git_has and 1 or 0
  )

  local key = string.format(
    '%d:%d:%d:%d:%d:%s',
    win,
    buf,
    vim.v.lnum,
    vim.v.virtnum ~= 0 and 1 or 0,
    vim.v.relnum,
    option_flags
  )

  local result = result_cache[key]
  if result then return result end

  local value = render(ctx)

  result_cache[key] = value
  return value
end

---@param opts VVStatusColConfig
---@param state VVStatusColLayoutState
function M.configure(opts, state)
  config = opts
  layout_state = state
  M.reset()
end

---@return string
function M.get()
  return cached()
end

---@param buf integer
function M.clear_buffer(buf)
  local needle = ':' .. buf .. ':'
  for key in pairs(result_cache) do
    if key:find(needle, 1, true) then
      result_cache[key] = nil
    end
  end
end

function M.reset()
  result_cache = {}
end

---@class VVStatusColRenderContext
---@field win integer
---@field buf integer
---@field data { map: table, has_mark: boolean, has_sign: boolean }
---@field git_has boolean

return M
