-- 场景共享的真实状态列接线；不注册或执行测试
local function eq(name, got, want)
  assert(got == want, name .. '：期望 ' .. vim.inspect(want) .. '，实际 ' .. vim.inspect(got))
end

local function evaluate(win, lnum, maxwidth)
  return vim.api.nvim_eval_statusline(vim.o.statuscolumn, {
    winid = win, use_statuscol_lnum = lnum, maxwidth = maxwidth,
  }).str
end

local function setup()
  local statuscol = require('vv-statuscol')
  local state = { listener_calls = 0, consume_segment = false }
  statuscol.setup({
    refresh = 1000, ft_ignore = { 'custom-ui' },
    fold = { open = 'F', close = 'X' },
    git = { A = { text = 'A', hl = 'Added' }, C = { text = 'C', hl = 'Changed' },
      D = { text = 'D', hl = 'Deleted' } },
    layout = { left = { { segment = 'sign', on_click = function(ctx)
      state.segment_ctx = ctx
      return state.consume_segment
    end } }, right = { 'unstaged', 'fold' } },
  })
  return statuscol, state
end

local function git_fixture()
  local git = require('vv-statuscol.git')
  git.configure({
    A = { text = 'A', hl = 'Added' },
    C = { text = 'C', hl = 'Changed' },
    D = { text = 'D', hl = 'Deleted' },
  })

  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, 'p')
  local both_path = tmp_dir .. '/both.txt'
  vim.fn.writefile({ 'one', 'two', 'three' }, both_path)
  vim.fn.system({ 'git', '-C', tmp_dir, 'init', '-q' })
  vim.fn.system({ 'git', '-C', tmp_dir, 'config', 'user.name', 'vv-statuscol test' })
  vim.fn.system({ 'git', '-C', tmp_dir, 'config', 'user.email', 'test@example.com' })
  vim.fn.system({ 'git', '-C', tmp_dir, 'add', 'both.txt' })
  vim.fn.system({ 'git', '-C', tmp_dir, 'commit', '-qm', 'initial' })
  vim.fn.writefile({ 'one', 'staged', 'two', 'three' }, both_path)
  vim.fn.system({ 'git', '-C', tmp_dir, 'add', 'both.txt' })
  vim.fn.writefile({ 'one', 'staged again', 'two', 'three' }, both_path)

  local both_buf = vim.fn.bufadd(both_path)
  vim.fn.bufload(both_buf)
  git.refresh(both_buf)
  local dual_ready = vim.wait(3000, function()
    return git.symbol(both_buf, 2, 'staged') ~= nil
      and git.symbol(both_buf, 2, 'unstaged') ~= nil
  end, 10)
  eq('同一行同时产生 staged / unstaged marker', dual_ready, true)
  eq('staged 使用独立 Added 标记', git.symbol(both_buf, 2, 'staged').hl, 'Added')
  eq('unstaged 使用独立 Changed 标记', git.symbol(both_buf, 2, 'unstaged').hl, 'Changed')
  eq('普通文件保留 staged 双轨', git.channels(both_buf).staged, true)
  eq('普通文件保留 unstaged 双轨', git.channels(both_buf).unstaged, true)

  vim.fn.system({ 'git', '-C', tmp_dir, 'commit', '-qm', 'second' })
  local revision_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(revision_buf, 0, -1, false, { 'one', 'staged', 'two', 'three' })
  vim.b[revision_buf].vv_git_diff_source = {
    root = tmp_dir,
    path = 'both.txt',
    from_rev = 'HEAD^',
    to_rev = 'HEAD',
    side = 'new',
  }
  git.refresh(revision_buf)
  local revision_ready = vim.wait(3000, function()
    return git.symbol(revision_buf, 2, 'unstaged') ~= nil
  end, 10)
  eq('虚拟 revision buffer 读取通用 diff source', revision_ready, true)
  eq('revision source 隐藏 staged 空轨', git.channels(revision_buf).staged, false)
  eq('revision source 只显示单条比较轨', git.channels(revision_buf).unstaged, true)

  return git, tmp_dir, both_buf, revision_buf
end

Smoke = { eq = eq, evaluate = evaluate, setup = setup, git_fixture = git_fixture }
