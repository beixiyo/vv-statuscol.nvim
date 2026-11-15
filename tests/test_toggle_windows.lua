-- 真实场景在独立子进程中执行；收集阶段仅注册具名用例
local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set({ setup = 'fixture_smoke.lua' })

T["禁用与重新启用覆盖所有窗口，保留单独设置过的窗口"] = function()
  child.lua_func(function()
    -- 'statuscolumn' / 'foldcolumn' 是窗口局部选项，vim.o 只改全局值和当前窗口
    local statuscol = require('vv-statuscol')
    statuscol.setup({})
    statuscol.enable()
    local ours = vim.wo.statuscolumn
    assert(ours:find('vv-statuscol', 1, true), ours)

    vim.cmd('vsplit')
    vim.cmd('split')
    vim.cmd('tabnew')
    local wins = vim.api.nvim_list_wins()
    local custom = wins[1]
    vim.wo[custom].statuscolumn = '%l custom'

    local function columns()
      local out = {}
      for _, win in ipairs(wins) do out[#out + 1] = vim.wo[win].statuscolumn end
      return out
    end

    statuscol.disable()
    for index, value in ipairs(columns()) do
      local expected = wins[index] == custom and '%l custom' or ''
      assert(value == expected, ('禁用后窗口 %d：%q'):format(index, value))
      assert(wins[index] == custom or vim.wo[wins[index]].foldcolumn == '0')
    end

    statuscol.enable()
    for index, value in ipairs(columns()) do
      local expected = wins[index] == custom and '%l custom' or ours
      assert(value == expected, ('重新启用后窗口 %d：%q'):format(index, value))
    end
  end)
end

return T
