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
