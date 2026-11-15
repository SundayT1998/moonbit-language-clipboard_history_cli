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

///|
test "classify: 各种连接串前缀" {
  assert_eq(classify("mysql://host:3306/db").label, "dsn")
  assert_false(classify("mysql://host:3306/db").is_secret)
  assert_eq(classify("redis://localhost:6379").label, "dsn")
  assert_true(classify("redis://:p@localhost:6379").is_secret)
  assert_true(classify("https://user:pass@example.com/").is_secret)
}

///|
test "classify: 大小写不敏感" {
  assert_eq(classify("HTTPS://EXAMPLE.COM").label, "url")
  assert_true(classify("EyjJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig").is_secret)
  assert_true(classify("PASSWORD=hunter2").is_secret)
  assert_true(classify("-----BEGIN RSA PRIVATE KEY-----").is_secret)
}

///|
test "classify: JWT 必须正好三段" {
  assert_eq(classify("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig").label, "jwt")
  // 两段 / 四段不算 JWT
  assert_eq(classify("eyJhbGciOiJIUzI1NiJ9.abc").label, "text")
  assert_eq(classify("eyJhbGciOiJIUzI1NiJ9.a.b.c").label, "text")
}

///|
test "classify: 敏感关键词只在等号左边生效" {
  assert_true(classify("db_password = hunter2").is_secret)
  assert_true(classify("ACCESS_KEY=abc").is_secret)
  assert_true(classify("private_key=abc").is_secret)
  // 冒号分隔的键值只覆盖 token/password 这类明确的关键词
  assert_true(classify("token: abc").is_secret)
  // 关键词出现在等号右边不按“键名”算
  assert_false(classify("note=greeting").is_secret)
  // 单独的等号没有键名不算
  assert_false(classify("=value").is_secret)
}

///|
test "classify: URL 里带敏感参数算密钥" {
  assert_true(classify("https://x.dev/cb?access_token=abc").is_secret)
  assert_true(classify("https://x.dev/cb?password=abc").is_secret)
  assert_true(classify("https://x.dev/cb?passwd=abc").is_secret)
  // 普通查询参数不算
  assert_false(classify("https://x.dev/cb?q=abc").is_secret)
}

///|
test "classify: 多行只在最后一行是敏感赋值时才算密钥" {
  assert_true(classify("kubectl get pods\napi_key=abcd").is_secret)
  assert_false(classify("api_key=abcd\nkubectl get pods").is_secret)
  // 多行里的 URL 不参与结构判定
  assert_eq(classify("https://example.com\nextra").label, "text")
}

///|
test "classify: 各种裸密钥前缀" {
  for p in ["sk-", "gho_", "ghs_", "github_pat_", "xoxb-", "xoxp-"] {
    assert_true(classify("\{p}abcdefgh").is_secret)
  }
  assert_true(classify("prefix AKIAABCDEFGH suffix").is_secret)
  assert_true(classify("xoxb-1234-5678").is_secret)
}

///|
test "classify: 路径里才出现冒号时不算账号密码" {
  // `https://example.com:8080` 是端口，不是 userinfo
  assert_false(classify("https://example.com:8080/path").is_secret)
  // userinfo 必须在第一个斜杠之前
  assert_true(classify("https://user:pass@example.com/path").is_secret)
}

///|
test "classify: 裸前缀的子串误判（当前行为）" {
  // `akia` 没有词边界，URL 里带这几个字母也会被判成密钥
  assert_true(classify("https://example.com/akia_page").is_secret)
  assert_true(classify("https://example.com/zhakia_page").is_secret)
  // `bearer ` 后面只有空格也算
  assert_true(classify("word bearer test").is_secret)
  // 这几个不该误判
  assert_eq(classify("https://github.com/asia/foo").label, "url")
  assert_false(classify("https://github.com/asia/foo").is_secret)
}

///|
test "mask 的边界" {
  assert_eq(mask(""), "")
  assert_eq(mask("a"), "a")
  assert_eq(mask("abcdef"), "a•••••")
  // 超过 6 个字符保留前 4 个，最多 8 个点
  assert_eq(mask("abcdefg"), "abcd•••")
  assert_eq(mask("abcdefghijklmnop"), "abcd••••••••")
  // 多字节字符按字符数算
  // 9 个字符：保留前 4 个，剩下 5 个打点
  assert_eq(mask("密码就是很长的一串"), "密码就是•••••")
}

///|
test "classify: 密钥判定结果不会泄漏原文" {
  let text = "password=hunter2"
  let kind = classify(text)
  assert_true(kind.is_secret)
  assert_false(kind.label.contains("hunter2"))
  assert_false(mask(text).contains("hunter2"))
}
