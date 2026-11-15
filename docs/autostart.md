# 开机自启 `watch`

## macOS（launchd）

`~/Library/LaunchAgents/dev.mtuck.watch.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>dev.mtuck.watch</string>
  <key>ProgramArguments</key>
  <array><string>/Users/me/.local/bin/mtuck</string><string>watch</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/mtuck-watch.log</string>
  <key>StandardErrorPath</key><string>/tmp/mtuck-watch.log</string>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/dev.mtuck.watch.plist
```

## Linux（systemd --user）

`~/.config/systemd/user/mtuck-watch.service`：

```ini
[Unit]
Description=mtuck clipboard history watcher

[Service]
ExecStart=%h/.local/bin/mtuck watch
Restart=always
Environment=MTUCK_DIR=%h/.local/share/mtuck

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now mtuck-watch
```

## Windows（任务计划程序）

```powershell
schtasks /Create /SC ONLOGON /TN "mtuck watch" /TR "C:\tools\mtuck.exe watch" /RL LIMITED
```

---

[← 返回 README](../README.mbt.md)
