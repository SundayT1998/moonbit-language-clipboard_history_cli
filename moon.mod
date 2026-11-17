// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "SundayT1998/mtuck"

version = "0.1.1"

readme = "README.mbt.md"

repository = "https://github.com/SundayT1998/moonbit-language-clipboard_history_cli"

license = "Apache-2.0"

keywords = [ "clipboard", "history", "cli", "productivity" ]

preferred_target = "native"

description = "Moonbit 实现的终端剪贴板历史 cli 工具"

import {
  "moonbit-community/proton_clipboard@0.9.0",
  "moonbitlang/x@0.5.7",
}
