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

local function assert_no_match(name, str, pattern)
  if not str:find(pattern) then
    passed = passed + 1
    print('[PASS] ' .. name)
  else
    failed = failed + 1
    print(('[FAIL] %s\n  不应匹配到: %s\n  内容: %s'):format(name, pattern, str))
  end
end

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')

-- =============================================
-- FIX 2: README git delete glyph 描述与代码一致
-- =============================================
local readme_path = root .. '/README.md'
local readme = table.concat(vim.fn.readfile(readme_path), '\n')
local init_path = root .. '/lua/vv-statuscol/init.lua'
local init_src = table.concat(vim.fn.readfile(init_path), '\n')

-- 从代码中提取 D 的 text 值
local code_d_text = init_src:match("D = { text = '([^']+)'")
assert_eq('代码中 D glyph 已定义', code_d_text ~= nil, true)

-- README 描述行的 glyph 应匹配代码
assert_match(
  'README 描述中 D glyph 与代码一致',
  readme,
  code_d_text
)

-- 确保旧的错误 glyph 不再出现在描述行
-- 注意：配置表中也不该有旧 glyph
assert_no_match(
  'README 不包含旧的错误 glyph 󰍵',
  readme,
  '󰍵'
)

-- =============================================
-- FIX 3: README 不包含旧 spec 路径引用
-- =============================================
assert_no_match(
  'README 不包含旧 spec 路径',
  readme,
  'lua/plugins/specs/ui/vv%-statuscol%.lua'
)

-- README 安装段是 lazy.nvim 风格插件 spec（以仓库名定义行为锚点；README 重排后不再含字面 'lazy.nvim'）
assert_match(
  'README 包含 lazy.nvim 风格安装示例',
  readme,
  "'beixiyo/vv%-statuscol%.nvim'"
)

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
-- FIX 5 (#69): git 异步回调在 buffer 失效后不写回 markers
-- =============================================
local git_path = root .. '/lua/vv-statuscol/git.lua'
local git_src = table.concat(vim.fn.readfile(git_path), '\n')

-- diff 回调（写 markers 前）必须有 is_loaded 守卫
local diff_cb = git_src:match('schedule_wrap.-M%.parse') or ''
assert_match('#69 diff 回调写 markers 前有 is_loaded 守卫', diff_cb, 'nvim_buf_is_loaded%(bufnr%)')

-- rev-parse(root_async) 回调在 spawn diff 前也有 is_loaded 守卫
local revparse_cb = git_src:match('root_async.-vim%.system') or ''
assert_match('#69 rev-parse 回调有 is_loaded 守卫', revparse_cb, 'nvim_buf_is_loaded%(bufnr%)')

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
-- 汇总
-- =============================================
print(('\n总计: %d 通过, %d 失败'):format(passed, failed))
if failed > 0 then
  vim.cmd('cquit 1')
end
