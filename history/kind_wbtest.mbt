///|
test "classify: url" {
  assert_eq(classify("https://example.com/a?b=1").label, "url")
  assert_eq(classify("https://example.com/a?b=1").is_secret, false)
  assert_eq(classify("  https://x.dev ").label, "url")
}

///|
test "classify: jwt 与私钥算密钥" {
  assert_true(classify("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig").is_secret)
  assert_true(
    classify(
      "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----",
    ).is_secret,
  )
}

///|
test "classify: 密钥赋值" {
  assert_true(classify("password=hunter2").is_secret)
  assert_true(classify("DB_PASSWORD = hunter2").is_secret)
  assert_true(classify("api_key=abcd").is_secret)
  assert_false(classify("hello=world").is_secret)
}

///|
test "classify: 带账号的 dsn 算密钥" {
  assert_true(classify("postgres://user:pass@host/db").is_secret)
  assert_false(classify("postgres://host/db").is_secret)
}

///|
test "classify: 多行文本与非敏感多行" {
  assert_false(classify("line1\nline2\nline3").is_secret)
  assert_true(classify("line1\ntoken=abcd").is_secret)
  assert_eq(classify("   ").label, "empty")
}

///|
test "mask 保留前缀并封顶" {
  assert_eq(mask("password=hunter2"), "pass••••••••")
  assert_eq(mask("abc"), "a••")
}

///|
test "classify: 常见脱敏漏判" {
  // Authorization 头 / bearer
  assert_true(classify("authorization: bearer abcdefghijklmnop").is_secret)
  assert_true(classify("Bearer abcdefghijklmnop").is_secret)
  // 裸密钥前缀
  assert_true(classify("sk-ant-abcdefghijklmnopqrstuvwxyz").is_secret)
  assert_true(classify("ghp_abcdefghijklmnopqrstuvwxyz").is_secret)
  assert_true(classify("AKIAABCDEFGHIJKLMNOP").is_secret)
  // URL 里带 token 查询参数
  assert_true(classify("https://example.com/?token=abcdefghijklmnop").is_secret)
  // 带 + 的 scheme 的连接串
  assert_true(
    classify("mongodb+srv://admin:hunter2@cluster0.mongodb.net").is_secret,
  )
  assert_eq(classify("mongodb+srv://cluster0.mongodb.net").label, "dsn")
  assert_false(classify("mongodb+srv://cluster0.mongodb.net").is_secret)
  // 不能误伤
  assert_false(classify("hello@example.com").is_secret)
  assert_eq(classify("https://example.com/a?b=1").label, "url")
  assert_false(classify("https://user@example.com/a").is_secret)
}
