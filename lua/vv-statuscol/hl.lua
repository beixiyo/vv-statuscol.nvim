local M = {}

local staged_groups = {}

---@param git VVStatusColGitConfig
function M.setup(git)
  local hl = require('vv-utils.hl')
  hl.register('VVStatusColHL', {
    VVStatusColMark = { link = 'DiagnosticHint' },
  })

  -- 共享 git 调色板 VVGitAdded/Modified/Deleted/... （VSCode Dark+）
  require('vv-utils.git').register_hl()

  staged_groups = {
    [git.A.hl] = 'VVStatusColStagedA',
    [git.C.hl] = 'VVStatusColStagedC',
    [git.D.hl] = 'VVStatusColStagedD',
  }

  hl.register_dimmed('VVStatusColStagedHL', {
    VVStatusColStagedA = git.A.hl,
    VVStatusColStagedC = git.C.hl,
    VVStatusColStagedD = git.D.hl,
  }, {
    amount = git.staged_dim,
    background = 'StatusColumn',
  })
end

---@param source string
---@return string
function M.staged(source)
  return staged_groups[source] or source
end

return M
