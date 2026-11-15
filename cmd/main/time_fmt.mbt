///|
/// 相对时间：刚刚 / 3 分钟前 / 2 小时前 / 今天 14:03 / 昨天 14:03 /
/// 3 天前 / 2023-11-15。
fn format_ago(ms : Int64, now_ms : Int64) -> String {
  let delta = now_ms - ms
  let seconds = delta / 1000L
  if seconds < 60L {
    "刚刚"
  } else if seconds < 3600L {
    "\{seconds / 60L} 分钟前"
  } else if seconds < 86400L {
    "\{seconds / 3600L} 小时前"
  } else {
    let zone = local_offset()
    let now = wall_clock(now_ms, zone)
    let then = wall_clock(ms, zone)
    // 按本地日历日比较：同一天 → 今天，早一天 → 昨天
    let days = floor_div(then.to_unix_second(), 86400L) -
      floor_div(now.to_unix_second(), 86400L)
    if days == 0L {
      "今天 \{pad2(then.hour())}:\{pad2(then.minute())}"
    } else if days == -1L {
      "昨天 \{pad2(then.hour())}:\{pad2(then.minute())}"
    } else if seconds < 7L * 86400L {
      "\{seconds / 86400L} 天前"
    } else {
      then.to_plain_date().to_string()
    }
  }
}

///|
/// 本地时区偏移，形如 `+08:00`；拿不到时区信息就用 UTC，宁可时间差几个小时，
/// 也不能让 `list` 直接崩。
fn local_offset() -> @time.ZoneOffset {
  let zone = @time.local_zone() catch { _ => return @time.utc_offset }
  let probe = @time.ZonedDateTime::from_unix_second(0L, zone~) catch {
    _ => return @time.utc_offset
  }
  probe.offset()
}

///|
/// 毫秒时间戳 → 本地基准下的日期时间。返回值的年/月/日/时/分就是本地墙上
/// 时间，可以直接拿来显示、比较。
///
/// 先在 UTC 下算出“墙上时间区号”，再把它当成 UTC 偏移重新解释一遍：以后从
/// 这个值上取日期、时分都是本地语义，不用再关心时区。
fn wall_clock(ms : Int64, offset : @time.ZoneOffset) -> @time.ZonedDateTime {
  let seconds = if ms < 0L && ms % 1000L != 0L {
    ms / 1000L - 1L
  } else {
    ms / 1000L
  }
  let shifted = seconds + offset_seconds(offset)
  @time.ZonedDateTime::from_unix_second(shifted, zone=@time.utc_zone) catch {
    e => abort("无法构造时间: \{e}")
  }
}

///|
/// `+08:00` / `-05:30` → 秒数。
fn offset_seconds(offset : @time.ZoneOffset) -> Int64 {
  let s = offset.to_string()
  let chars = s.to_array()
  if chars.length() < 6 {
    return 0L
  }
  let sign = if chars[0] == '-' { -1L } else { 1L }
  let hours = digit(chars[1]) * 10L + digit(chars[2])
  let minutes = digit(chars[4]) * 10L + digit(chars[5])
  sign * (hours * 3600L + minutes * 60L)
}

///|
fn digit(c : Char) -> Int64 {
  (c.to_int() - '0'.to_int()).to_int64()
}

///|
/// 向负无穷取整的除法（`Int64` 的 `/` 是向零取整，1970 年前会差一天）。
fn floor_div(a : Int64, b : Int64) -> Int64 {
  let q = a / b
  if a % b != 0L && (a < 0L) != (b < 0L) {
    q - 1L
  } else {
    q
  }
}

///|
/// 两位补零，用于 `14:03` 这样的时分。
fn pad2(n : Int32) -> String {
  if n < 10 {
    "0\{n}"
  } else {
    "\{n}"
  }
}

///|
/// 当前 Unix 时间（毫秒）。
///
/// `@env.now()` 返回的就是毫秒级 Unix 时间，直接转 `Int64` 即可。
pub fn now_ms() -> Int64 {
  @env.now().reinterpret_as_int64()
}

///|
test "now_ms 是毫秒级 Unix 时间" {
  // 2023-11 之后、3000 年之前：量级正确就落在这个区间
  assert_true(now_ms() > 1_700_000_000_000L)
  assert_true(now_ms() < 32_503_680_000_000L)
}

///|
test "format_ago 的分段" {
  assert_eq(format_ago(1_000L, 1_000L + 59_000L), "刚刚")
  assert_eq(format_ago(1_000L, 1_000L + 3L * 60_000L), "3 分钟前")
  assert_eq(format_ago(1_000L, 1_000L + 2L * 3_600_000L), "2 小时前")
}

///|
test "offset_seconds 解析各种偏移" {
  let plus8 = @time.ZoneOffset::from_seconds(8 * 3600) catch { _ => abort("x") }
  assert_eq(offset_seconds(plus8), 8L * 3600L)
  let minus = @time.ZoneOffset::from_seconds(-(5 * 3600 + 30 * 60)) catch {
    _ => abort("x")
  }
  assert_eq(offset_seconds(minus), -(5L * 3600L + 30L * 60L))
}

///|
test "floor_div 向负无穷取整" {
  assert_eq(floor_div(7L, 2L), 3L)
  assert_eq(floor_div(-7L, 2L), -4L)
  assert_eq(floor_div(-7L, 2L), -4L)
}
