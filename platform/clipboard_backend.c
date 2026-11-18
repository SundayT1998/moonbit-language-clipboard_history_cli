/* 剪贴板读写的原生实现。
 *
 * 分两条路：
 *   - Windows / macOS：直接调系统 API（Win32 剪贴板、AppKit NSPasteboard），不依赖外部命令。
 *   - Linux / 其他类 Unix：图形服务器没有统一 ABI，走 wl-clipboard / xclip / xsel。
 *
 * 这里只负责“能不能用”和“怎么读怎么写”的原始动作。挑哪个后端、怎么探测显示服务器
 * 可达、失败怎么措辞，都在 MoonBit 侧（platform/backend.mbt）做，便于测试。
 *
 * 错误码与 MoonBit 侧的 `ClipRc` 一一对应（见下方 MTUCK_RC_*）。
 */
#define _POSIX_C_SOURCE 200809L

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"

#if defined(_WIN32)
#include <windows.h>
#ifdef _MSC_VER
#pragma comment(lib, "user32.lib")
#endif
#elif defined(__APPLE__)
#include <objc/message.h>
#include <objc/runtime.h>
#else
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#endif

#define MTUCK_RC_OK 0
#define MTUCK_RC_READ_FAILED 1
#define MTUCK_RC_WRITE_FAILED 2
#define MTUCK_RC_NO_BACKEND 3
#define MTUCK_RC_NO_DISPLAY 4

/* 文本超过这个长度就判定不是“一段可记录的剪贴板文本”，避免把图片、
 * 巨大的转储读进内存再逐帧比对。 */
#define MTUCK_MAX_TEXT (1024 * 1024)

/* 子进程硬超时：后端卡在等图形服务器响应时不能把 mtuck 一起拖死。 */
#define MTUCK_CHILD_TIMEOUT_MS 2000

/* 单个子命令：可执行文件 + 参数（以 NULL 结尾）。 */
typedef struct {
  const char *program;
  const char *const *argv;
} mtuck_tool;

typedef struct {
  int32_t len;
  char *data;
} mtuck_buffer;

#if defined(_WIN32)
/* ------------------------------------------------------------------ Win32 */

static int mtuck_win32_status(DWORD err) {
  if (err == ERROR_ACCESS_DENIED || err == ERROR_CLIPBOARD_NOT_OPEN) {
    return MTUCK_RC_NO_DISPLAY;
  }
  return MTUCK_RC_READ_FAILED;
}

/* 打开剪贴板。别的程序短暂占着剪贴板时重试几次再认输。 */
static int mtuck_win32_open(void) {
  for (int attempt = 0; attempt < 20; attempt++) {
    if (OpenClipboard(NULL)) {
      return 1;
    }
    Sleep(10);
  }
  return 0;
}

static int mtuck_read_native(mtuck_buffer *out) {
  if (!mtuck_win32_open()) {
    return mtuck_win32_status(GetLastError());
  }
  if (!IsClipboardFormatAvailable(CF_UNICODETEXT)) {
    CloseClipboard();
    return MTUCK_RC_READ_FAILED;
  }
  HANDLE handle = GetClipboardData(CF_UNICODETEXT);
  if (handle == NULL) {
    int rc = mtuck_win32_status(GetLastError());
    CloseClipboard();
    return rc;
  }
  const wchar_t *wide = (const wchar_t *)GlobalLock(handle);
  if (wide == NULL) {
    int rc = mtuck_win32_status(GetLastError());
    CloseClipboard();
    return rc;
  }
  /* -1 的写法返回的字节数含结尾的 NUL，正好让下面的 utf8_len 少一个字节。 */
  int needed = WideCharToMultiByte(CP_UTF8, 0, wide, -1, NULL, 0, NULL, NULL);
  if (needed <= 0 || needed > MTUCK_MAX_TEXT) {
    GlobalUnlock(handle);
    CloseClipboard();
    return MTUCK_RC_READ_FAILED;
  }
  char *buf = (char *)malloc((size_t)needed);
  if (buf == NULL) {
    GlobalUnlock(handle);
    CloseClipboard();
    return MTUCK_RC_READ_FAILED;
  }
  int written = WideCharToMultiByte(CP_UTF8, 0, wide, -1, buf, needed, NULL, NULL);
  GlobalUnlock(handle);
  CloseClipboard();
  if (written <= 0) {
    free(buf);
    return MTUCK_RC_READ_FAILED;
  }
  out->data = buf;
  out->len = written - 1;
  return MTUCK_RC_OK;
}

static int mtuck_write_native(const char *text, int32_t len) {
  if (len > MTUCK_MAX_TEXT) {
    return MTUCK_RC_WRITE_FAILED;
  }
  int wide_len = (int)MultiByteToWideChar(CP_UTF8, 0, text, len, NULL, 0);
  if (len > 0 && wide_len <= 0) {
    return MTUCK_RC_WRITE_FAILED;
  }
  /* 写入的是文本，先拒绝含 NUL 的内容，否则 SetClipboardData 会把它截断。 */
  if (memchr(text, '\0', (size_t)len) != NULL) {
    return MTUCK_RC_WRITE_FAILED;
  }
  HGLOBAL handle = GlobalAlloc(GMEM_MOVEABLE, ((size_t)wide_len + 1) * sizeof(wchar_t));
  if (handle == NULL) {
    return MTUCK_RC_WRITE_FAILED;
  }
  wchar_t *buffer = (wchar_t *)GlobalLock(handle);
  if (buffer == NULL) {
    GlobalFree(handle);
    return MTUCK_RC_WRITE_FAILED;
  }
  if (len > 0 && MultiByteToWideChar(CP_UTF8, 0, text, len, buffer, wide_len) <= 0) {
    GlobalUnlock(handle);
    GlobalFree(handle);
    return MTUCK_RC_WRITE_FAILED;
  }
  buffer[wide_len] = L'\0';
  GlobalUnlock(handle);

  if (!mtuck_win32_open()) {
    GlobalFree(handle);
    return MTUCK_RC_NO_DISPLAY;
  }
  if (!EmptyClipboard()) {
    int rc = mtuck_win32_status(GetLastError());
    CloseClipboard();
    GlobalFree(handle);
    return rc;
  }
  /* SetClipboardData 成功后所有权归系统，不能再 GlobalFree。 */
  if (SetClipboardData(CF_UNICODETEXT, handle) == NULL) {
    int rc = mtuck_win32_status(GetLastError());
    CloseClipboard();
    GlobalFree(handle);
    return rc;
  }
  CloseClipboard();
  return MTUCK_RC_OK;
}

#elif defined(__APPLE__)
/* ----------------------------------------------------------------- AppKit */

/* 编译期没有 AppKit 头文件时，用 objc runtime 直接发消息：
 * 链接期必然有 libobjc，AppKit 在运行期按名字查找，找不到就是“没有后端”。 */

static id mtuck_send(id receiver, const char *selector) {
  return ((id(*)(id, SEL))objc_msgSend)(receiver, sel_registerName(selector));
}

static int mtuck_read_native(mtuck_buffer *out) {
  out->data = NULL;
  out->len = 0;
  Class pasteboard_class = objc_getClass("NSPasteboard");
  if (pasteboard_class == NULL) {
    return MTUCK_RC_NO_BACKEND;
  }
  id pasteboard = mtuck_send((id)pasteboard_class, "generalPasteboard");
  if (pasteboard == NULL) {
    return MTUCK_RC_NO_DISPLAY;
  }

  /* 这一层调用的都是 returns-retained / autorelease 的对象，
   * 每次读剪贴板都开一个 pool 收掉，watch 轮询才不会涨内存。 */
  Class pool_class = objc_getClass("NSAutoreleasePool");
  id pool = pool_class != NULL ? mtuck_send((id)pool_class, "new") : NULL;

  int rc = MTUCK_RC_READ_FAILED;
  Class string_class = objc_getClass("NSString");
  /* NSPasteboardTypeString 的实参就是字符串字面量。 */
  id type_name = string_class != NULL
                   ? ((id(*)(id, SEL, const char *))objc_msgSend)(
                       (id)string_class,
                       sel_registerName("stringWithUTF8String:"),
                       "public.utf8-plain-text")
                   : NULL;
  if (type_name != NULL) {
    id text = ((id(*)(id, SEL, id))objc_msgSend)(
      pasteboard, sel_registerName("stringForType:"), type_name);
    if (text != NULL) {
      /* NSUTF8StringEncoding == 4 */
      id data = ((id(*)(id, SEL, unsigned long))objc_msgSend)(
        text, sel_registerName("dataUsingEncoding:"), (unsigned long)4);
      if (data != NULL) {
        unsigned long length =
          ((unsigned long(*)(id, SEL))objc_msgSend)(data, sel_registerName("length"));
        const char *bytes =
          ((const char *(*)(id, SEL))objc_msgSend)(data, sel_registerName("bytes"));
        if (length <= (unsigned long)MTUCK_MAX_TEXT) {
          char *buf = (char *)malloc((size_t)length + 1);
          if (buf != NULL) {
            if (length > 0 && bytes != NULL) {
              memcpy(buf, bytes, (size_t)length);
            }
            buf[length] = '\0';
            out->data = buf;
            out->len = (int32_t)length;
            rc = MTUCK_RC_OK;
          }
        }
      }
    }
  }

  if (pool != NULL) {
    mtuck_send(pool, "drain");
  }
  return rc;
}

static int mtuck_write_native(const char *text, int32_t len) {
  Class pasteboard_class = objc_getClass("NSPasteboard");
  if (pasteboard_class == NULL) {
    return MTUCK_RC_NO_BACKEND;
  }
  id pasteboard = mtuck_send((id)pasteboard_class, "generalPasteboard");
  if (pasteboard == NULL) {
    return MTUCK_RC_NO_DISPLAY;
  }
  Class string_class = objc_getClass("NSString");
  if (string_class == NULL) {
    return MTUCK_RC_NO_BACKEND;
  }
  if (memchr(text, '\0', (size_t)len) != NULL) {
    return MTUCK_RC_WRITE_FAILED;
  }
  /* [[NSString alloc] initWithBytes:len encoding:NSUTF8StringEncoding] */
  id value = ((id(*)(id, SEL, const void *, unsigned long, unsigned long))objc_msgSend)(
    ((id(*)(id, SEL))objc_msgSend)((id)string_class, sel_registerName("alloc")),
    sel_registerName("initWithBytes:length:encoding:"),
    text,
    (unsigned long)len,
    (unsigned long)4);
  if (value == NULL) {
    return MTUCK_RC_WRITE_FAILED;
  }
  /* 类型名用字面量字符串，免去依赖 AppKit 的 NSPasteboardTypeString 常量。 */
  Class nsstring_class = objc_getClass("NSString");
  id type_name = ((id(*)(id, SEL, const char *))objc_msgSend)(
    (id)nsstring_class, sel_registerName("stringWithUTF8String:"), "public.utf8-plain-text");
  if (type_name == NULL) {
    mtuck_send(value, "release");
    return MTUCK_RC_WRITE_FAILED;
  }
  mtuck_send(pasteboard, "clearContents");
  BOOL ok = ((BOOL(*)(id, SEL, id, id))objc_msgSend)(
    pasteboard, sel_registerName("setString:forType:"), value, type_name);
  mtuck_send(value, "release");
  return ok ? MTUCK_RC_OK : MTUCK_RC_WRITE_FAILED;
}

#else
/* --------------------------------------------------------------- 类 Unix */

static int mtuck_redirect_stdin(const char *input_path) {
  int fd = open(input_path, O_RDONLY);
  if (fd < 0) {
    return 0;
  }
  dup2(fd, STDIN_FILENO);
  close(fd);
  return 1;
}

/* 把读到的字节追加进 out，返回 1 表示成功。 */
static int mtuck_append(mtuck_buffer *out, const char *chunk, ssize_t len) {
  char *next = (char *)realloc(out->data, (size_t)out->len + (size_t)len + 1);
  if (next == NULL) {
    return 0;
  }
  memcpy(next + out->len, chunk, (size_t)len);
  out->data = next;
  out->len += (int32_t)len;
  out->data[out->len] = '\0';
  return 1;
}

/* 子进程硬超时。后端卡在等图形服务器响应时不能把 mtuck 一起拖死；
 * MTUCK_CLIPBOARD_TIMEOUT_MS 只是给调试留的逃生口。 */
static int32_t mtuck_child_timeout_ms(void) {
  const char *override = getenv("MTUCK_CLIPBOARD_TIMEOUT_MS");
  if (override != NULL && override[0] != '\0') {
    int value = atoi(override);
    if (value >= 10) {
      return value;
    }
  }
  return MTUCK_CHILD_TIMEOUT_MS;
}

/* 跑完一个子命令，带超时。返回子进程退出码，-1 表示 fork/exec 失败或超时。
 * collected 不为 NULL 时收集子进程 stdout（超过 MTUCK_MAX_TEXT 直接判失败）。
 * 超时后先 SIGTERM 再 SIGKILL，原因见 mtuck_child_timeout_ms。 */
static int mtuck_run_child(
  const mtuck_tool *tool,
  const char *input_path,
  mtuck_buffer *collected
) {
  int out_pipe[2] = {-1, -1};
  if (collected != NULL && pipe(out_pipe) != 0) {
    return -1;
  }
  fflush(stdout);
  fflush(stderr);
  pid_t pid = fork();
  if (pid < 0) {
    if (collected != NULL) {
      close(out_pipe[0]);
      close(out_pipe[1]);
    }
    return -1;
  }
  if (pid == 0) {
    int devnull = open("/dev/null", O_RDWR);
    if (input_path != NULL) {
      if (!mtuck_redirect_stdin(input_path)) {
        _exit(126);
      }
    } else if (devnull >= 0) {
      dup2(devnull, STDIN_FILENO);
    }
    if (collected != NULL) {
      dup2(out_pipe[1], STDOUT_FILENO);
      close(out_pipe[0]);
      close(out_pipe[1]);
    } else if (devnull >= 0) {
      dup2(devnull, STDOUT_FILENO);
    }
    if (devnull >= 0) {
      dup2(devnull, STDERR_FILENO);
      close(devnull);
    }
    execvp(tool->program, (char *const *)tool->argv);
    /* execvp 失败：沿用 shell 的约定，127 = 命令不存在，126 = 不可执行 */
    _exit(errno == ENOENT ? 127 : 126);
  }

  if (collected != NULL) {
    close(out_pipe[1]);
    char chunk[4096];
    int overflow = 0;
    while (1) {
      ssize_t got = read(out_pipe[0], chunk, sizeof(chunk));
      if (got > 0) {
        if (!mtuck_append(collected, chunk, got) || collected->len > MTUCK_MAX_TEXT) {
          overflow = 1;
          break;
        }
      } else if (got == 0) {
        break;
      } else if (errno != EINTR) {
        overflow = 1;
        break;
      }
    }
    close(out_pipe[0]);
    if (overflow) {
      /* 内容太大就不必等它写完了，直接杀掉。 */
      kill(pid, SIGKILL);
      waitpid(pid, NULL, 0);
      return -1;
    }
  }

  int32_t timeout_ms = mtuck_child_timeout_ms();
  int32_t waited = 0;
  int status = 0;
  while (1) {
    pid_t done = waitpid(pid, &status, WNOHANG);
    if (done == pid) {
      return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    }
    if (done < 0 && errno != EINTR) {
      return -1;
    }
    if (waited >= timeout_ms) {
      break;
    }
    struct timespec nap = {0, 5 * 1000 * 1000};
    nanosleep(&nap, NULL);
    waited += 5;
  }
  kill(pid, SIGTERM);
  for (int i = 0; i < 20; i++) {
    if (waitpid(pid, &status, WNOHANG) == pid) {
      return -1;
    }
    struct timespec nap = {0, 5 * 1000 * 1000};
    nanosleep(&nap, NULL);
  }
  kill(pid, SIGKILL);
  waitpid(pid, &status, 0);
  return -1;
}

/* 依次尝试工具列表，第一个成功的就是后端。全部失败时按“最像的原因”回报：
 * 全部不存在 → 没有后端；存在但不可执行 → 执行失败；其余 → 读写失败。 */
static int mtuck_try_tools(
  const mtuck_tool *tools,
  int count,
  const char *input_path,
  mtuck_buffer *collected,
  int write_mode
) {
  int saw_missing = 0;
  int saw_exec_error = 0;
  for (int i = 0; i < count; i++) {
    int rc = mtuck_run_child(&tools[i], input_path, collected);
    if (rc == 0) {
      return MTUCK_RC_OK;
    }
    if (collected != NULL && collected->data != NULL) {
      free(collected->data);
      collected->data = NULL;
      collected->len = 0;
    }
    if (rc == 127) {
      saw_missing = 1;
    } else if (rc == 126) {
      saw_exec_error = 1;
    }
  }
  if (saw_missing && !saw_exec_error) {
    return MTUCK_RC_NO_BACKEND;
  }
  return write_mode ? MTUCK_RC_WRITE_FAILED : MTUCK_RC_READ_FAILED;
}

#if defined(__linux__)

static const char *const mtuck_wl_paste_argv[] = {"wl-paste", "--no-newline", NULL};
static const char *const mtuck_xclip_read_argv[] = {
  "xclip", "-selection", "clipboard", "-o", NULL};
static const char *const mtuck_xsel_read_argv[] = {
  "xsel", "--clipboard", "--output", NULL};
static const char *const mtuck_wl_copy_argv[] = {"wl-copy", NULL};
static const char *const mtuck_xclip_write_argv[] = {
  "xclip", "-selection", "clipboard", "-i", NULL};
static const char *const mtuck_xsel_write_argv[] = {
  "xsel", "--clipboard", "--input", NULL};

static const mtuck_tool mtuck_read_tools[] = {
  {"wl-paste", mtuck_wl_paste_argv},
  {"xclip", mtuck_xclip_read_argv},
  {"xsel", mtuck_xsel_read_argv},
};

static const mtuck_tool mtuck_write_tools[] = {
  {"wl-copy", mtuck_wl_copy_argv},
  {"xclip", mtuck_xclip_write_argv},
  {"xsel", mtuck_xsel_write_argv},
};

#define MTUCK_READ_TOOL_COUNT ((int)(sizeof(mtuck_read_tools) / sizeof(mtuck_read_tools[0])))
#define MTUCK_WRITE_TOOL_COUNT ((int)(sizeof(mtuck_write_tools) / sizeof(mtuck_write_tools[0])))

/* 临时文件：xclip / wl-copy 都要从 stdin 读，跨进程写管道容易在 fork 后
 * 复制一份写端导致子进程永远等不到 EOF，所以先把文本落到临时文件再重定向。 */
static int mtuck_make_temp_file(const char *text, int32_t len, char *path, size_t path_size) {
  const char *dir = getenv("TMPDIR");
  if (dir == NULL || dir[0] == '\0') {
    dir = "/tmp";
  }
  int written = snprintf(path, path_size, "%s/mtuck-clip-XXXXXX", dir);
  if (written <= 0 || (size_t)written >= path_size) {
    return 0;
  }
  int fd = mkstemp(path);
  if (fd < 0) {
    return 0;
  }
  int32_t offset = 0;
  while (offset < len) {
    ssize_t put = write(fd, text + offset, (size_t)(len - offset));
    if (put <= 0) {
      if (errno == EINTR) {
        continue;
      }
      close(fd);
      unlink(path);
      return 0;
    }
    offset += (int32_t)put;
  }
  close(fd);
  return 1;
}

static int mtuck_read_native(mtuck_buffer *out) {
  out->data = NULL;
  out->len = 0;
  return mtuck_try_tools(mtuck_read_tools, MTUCK_READ_TOOL_COUNT, NULL, out, 0);
}

static int mtuck_write_native(const char *text, int32_t len) {
  char path[4096];
  if (!mtuck_make_temp_file(text, len, path, sizeof(path))) {
    return MTUCK_RC_WRITE_FAILED;
  }
  int rc = mtuck_try_tools(mtuck_write_tools, MTUCK_WRITE_TOOL_COUNT, path, NULL, 1);
  unlink(path);
  return rc;
}

#else

static int mtuck_read_native(mtuck_buffer *out) {
  out->data = NULL;
  out->len = 0;
  return MTUCK_RC_NO_BACKEND;
}

static int mtuck_write_native(const char *text, int32_t len) {
  (void)text;
  (void)len;
  return MTUCK_RC_NO_BACKEND;
}

#endif
#endif

/* ------------------------------------------------------------ 分发出口 */

/* 平台分派层：Windows / macOS 走原生 API，其余走图形服务器命令行后端。
 * 指向原生实现而不是直接写在 FFI 出口里，macOS 分支里才不用再套一层 #if。 */
static int mtuck_read_dispatch(mtuck_buffer *out) { return mtuck_read_native(out); }

static int mtuck_write_dispatch(const char *text, int32_t len) {
  return mtuck_write_native(text, len);
}

/* ------------------------------------------------------------- FFI 出口 */

static moonbit_bytes_t mtuck_bytes_or_empty(const char *data, int32_t len) {
  if (data == NULL || len <= 0) {
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, data, (size_t)len);
  return bytes;
}

/* MoonBit 侧用一个 8 字节的 Bytes 承接送回的字节数组：
 * FFI 的返回值要留给结果码，文本地址写在调用方给的缓冲区头 8 个字节里。
 * 失败（含“内容不是文本”）时写空数组并返回对应错误码。 */
#define MTUCK_PAYLOAD_OFFSET 8

MOONBIT_FFI_EXPORT int32_t mtuck_clipboard_read(moonbit_bytes_t bytes) {
  if (bytes == NULL || Moonbit_array_length(bytes) < MTUCK_PAYLOAD_OFFSET) {
    return MTUCK_RC_READ_FAILED;
  }
  mtuck_buffer buffer = {0, NULL};
  int rc = mtuck_read_dispatch(&buffer);
  if (rc != MTUCK_RC_OK) {
    *(moonbit_bytes_t *)bytes = moonbit_make_bytes(0, 0);
    return rc;
  }
  /* 含 NUL 的内容不是可记录的文本（图片、二进制转储），当作读到了非文本。 */
  if (buffer.len > 0 && memchr(buffer.data, '\0', (size_t)buffer.len) != NULL) {
    free(buffer.data);
    *(moonbit_bytes_t *)bytes = moonbit_make_bytes(0, 0);
    return MTUCK_RC_READ_FAILED;
  }
  *(moonbit_bytes_t *)bytes = mtuck_bytes_or_empty(buffer.data, buffer.len);
  free(buffer.data);
  return MTUCK_RC_OK;
}

/* 写剪贴板文本，text 是 UTF-8 字节。返回 0 成功，其他见文件头的错误码。 */
MOONBIT_FFI_EXPORT int32_t mtuck_clipboard_write(moonbit_bytes_t text) {
  int32_t len = Moonbit_array_length(text);
  return mtuck_write_dispatch((const char *)text, len);
}

/* 平台名，与 MoonBit 侧 `detect` 的约定一致：windows / macos / linux / 其他。 */
MOONBIT_FFI_EXPORT moonbit_bytes_t mtuck_os_name(void) {
#if defined(_WIN32)
  const char *name = "windows";
#elif defined(__APPLE__)
  const char *name = "macos";
#elif defined(__linux__)
  const char *name = "linux";
#else
  const char *name = "unknown";
#endif
  return mtuck_bytes_or_empty(name, (int32_t)strlen(name));
}

/* 路径是否存在。符号链接按“存在”算；`DISPLAY` 的 socket 判定用它。 */
MOONBIT_FFI_EXPORT int32_t mtuck_path_exists(moonbit_bytes_t path) {
  char buffer[4096];
  int32_t len = Moonbit_array_length(path);
  if (len <= 0 || len >= (int32_t)sizeof(buffer)) {
    return 0;
  }
  memcpy(buffer, path, (size_t)len);
  buffer[len] = '\0';
#if defined(_WIN32)
  return GetFileAttributesA(buffer) == INVALID_FILE_ATTRIBUTES ? 0 : 1;
#else
  return access(buffer, F_OK) == 0 ? 1 : 0;
#endif
}

/* 把 `mtuck_clipboard_read` 写回 slot 的字节数组取出来。空指针表示没有文本。 */
MOONBIT_FFI_EXPORT moonbit_bytes_t mtuck_clipboard_slot_bytes(moonbit_bytes_t slot) {
  if (slot == NULL || Moonbit_array_length(slot) < MTUCK_PAYLOAD_OFFSET) {
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t payload = *(moonbit_bytes_t *)slot;
  if (payload == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  return payload;
}

/* 原生后端（不依赖外部命令）的别名：Windows 是 "Windows"，macOS 是 "AppKit"。 */
MOONBIT_FFI_EXPORT moonbit_bytes_t mtuck_clipboard_native_kind(void) {
#if defined(_WIN32)
  const char *kind = "Windows";
#elif defined(__APPLE__)
  const char *kind = "AppKit";
#else
  const char *kind = "";
#endif
  return mtuck_bytes_or_empty(kind, (int32_t)strlen(kind));
}
