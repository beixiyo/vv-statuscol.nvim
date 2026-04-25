local M = {}

function M.setup()
  require('vv-utils.hl').register('VVStatusColHL', {
    VVStatusColMark = { link = 'DiagnosticHint' },
    VVStatusColFold = { link = 'Folded' },
  })
  -- 共享 git 调色板 VVGitAdded/Modified/Deleted/... （VSCode Dark+）
  require('vv-utils.git').register_hl()
end

return M
