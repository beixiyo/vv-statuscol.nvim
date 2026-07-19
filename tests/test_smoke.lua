-- vv-statuscol.nvim 行为验证
-- 用法：nvim --headless -u NONE -l tests/test_smoke.lua

local passed = 0
local failed = 0

local function assert_eq(name, got, want)
  if got == want then
    passed = passed + 1
    print('[PASS] ' .. name)
    return
  end

  failed = failed + 1
  print(('[FAIL] %s\n  期望: %s\n  实际: %s'):format(
    name,
    vim.inspect(want),
    vim.inspect(got)
  ))
end

local function evaluate(win, lnum, maxwidth)
  return vim.api.nvim_eval_statusline(vim.o.statuscolumn, {
    winid = win,
    use_statuscol_lnum = lnum,
    maxwidth = maxwidth,
  }).str
end

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(root, ':h') .. '/vv-utils.nvim')
vim.opt.runtimepath:prepend(root)

local layout = require('vv-statuscol.layout')
local invalid_ok, invalid_error = pcall(layout.configure, {
  left = { 'sign' },
  right = { 'unknown' },
})
assert_eq('非法布局被拒绝', invalid_ok, false)
assert_eq(
  '非法布局包含明确错误',
  tostring(invalid_error):find('invalid right segment', 1, true) ~= nil,
  true
)

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
assert_eq('同一行同时产生 staged / unstaged marker', dual_ready, true)
assert_eq('staged 使用独立 Added 标记', git.symbol(both_buf, 2, 'staged').hl, 'Added')
assert_eq('unstaged 使用独立 Changed 标记', git.symbol(both_buf, 2, 'unstaged').hl, 'Changed')

local statuscol = require('vv-statuscol')
local segment_ctx
local listener_ctx
local consume_segment = false
local listener_calls = 0

statuscol.setup({
  refresh = 1000,
  ft_ignore = { 'custom-ui' },
  fold = { open = 'F', close = 'X' },
  git = {
    A = { text = 'A', hl = 'Added' },
    C = { text = 'C', hl = 'Changed' },
    D = { text = 'D', hl = 'Deleted' },
  },
  layout = {
    left = {
      {
        segment = 'sign',
        on_click = function(ctx)
          segment_ctx = ctx
          return consume_segment
        end,
      },
    },
    right = { 'unstaged', 'fold' },
  },
})

statuscol.on_click(function(ctx)
  listener_ctx = ctx
  listener_calls = listener_calls + 1
  return false
end)

local sign_buf = vim.api.nvim_get_current_buf()
local sign_win = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_lines(sign_buf, 0, -1, false, { 'one', 'two', 'three' })
vim.fn.sign_define('VVStatusColTestSign', { text = 'T', texthl = 'DiagnosticInfo' })

statuscol.refresh(sign_buf)
local before_sign = evaluate(sign_win, 2)
vim.fn.sign_place(0, 'vv-statuscol-test', 'VVStatusColTestSign', sign_buf, {
  lnum = 2,
  priority = 50,
})
vim.api.nvim_buf_set_mark(sign_buf, 'a', 2, 0, {})
statuscol.refresh(sign_buf)
local after_sign = evaluate(sign_win, 2)

assert_eq('refresh 前状态列没有测试 sign', before_sign:find('T', 1, true), nil)
assert_eq('refresh 后立即读取到测试 sign', after_sign:find('T', 1, true) ~= nil, true)
assert_eq('layout.left 隐藏省略的 mark', after_sign:find('a', 1, true), nil)

vim.wo[sign_win].number = true
local with_number = evaluate(sign_win, 2)
vim.wo[sign_win].number = false
local without_number = evaluate(sign_win, 2)
assert_eq('number 变化无需等待定时器即可更新缓存结果', with_number:find('2', 1, true) ~= nil, true)
assert_eq('关闭 number 后立即隐藏行号', without_number:find('2', 1, true), nil)
vim.wo[sign_win].number = true

local original_getmousepos = vim.fn.getmousepos
vim.fn.getmousepos = function()
  return { winid = sign_win, line = 2, column = 1, screenrow = 1, screencol = 1 }
end

statuscol.click(2, 2, 'r', 'c')
assert_eq('槽位回调收到 segment', segment_ctx and segment_ctx.segment, 'sign')
assert_eq('槽位回调收到右键', segment_ctx and segment_ctx.button, 'r')
assert_eq('槽位回调收到双击次数', segment_ctx and segment_ctx.clicks, 2)
assert_eq('槽位回调收到修饰键', segment_ctx and segment_ctx.mods, 'c')
assert_eq('全局监听器收到统一窗口字段', listener_ctx and listener_ctx.win, sign_win)
assert_eq('全局监听器收到统一 buffer 字段', listener_ctx and listener_ctx.buf, sign_buf)

consume_segment = true
local calls_before_consume = listener_calls
statuscol.click(2, 1, 'l', '')
assert_eq('槽位回调返回 true 后停止事件传播', listener_calls, calls_before_consume)
consume_segment = false

vim.api.nvim_win_set_buf(sign_win, both_buf)
vim.api.nvim_win_call(sign_win, function()
  vim.wo.number = true
  vim.wo.foldenable = true
  vim.wo.foldmethod = 'manual'
  vim.cmd('2,3fold')
  vim.api.nvim_win_set_cursor(sign_win, { 2, 0 })
  vim.cmd('normal! zo')
end)
statuscol.refresh(both_buf)

local fold_open_full = evaluate(sign_win, 2)
local fold_open_narrow = evaluate(sign_win, 2, 4)
local unstaged_pos = fold_open_full:find('C', 1, true) or 0
local staged_pos = fold_open_full:find('A', 1, true) or 0
local open_pos = fold_open_full:find('F', 1, true) or 0
assert_eq(
  'layout.right 按用户顺序渲染 unstaged / fold',
  unstaged_pos > 0 and unstaged_pos < open_pos,
  true
)
assert_eq('layout.right 隐藏省略的 staged', staged_pos, 0)
assert_eq('宽度受限时优先保留 fold 图标', fold_open_narrow:find('F', 1, true) ~= nil, true)

vim.fn.getmousepos = function()
  return { winid = sign_win, line = 2, column = 1, screenrow = 1, screencol = 1 }
end

statuscol.click(4, 1, 'r', '')
assert_eq('右键不触发默认折叠', vim.fn.foldclosed(2), -1)
statuscol.click(4, 2, 'l', '')
assert_eq('左键双击不触发默认折叠', vim.fn.foldclosed(2), -1)
statuscol.click(4, 1, 'l', '')
assert_eq('左键单击触发默认折叠', vim.fn.foldclosed(2), 2)
statuscol.refresh(both_buf)
assert_eq('折叠后保留 close 图标', evaluate(sign_win, 2, 4):find('X', 1, true) ~= nil, true)

vim.fn.getmousepos = original_getmousepos
vim.api.nvim_win_set_buf(sign_win, sign_buf)
vim.api.nvim_buf_delete(both_buf, { force = true })
vim.fn.delete(tmp_dir, 'rf')

local original_git_has = git.has
git.has = function() error('ignored buffers must return before Git lookup') end

vim.bo[sign_buf].filetype = 'custom-ui'
statuscol.refresh(sign_buf)
assert_eq('外部 ft_ignore 整体覆盖后生效', evaluate(sign_win, 2), '')

vim.bo[sign_buf].filetype = 'lua'
for _, buftype in ipairs({ 'help', 'nofile', 'prompt', 'quickfix' }) do
  vim.bo[sign_buf].buftype = buftype
  statuscol.refresh(sign_buf)
  assert_eq('buftype=' .. buftype .. ' 不渲染状态列', evaluate(sign_win, 2), '')
end

git.has = original_git_has
vim.bo[sign_buf].buftype = ''
vim.bo[sign_buf].filetype = 'dashboard'
statuscol.refresh(sign_buf)
assert_eq('外部 ft_ignore 不与旧默认 filetype 合并', evaluate(sign_win, 2):find('T', 1, true) ~= nil, true)

statuscol.disable()
assert_eq('disable 清空 statuscolumn', vim.o.statuscolumn, '')
statuscol.enable()
assert_eq('enable 恢复 statuscolumn', vim.o.statuscolumn ~= '', true)

vim.fn.sign_unplace('vv-statuscol-test', { buffer = sign_buf })
statuscol.disable()

print(('\n总计: %d 通过, %d 失败'):format(passed, failed))
if failed > 0 then vim.cmd('cquit 1') end
