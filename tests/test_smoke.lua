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
---@diagnostic disable-next-line: assign-type-mismatch
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
assert_eq('普通文件保留 staged 双轨', git.channels(both_buf).staged, true)
assert_eq('普通文件保留 unstaged 双轨', git.channels(both_buf).unstaged, true)

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
assert_eq('虚拟 revision buffer 读取通用 diff source', revision_ready, true)
assert_eq('revision source 隐藏 staged 空轨', git.channels(revision_buf).staged, false)
assert_eq('revision source 只显示单条比较轨', git.channels(revision_buf).unstaged, true)

vim.api.nvim_set_hl(0, 'StatusColumn', { bg = '#000000' })
vim.api.nvim_set_hl(0, 'Added', { fg = '#00ff00' })
local statuscol_hl = require('vv-statuscol.hl')
statuscol_hl.setup({
  staged_dim = 0.7,
  A = { text = 'A', hl = 'Added' },
  C = { text = 'C', hl = 'Changed' },
  D = { text = 'D', hl = 'Deleted' },
})
local staged_added = vim.api.nvim_get_hl(0, {
  name = statuscol_hl.staged('Added'),
  link = false,
})
assert_eq('staged 颜色向状态列背景混合 70%', staged_added.fg, 0x004d00)
assert_eq('未暂存颜色仍使用原高亮', git.symbol(both_buf, 2, 'unstaged').hl, 'Changed')

local statuscol = require('vv-statuscol')
local original_statuscolumn = vim.o.statuscolumn
local original_foldcolumn = vim.o.foldcolumn
local original_fillchars = vim.o.fillchars
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
assert_eq('fold layout 启用原生 foldcolumn', vim.wo.foldcolumn, 'auto:1')

local race_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(race_buf, 0, -1, false, { 'one', 'two' })
local git_utils = require('vv-utils.git')
local original_diff_lines = git_utils.diff_lines
local diff_callbacks = {}
git_utils.diff_lines = function(_, callback, source)
  diff_callbacks[#diff_callbacks + 1] = {
    callback = callback,
    source = vim.deepcopy(source),
  }
end

vim.b[race_buf].vv_git_diff_source = { path = 'first.txt' }
git.refresh(race_buf)
vim.b[race_buf].vv_git_diff_source = { path = 'latest.txt' }
git.refresh(race_buf)
assert_eq('Git 请求执行期间合并后续刷新', #diff_callbacks, 1)

diff_callbacks[1].callback({ [1] = 'A' })
assert_eq('旧 Git 回调触发最新来源查询', #diff_callbacks, 2)
assert_eq('补跑查询读取最新 diff source', diff_callbacks[2].source.path, 'latest.txt')
diff_callbacks[2].callback({ [2] = 'C' })
assert_eq('旧 Git 结果不会写入 marker', git.symbol(race_buf, 1, 'unstaged'), nil)
assert_eq('最新 Git 结果写入 marker', git.symbol(race_buf, 2, 'unstaged').hl, 'Changed')

vim.b[race_buf].vv_git_diff_source = { path = 'obsolete.txt' }
git.refresh(race_buf)
git.clear(race_buf)
vim.b[race_buf].vv_git_diff_source = { path = 'current.txt' }
git.refresh(race_buf)
diff_callbacks[3].callback({ [1] = 'A' })
git.refresh(race_buf)
assert_eq('clear 前的回调不会清除新请求状态', #diff_callbacks, 4)
diff_callbacks[4].callback({ [1] = 'C' })
assert_eq('新请求期间的刷新仍会补跑', #diff_callbacks, 5)
diff_callbacks[5].callback({ [2] = 'C' })

git_utils.diff_lines = original_diff_lines
git.clear(race_buf)

local dispose_listener = statuscol.on_click(function(ctx)
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
---@diagnostic disable-next-line: duplicate-set-field
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

dispose_listener()
local calls_after_dispose = listener_calls
statuscol.click(2, 1, 'r', '')
assert_eq('click disposer 移除监听器', listener_calls, calls_after_dispose)

local first_listener_calls = 0
local second_listener_calls = 0
local dispose_first
dispose_first = statuscol.on_click(function()
  first_listener_calls = first_listener_calls + 1
  dispose_first()
  return false
end)
local dispose_second = statuscol.on_click(function()
  second_listener_calls = second_listener_calls + 1
  return false
end)
statuscol.click(2, 1, 'r', '')
statuscol.click(2, 1, 'r', '')
assert_eq('监听器可在分发期间释放自身', first_listener_calls, 1)
assert_eq('释放监听器不会跳过后续监听器', second_listener_calls, 2)
dispose_second()

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

local nested_buf = vim.api.nvim_create_buf(false, true)
vim.bo[nested_buf].buftype = ''
vim.api.nvim_buf_set_lines(nested_buf, 0, -1, false, { 'one', 'two', 'three', 'four', 'five' })
vim.api.nvim_win_set_buf(sign_win, nested_buf)
vim.api.nvim_win_call(sign_win, function()
  vim.wo.foldenable = true
  vim.wo.foldmethod = 'manual'
  vim.cmd('1,5fold')
  vim.cmd('2,4fold')
  vim.cmd('normal! zR')
end)
statuscol.refresh(nested_buf)
assert_eq('默认隐藏折叠嵌套层数数字', evaluate(sign_win, 3):find('2', 1, true), nil)

local no_fold_buf = vim.api.nvim_create_buf(false, true)
local switched_fold_buf = vim.api.nvim_create_buf(false, true)
for _, buf in ipairs({ no_fold_buf, switched_fold_buf }) do
  vim.bo[buf].buftype = ''
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'one', 'two', 'three' })
end
assert_eq(
  'buffer 切换回归夹具使用相同 changedtick',
  vim.b[no_fold_buf].changedtick,
  vim.b[switched_fold_buf].changedtick
)

vim.api.nvim_win_set_buf(sign_win, no_fold_buf)
vim.wo[sign_win].foldmethod = 'manual'
statuscol.refresh(no_fold_buf)
assert_eq('无折叠 buffer 不显示 fold 图标', evaluate(sign_win, 2):find('F', 1, true), nil)

vim.api.nvim_win_set_buf(sign_win, switched_fold_buf)
vim.api.nvim_win_call(sign_win, function()
  vim.wo.foldenable = true
  vim.wo.foldmethod = 'manual'
  vim.cmd('2,3fold')
  vim.cmd('normal! zR')
end)
statuscol.refresh(switched_fold_buf)
assert_eq(
  '同窗口从无折叠 buffer 切换后立即显示 fold 图标',
  evaluate(sign_win, 2):find('F', 1, true) ~= nil,
  true
)

local long_buf = vim.api.nvim_create_buf(false, true)
vim.bo[long_buf].buftype = ''
local long_lines = {}
for lnum = 1, 2105 do
  long_lines[lnum] = 'line ' .. lnum
end
vim.api.nvim_buf_set_lines(long_buf, 0, -1, false, long_lines)
vim.api.nvim_win_set_buf(sign_win, long_buf)
vim.api.nvim_win_call(sign_win, function()
  vim.wo.foldenable = true
  vim.wo.foldmethod = 'manual'
  vim.cmd('2100,2105fold')
  vim.cmd('normal! zR')
end)
statuscol.refresh(long_buf)
assert_eq(
  '2000 行以后才出现的折叠仍显示 fold 图标',
  evaluate(sign_win, 2100):find('F', 1, true) ~= nil,
  true
)

vim.fn.getmousepos = original_getmousepos
vim.api.nvim_win_set_buf(sign_win, sign_buf)
vim.api.nvim_buf_delete(both_buf, { force = true })
vim.api.nvim_buf_delete(revision_buf, { force = true })
vim.api.nvim_buf_delete(nested_buf, { force = true })
vim.api.nvim_buf_delete(no_fold_buf, { force = true })
vim.api.nvim_buf_delete(switched_fold_buf, { force = true })
vim.api.nvim_buf_delete(long_buf, { force = true })
vim.fn.delete(tmp_dir, 'rf')

local original_git_has = git.has
---@diagnostic disable-next-line: duplicate-set-field
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
assert_eq('disable 恢复原 statuscolumn', vim.o.statuscolumn, original_statuscolumn)
assert_eq('disable 恢复原 foldcolumn', vim.o.foldcolumn, original_foldcolumn)
assert_eq('disable 恢复原 fillchars', vim.o.fillchars, original_fillchars)
statuscol.enable()
assert_eq('enable 恢复 statuscolumn', vim.o.statuscolumn ~= '', true)

vim.o.statuscolumn = 'external-statuscolumn'
vim.o.foldcolumn = '3'
vim.o.fillchars = 'fold:-'
statuscol.disable()
assert_eq('disable 保留外部 statuscolumn', vim.o.statuscolumn, 'external-statuscolumn')
assert_eq('disable 保留外部 foldcolumn', vim.o.foldcolumn, '3')
assert_eq('disable 保留外部 fillchars', vim.o.fillchars, 'fold:-')

vim.fn.sign_unplace('vv-statuscol-test', { buffer = sign_buf })
vim.api.nvim_buf_delete(race_buf, { force = true })
vim.o.statuscolumn = original_statuscolumn
vim.o.foldcolumn = original_foldcolumn
vim.o.fillchars = original_fillchars

print(('\n总计: %d 通过, %d 失败'):format(passed, failed))
if failed > 0 then vim.cmd('cquit 1') end
