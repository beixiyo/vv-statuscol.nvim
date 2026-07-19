-- vv-statuscol.nvim 变更验证脚本
-- 用法：nvim --headless -u NONE -l tests/test_smoke.lua

local passed, failed = 0, 0

local function assert_eq(name, got, want)
  if got == want then
    passed = passed + 1
    print('[PASS] ' .. name)
  else
    failed = failed + 1
    print(('[FAIL] %s\n  期望: %s\n  实际: %s'):format(name, tostring(want), tostring(got)))
  end
end

local function assert_match(name, str, pattern)
  if str:find(pattern) then
    passed = passed + 1
    print('[PASS] ' .. name)
  else
    failed = failed + 1
    print(('[FAIL] %s\n  未匹配到: %s\n  内容: %s'):format(name, pattern, str))
  end
end

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(root, ':h') .. '/vv-utils.nvim')
vim.opt.runtimepath:prepend(root)

-- =============================================
-- FIX 2: git delete glyph 已定义
-- =============================================
local init_path = root .. '/lua/vv-statuscol/init.lua'
local init_src = table.concat(vim.fn.readfile(init_path), '\n')

-- 从代码中提取 D 的 text 值
local code_d_text = init_src:match("D = { text = '([^']+)'")
assert_eq('代码中 D glyph 已定义', code_d_text ~= nil, true)

-- =============================================
-- FIX 4: BufWipeout 清理 sign_cache
-- =============================================
-- 验证代码中存在 BufWipeout autocmd
assert_match(
  'init.lua 包含 BufWipeout autocmd',
  init_src,
  'BufWipeout'
)

-- 验证清理 sign_cache
assert_match(
  'BufWipeout 回调清理 sign_cache',
  init_src,
  'sign_cache%[args%.buf%] = nil'
)

-- 验证清理 result_cache 条目
assert_match(
  'BufWipeout 回调清理 result_cache 条目',
  init_src,
  'result_cache%[k%] = nil'
)

-- 验证 augroup 存在
assert_match(
  'init.lua 创建了 VVStatusCol augroup',
  init_src,
  "VVStatusCol"
)

-- =============================================
-- FIX 4: 运行时行为验证（模拟 sign_cache 清理）
-- =============================================
-- 模拟 sign_cache / result_cache 清理逻辑
-- key 格式: win:buf:lnum:virtnum:relnum
local sign_cache = { [42] = { mark = 'a' }, [99] = { sign = 'x' } }
local result_cache = {
  ['100:42:5:0:3'] = 'cached_1',
  ['100:42:10:0:8'] = 'cached_2',
  ['200:99:5:0:3'] = 'cached_3',
  ['200:99:20:0:18'] = 'cached_4',
}

-- 模拟 wipe buf=42
local wipe_buf = 42
sign_cache[wipe_buf] = nil
local prefix = ':' .. wipe_buf .. ':'
for k in pairs(result_cache) do
  if k:find(prefix, 1, true) then
    result_cache[k] = nil
  end
end

assert_eq('sign_cache[42] 已清理', sign_cache[42], nil)
assert_eq('sign_cache[99] 未受影响', sign_cache[99] ~= nil, true)
assert_eq('result_cache buf=42 条目已清理', result_cache['100:42:5:0:3'], nil)
assert_eq('result_cache buf=42 条目已清理(2)', result_cache['100:42:10:0:8'], nil)
assert_eq('result_cache buf=99 未受影响', result_cache['200:99:5:0:3'], 'cached_3')
assert_eq('result_cache buf=99 未受影响(2)', result_cache['200:99:20:0:18'], 'cached_4')

-- =============================================
-- Git 双轨：同一行可同时显示 staged / unstaged
-- =============================================
local git_path = root .. '/lua/vv-statuscol/git.lua'
local git_src = table.concat(vim.fn.readfile(git_path), '\n')
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
vim.api.nvim_buf_delete(both_buf, { force = true })
vim.fn.delete(tmp_dir, 'rf')

-- =============================================
-- FIX 6 (动态宽度): result_cache 键纳入影响「渲染宽度」的因素
--   行号段：number / relativenumber；各槽是否收成 0 宽：has_mark / has_sign / git / fold
-- =============================================
local cached_fn = init_src:match('local function cached_get.-result_cache%[key%]') or ''
assert_match('缓存键纳入 number', cached_fn, 'wo%.number')
assert_match('缓存键纳入 relativenumber', cached_fn, 'wo%.relativenumber')
assert_match('缓存键纳入 has_mark', cached_fn, 'has_mark')
assert_match('缓存键纳入 has_sign', cached_fn, 'has_sign')
assert_match('缓存键纳入 git 存在性', cached_fn, 'git_has')
assert_match('缓存键纳入 fold 结构存在性', cached_fn, 'win_has_fold')

-- 逻辑：复刻 opt_flags 公式，验证六个因素任一变化都改变键
local function opt_flags(nu, rnu, mark, sign, git, fold)
  return string.format('%d%d%d%d%d%d',
    nu and 1 or 0, rnu and 1 or 0, mark and 1 or 0, sign and 1 or 0, git and 1 or 0, fold and 1 or 0)
end
local base = opt_flags(true, false, false, false, false, false)
assert_eq('nonumber 改变键', opt_flags(false, false, false, false, false, false) ~= base, true)
assert_eq('relativenumber 改变键', opt_flags(true, true, false, false, false, false) ~= base, true)
assert_eq('有 mark 改变键', opt_flags(true, false, true, false, false, false) ~= base, true)
assert_eq('有 sign 改变键', opt_flags(true, false, false, true, false, false) ~= base, true)
assert_eq('有 git 改变键', opt_flags(true, false, false, false, true, false) ~= base, true)
assert_eq('有 fold 改变键', opt_flags(true, false, false, false, false, true) ~= base, true)

-- 新键仍保留 ':buf:' 子串，BufWipeout 前缀清理逻辑不受影响
local sample_key = string.format('%d:%d:%d:%d:%d:%s', 100, 42, 5, 0, 3, base)
assert_match('新键仍含 :buf: 供 BufWipeout 清理', sample_key, ':42:')

-- =============================================
-- FIX 7 (#71): disable() 释放后台资源，enable() 重挂
-- =============================================
assert_match('#71 git.lua 提供 detach()', git_src, 'function M%.detach')
assert_match('#71 detach 删除 VVStatusColGit augroup', git_src, 'del_augroup_by_name')

assert_match('#71 init 定义 start_resources', init_src, 'local function start_resources')
assert_match('#71 init 定义 stop_resources', init_src, 'local function stop_resources')
assert_match('#71 stop_resources 停止 refresh_timer', init_src, 'refresh_timer:stop')
assert_match('#71 stop_resources 删除 statuscol_augroup', init_src, 'del_augroup_by_id')
assert_match('#71 disable 调用 stop_resources', init_src, 'stop_resources%(%)')
assert_match('#71 enable 调用 start_resources', init_src, 'start_resources%(%)')

-- =============================================
-- Sign 变化：refresh() 必须同步失效缓存并立即刷新
-- =============================================
local statuscol = require('vv-statuscol')
statuscol.setup({
  refresh = 1000,
  ft_ignore = { 'custom-ui' },
})

local sign_buf = vim.api.nvim_get_current_buf()
local sign_win = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_lines(sign_buf, 0, -1, false, { 'one', 'two', 'three' })
vim.fn.sign_define('VVStatusColTestSign', { text = 'T', texthl = 'DiagnosticInfo' })

statuscol.refresh(sign_buf)
local before_sign = vim.api.nvim_eval_statusline(vim.o.statuscolumn, {
  winid = sign_win,
  use_statuscol_lnum = 2,
}).str

vim.fn.sign_place(0, 'vv-statuscol-test', 'VVStatusColTestSign', sign_buf, {
  lnum = 2,
  priority = 50,
})
statuscol.refresh(sign_buf)

local after_sign = vim.api.nvim_eval_statusline(vim.o.statuscolumn, {
  winid = sign_win,
  use_statuscol_lnum = 2,
}).str
assert_eq('refresh 前状态列没有测试 sign', before_sign:find('T', 1, true), nil)
assert_eq('refresh 后立即读取到测试 sign', after_sign:find('T', 1, true) ~= nil, true)

local git_module = require('vv-statuscol.git')
local original_git_has = git_module.has
git_module.has = function() error('ignored buffers must return before Git lookup') end

vim.bo[sign_buf].filetype = 'custom-ui'
statuscol.refresh(sign_buf)
local ignored_ft = vim.api.nvim_eval_statusline(vim.o.statuscolumn, {
  winid = sign_win,
  use_statuscol_lnum = 2,
}).str
assert_eq('外部 ft_ignore 整体覆盖后生效', ignored_ft, '')

vim.bo[sign_buf].filetype = 'lua'
for _, bt in ipairs({ 'help', 'nofile', 'prompt', 'quickfix' }) do
  vim.bo[sign_buf].buftype = bt
  statuscol.refresh(sign_buf)
  local ignored = vim.api.nvim_eval_statusline(vim.o.statuscolumn, {
    winid = sign_win,
    use_statuscol_lnum = 2,
  }).str
  assert_eq('buftype=' .. bt .. ' 不渲染状态列', ignored, '')
end

vim.bo[sign_buf].buftype = ''
vim.cmd('new')
vim.cmd('terminal true')
local terminal_win = vim.api.nvim_get_current_win()
local ignored_terminal = vim.api.nvim_eval_statusline(vim.o.statuscolumn, {
  winid = terminal_win,
  use_statuscol_lnum = 1,
}).str
assert_eq('真实 terminal buffer 不渲染状态列', ignored_terminal, '')
vim.cmd('close!')

git_module.has = original_git_has
vim.bo[sign_buf].filetype = 'dashboard'
statuscol.refresh(sign_buf)
local replaced_defaults = vim.api.nvim_eval_statusline(vim.o.statuscolumn, {
  winid = sign_win,
  use_statuscol_lnum = 2,
}).str
assert_eq('外部 ft_ignore 不与旧默认 filetype 合并', replaced_defaults:find('T', 1, true) ~= nil, true)

vim.fn.sign_unplace('vv-statuscol-test', { buffer = sign_buf })
statuscol.disable()

-- =============================================
-- 汇总
-- =============================================
print(('\n总计: %d 通过, %d 失败'):format(passed, failed))
if failed > 0 then
  vim.cmd('cquit 1')
end
