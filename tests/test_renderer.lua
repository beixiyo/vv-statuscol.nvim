-- 通过生产 statuscolumn 求值验证动态行号、静态槽位和真实收集次数
local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set({ setup = 'fixture_smoke.lua' })

T['多窗口动态行号不重复格式化符号且即时遵循窗口选项'] = function()
  child.lua_func(function()
    local api = vim.api
    local sc = require('vv-statuscol')
    local layout = require('vv-statuscol.layout')
    local buf = api.nvim_get_current_buf()
    local lines = {}
    for i = 1, 200 do lines[i] = 'line ' .. i end
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    sc.setup({ refresh = 10000, layout = { left = { 'mark', 'sign' }, right = { 'fold' } } })
    local ns = api.nvim_create_namespace('任意第三方符号')
    api.nvim_buf_set_extmark(buf, ns, 4, 0, { sign_text = 'P', sign_hl_group = 'DiagnosticWarn' })
    api.nvim_buf_set_mark(buf, 'a', 5, 0, {})
    vim.cmd('vsplit')
    local wins = api.nvim_list_wins()
    local appends, collects, gets = 0, 0, 0
    local get = sc.get
    sc.get = function() gets = gets + 1; return get() end
    local append, extmarks = layout.append, api.nvim_buf_get_extmarks
    layout.append = function(...)
      appends = appends + 1
      return append(...)
    end
    api.nvim_buf_get_extmarks = function(b, ns_id, first, last, opts)
      if opts and opts.type == 'sign' then collects = collects + 1 end
      return extmarks(b, ns_id, first, last, opts)
    end
    require('vv-statuscol.renderer').reset()
    require('vv-statuscol.signs').reset()
    local started = vim.uv.hrtime()
    for cursor = 1, 20 do
      for _, win in ipairs(wins) do
        vim.wo[win].number = true
        vim.wo[win].relativenumber = true
        api.nvim_win_set_cursor(win, { cursor, 0 })
        for line = 1, 40 do
          local text = Smoke.evaluate(win, line)
          local expected = line == cursor and line or math.abs(line - cursor)
          assert(text:match('%d+') == tostring(expected), '行号必须跟随目标窗口光标实时变化')
          if line == 5 then
            assert(text:find('a', 1, true) and text:find('P', 1, true), '动态行号不能覆盖 mark/sign')
          end
        end
      end
    end
    local elapsed = (vim.uv.hrtime() - started) / 1e6
    Smoke.eq('同 buffer 双窗共享一次全 namespace sign 收集', collects, 1)
    for _, number in ipairs({ false, true }) do
      for _, relative in ipairs({ false, true }) do
        for i, win in ipairs(wins) do
          vim.wo[win].number = number
          vim.wo[win].relativenumber = relative
          api.nvim_win_set_cursor(win, { i + 1, 0 })
          local text = Smoke.evaluate(win, 5)
          local expected = relative and (5 - i - 1) or number and 5 or nil
          Smoke.eq('选项切换后行号即时更新且双窗不串扰', text:match('%d+'), expected and tostring(expected))
        end
      end
    end
    Smoke.eq('切换行号选项不重建静态槽位', appends, 160)
    RendererCounts = { get = gets, append = appends, collect = collects, elapsed_ms = elapsed }
    Smoke.eq('生产求值覆盖1600次光标矩阵和8次选项切换', gets, 1608)
    sc.disable()
  end)
  print('动态行号计数：' .. vim.inspect(child.lua_get('RendererCounts')))
end

T['心跳只失效缓存且任意符号诊断和生命周期仍按需刷新'] = function()
  child.lua_func(function()
    local api = vim.api
    local sc = require('vv-statuscol')
    local signs = require('vv-statuscol.signs')
    local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
    api.nvim_buf_set_lines(buf, 0, -1, false, { 'one', 'two', 'three' })
    local resets, collects = 0, 0
    local reset, extmarks = signs.reset, api.nvim_buf_get_extmarks
    signs.reset = function() resets = resets + 1; return reset() end
    api.nvim_buf_get_extmarks = function(b, ns, first, last, opts)
      if opts and opts.type == 'sign' then collects = collects + 1 end
      return extmarks(b, ns, first, last, opts)
    end
    sc.setup({ refresh = 50, layout = { left = { 'mark', 'sign' }, right = {} } })
    Smoke.evaluate(win, 2)
    local initial = collects
    resets = 0
    vim.wait(220)
    assert(resets >= 3, '默认 50ms 心跳必须继续失效缓存')
    local idle_resets = resets
    Smoke.eq('无生产求值的心跳不收集 sign', collects, initial)
    local ns = api.nvim_create_namespace('没有专用事件的任意provider')
    local id = api.nvim_buf_set_extmark(buf, ns, 1, 0, { sign_text = 'P', priority = 200 })
    vim.fn.sign_define('RendererLegacy', { text = 'L' })
    vim.fn.sign_place(0, 'renderer', 'RendererLegacy', buf, { lnum = 2, priority = 10 })
    api.nvim_buf_set_mark(buf, 'b', 2, 0, {})
    assert(Smoke.evaluate(win, 2):find('P', 1, true), '心跳后的首次求值发现任意namespace sign')
    Smoke.eq('首次消费仅再收集一次', collects, initial + 1)
    api.nvim_buf_del_extmark(buf, ns, id)
    sc.refresh(buf)
    assert(Smoke.evaluate(win, 2):find('L', 1, true), 'refresh立即发现删除并恢复低优先级legacy sign')
    sc.disable()
    local stopped = resets
    vim.wait(120)
    Smoke.eq('禁用后停止心跳', resets, stopped)
    sc.enable()
    assert(Smoke.evaluate(win, 2):find('b', 1, true), '重新启用后mark仍存在')
    -- 诊断回归使用长心跳，避免50ms兜底掩盖DiagnosticChanged失效链
    sc.setup({ refresh = 10000, layout = { left = { 'mark', 'sign' }, right = {} } })
    Smoke.evaluate(win, 2)
    vim.diagnostic.config({ virtual_text = false, underline = false, signs = { text = { [vim.diagnostic.severity.ERROR] = 'E' }, priority = 300 } })
    vim.diagnostic.set(ns, buf, { { lnum = 1, col = 0, message = '错误', severity = vim.diagnostic.severity.ERROR } })
    vim.wait(100)
    assert(Smoke.evaluate(win, 2):find('E', 1, true), '诊断事件更新已缓存行的最高优先级sign')
    vim.diagnostic.reset(ns, buf)
    vim.wait(100)
    assert(Smoke.evaluate(win, 2):find('L', 1, true), '诊断删除后恢复第三方sign')
    local other = api.nvim_create_buf(true, false)
    api.nvim_buf_set_lines(other, 0, -1, false, { 'one', 'two', 'three' })
    api.nvim_win_set_buf(win, other)
    assert(not Smoke.evaluate(win, 2):find('L', 1, true), '同窗口更换buffer不能复用旧sign片段')
    api.nvim_buf_delete(buf, { force = true })
    sc.disable()
    HeartbeatCounts = { idle_resets = idle_resets, total_collects = collects }
  end)
  print('心跳/按需收集：' .. vim.inspect(child.lua_get('HeartbeatCounts')))
end

T['缓存命中仍保留真实虚拟行原生折叠双轨和点击区域'] = function()
  child.lua_func(function()
    local api = vim.api
    local sc = require('vv-statuscol')
    local clicks = {}
    sc.setup({ refresh = 10000, fold = { open = 'F', close = 'X' },
      git = { A = { text = 'A', hl = 'Added' }, C = { text = 'C', hl = 'Changed' }, D = { text = 'D', hl = 'Deleted' } },
      layout = { left = { 'mark', 'sign' }, right = { 'staged', 'unstaged', { segment = 'fold', on_click = function(ctx) clicks[#clicks + 1] = ctx end } } },
    })
    local _, _, buf = Smoke.git_fixture()
    local win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, buf)
    vim.wo.number = true
    vim.wo.relativenumber = true
    vim.wo.foldmethod = 'manual'
    vim.cmd('2,4fold')
    sc.refresh(buf)
    local closed = Smoke.evaluate(win, 2)
    assert(closed:find('A', 1, true) and closed:find('C', 1, true) and closed:find('X', 1, true), '同一行显示双轨和闭合折叠')
    vim.cmd('vsplit')
    local second = api.nvim_get_current_win()
    vim.w[second].vv_statuscol_git_disabled = true
    local hidden = Smoke.evaluate(second, 2)
    assert(not hidden:find('A', 1, true) and not hidden:find('C', 1, true), 'Git隐藏标志仅影响目标窗口')
    assert(Smoke.evaluate(win, 2):find('A', 1, true), '同buffer另一窗口保留双轨')
    vim.fn.getmousepos = function() return { winid = win, line = 2, column = 1 } end
    -- 从生产字符串获取原生fold段实际绑定的点击编号，不硬编码布局编号
    local raw
    local get = sc.get
    sc.get = function() raw = get(); return raw end
    Smoke.evaluate(win, 2)
    local fold_id = tonumber(raw:match("%%(%d+)@v:lua.require'vv%-statuscol'.click@%%C%%T"))
    assert(fold_id, 'fold片段必须保留点击包装')
    sc.click(fold_id, 1, 'l', '')
    Smoke.eq('点击定位原窗口而非当前窗口', clicks[1].win, win)
    Smoke.eq('点击保留segment', clicks[1].segment, 'fold')
    Smoke.eq('默认点击展开原窗口折叠', api.nvim_win_call(win, function() return vim.fn.foldclosed(2) end), -1)
    assert(not Smoke.evaluate(win, 2):find('X', 1, true), '缓存中的%C必须实时反映折叠展开')
    local ns = api.nvim_create_namespace('虚拟行')
    api.nvim_buf_set_extmark(buf, ns, 1, 0, { virt_lines = { { { 'virtual', 'Comment' } } } })
    api.nvim_buf_set_lines(buf, 0, 1, false, { string.rep('wrapped ', 40) })
    vim.wo[win].wrap = true
    local virtual, wrapped, inserted = {}, false, false
    sc.get = function()
      local value = get()
      if vim.v.virtnum ~= 0 then
        virtual[#virtual + 1] = value
        wrapped = wrapped or vim.v.virtnum > 0
        inserted = inserted or vim.v.virtnum < 0
      end
      return value
    end
    vim.cmd('redraw!')
    assert(wrapped and inserted, '真实重绘必须覆盖折行和extmark虚拟行两种virtnum')
    for _, value in ipairs(virtual) do
      assert(value:find('@%= %T', 1, true), '虚拟行保留空行号点击区')
      assert(not value:find('#Added#', 1, true) and not value:find('#Changed#', 1, true), '虚拟行不得重复真实行Git图标')
    end
    api.nvim_win_close(second, true)
    sc.disable()
  end)
end

return T
