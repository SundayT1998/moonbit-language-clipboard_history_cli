/* 平台“剪贴板变更计数”的 C 侧实现。
 * 有原生接口就直接问系统，没有就返回 0 —— 上层收到 0 会退化成轮询读文本。 */
#include <stdint.h>

#if defined(__APPLE__)
#include <objc/message.h>
#include <objc/runtime.h>

uint64_t mtuck_clipboard_change_token(void) {
  Class pbcls = objc_getClass("NSPasteboard");
  if (pbcls == NULL) {
    return 0;
  }
  SEL general = sel_registerName("generalPasteboard");
  id pb = ((id(*)(id, SEL))objc_msgSend)((id)pbcls, general);
  if (pb == NULL) {
    return 0;
  }
  SEL change_count = sel_registerName("changeCount");
  return (uint64_t)((long(*)(id, SEL))objc_msgSend)(pb, change_count);
}

#elif defined(_WIN32)
#include <windows.h>

uint64_t mtuck_clipboard_change_token(void) {
  return (uint64_t)GetClipboardSequenceNumber();
}

#else

uint64_t mtuck_clipboard_change_token(void) { return 0; }

#endif
