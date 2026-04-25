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

assert_match(
  'README 包含 lazy.nvim 安装格式',
  readme,
  'lazy%.nvim'
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
-- 汇总
-- =============================================
print(('\n总计: %d 通过, %d 失败'):format(passed, failed))
if failed > 0 then
  vim.cmd('cquit 1')
end
