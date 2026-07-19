-- 折叠状态：通过 LuaJIT FFI 读取 Neovim native fold_info，并缓存窗口折叠结构
--
-- Neovim v0.12.1 内部 ABI 来源（不是公开 API）：
-- foldinfo_T:
-- https://github.com/neovim/neovim/blob/v0.12.1/src/nvim/fold_defs.h
-- fold_info():
-- https://github.com/neovim/neovim/blob/v0.12.1/src/nvim/fold.c
-- find_window_by_handle():
-- https://github.com/neovim/neovim/blob/v0.12.1/src/nvim/api/private/helpers.c
--
-- 参考实现：
-- https://github.com/folke/snacks.nvim/blob/main/lua/snacks/statuscolumn.lua
-- https://github.com/luukvbaal/statuscol.nvim/blob/main/lua/statuscol/ffidef.lua

local M = {}

local PROBE_MAX = 2000

local ffi_lib
local ffi_ready
local icons = { open = '', close = '' }
local has_cache = {} ---@type table<integer, { tick: integer, has: boolean }>

local function init_native()
  if ffi_ready ~= nil then return ffi_ready end

  ffi_ready = false
  local loaded, ffi = pcall(require, 'ffi')
  if not loaded then return false end

  local cdef_ok = pcall(ffi.cdef, [[
    typedef struct {} Error;
    typedef struct {} win_T;
    typedef struct {
      int start;
      int level;
      int llevel;
      int lines;
    } foldinfo_T;
    foldinfo_T fold_info(win_T* wp, int lnum);
    win_T *find_window_by_handle(int Window, Error *err);
  ]])
  if not cdef_ok then return false end

  ffi_lib = ffi
  ffi_ready = true
  return true
end

---@param win integer
---@param lnum integer
---@return foldinfo_T?
local function info(win, lnum)
  if not init_native() then return nil end

  local err = ffi_lib.new('Error')
  local window = ffi_lib.C.find_window_by_handle(win, err)
  if window == nil then return nil end

  return ffi_lib.C.fold_info(window, lnum)
end

---@param value { open: string, close: string }
function M.configure(value)
  icons = value
end

---@param win integer
---@return boolean
function M.has(win)
  if not vim.wo[win].foldenable then return false end

  local buf = vim.api.nvim_win_get_buf(win)
  local tick = vim.b[buf].changedtick
  local cached = has_cache[win]
  if cached and cached.tick == tick then return cached.has end

  local has = false
  local line_count = math.min(vim.api.nvim_buf_line_count(buf), PROBE_MAX)
  for lnum = 1, line_count do
    local fold = info(win, lnum)
    if fold and fold.level > 0 then
      has = true
      break
    end
  end

  has_cache[win] = { tick = tick, has = has }
  return has
end

---@param win integer
---@param lnum integer
---@return string
function M.render(win, lnum)
  local fold = info(win, lnum)
  if not fold or fold.level == 0 then return '' end

  if fold.lines > 0 then
    return '%#VVStatusColFold#' .. (icons.close or '') .. '%*'
  end
  if fold.start == lnum then
    return '%#VVStatusColFold#' .. (icons.open or '') .. '%*'
  end

  return ''
end

---@param win integer
---@param lnum integer
---@return 0|1|2
function M.state(win, lnum)
  local fold = info(win, lnum)
  if not fold or fold.level == 0 then return 0 end
  if fold.lines > 0 then return 2 end
  if fold.start == lnum then return 1 end
  return 0
end

function M.reset()
  has_cache = {}
end

return M
