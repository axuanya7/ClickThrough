# ClickThrough

ClickThrough 是一款 Windows 小工具：把任意窗口浮在游戏画面之上，正常显示、正常播放，而鼠标点击会完全穿透到下面的游戏，全程不抢焦点。适合挂机打游戏时在旁边看视频、看文档。

## 主要功能

- 任意窗口都能浮在游戏上层，鼠标点击直接落到下面的游戏，不打断操作
- 锁定后置顶且不抢焦点，游戏里该怎么点还怎么点
- 快捷键把不透明度在 100% 和 0% 之间切换，0% 时画面看不见但仍在播放
- 系统设置里手动挑顶层、底层窗口，可选开机自启和启动后自动锁定
- 三道保险：全局热键解锁、退出时自动清理、看门狗子进程兜底
- 万一锁住解不开，再双击一次程序会自动把粘住的窗口解开
- 启动时检查 GitHub Releases，发现新版本可在软件内直接下载更新

## 下载

最新版本：

- [GitHub Releases](https://github.com/axuanya7/ClickThrough/releases/latest)
- [ClickThrough-Setup.exe](https://github.com/axuanya7/ClickThrough/releases/latest/download/ClickThrough-Setup.exe)（安装版）
- [ClickThrough.exe](https://github.com/axuanya7/ClickThrough/releases/latest/download/ClickThrough.exe)（便携版）

推荐使用安装版，安装时可以选择安装位置，更新时可在软件内直接下载替换。装完在「设置 → 应用」里可以正常卸载。便携版解压即用，配置写在 exe 同目录。

程序用 AutoHotkey 编译，会注册全局热键、修改其他窗口的样式，Defender 和国产杀软大概率误报，属于这类工具的共性。SmartScreen 提示时点「更多信息」→「仍要运行」；文件被删就把它加进排除项。

## 使用说明

1. 启动后没有主窗口，只在右下角托盘放一个图标。
2. 按 `Ctrl+Alt+2` 选「顶层窗口」，也就是你打算浮在上面的那个（浏览器、播放器等）。
3. 按 `Ctrl+Alt+D` 锁定：该窗口变置顶、鼠标完全穿透。再按一次解锁。
4. 右键托盘图标可以打开系统设置、检查更新、打开日志或退出。

| 热键 | 作用 |
|---|---|
| `Ctrl+Alt+1` | 选择底层窗口（游戏本体，点击穿透后落到它上面） |
| `Ctrl+Alt+2` | 选择顶层窗口（浮在上面看的那个） |
| `Ctrl+Alt+D` | 锁定 / 解锁 |
| `Ctrl+Alt+S` | 不透明度 100% ↔ 0% |
| `Ctrl+Alt+Q` | 退出程序 |

## 配置

主程序同目录会生成两个文件：`overlay-config.ini` 记录你选的窗口，`overlay-log.txt` 是运行日志。安装版默认装在 `%LOCALAPPDATA%\Programs\ClickThrough`，安装时也可以改到别的位置。

## 出问题了

- **窗口锁住点不动**：再双击一次程序，它会把粘住的窗口解开。也可以在命令行跑 `ClickThrough.exe --unlock`。
- **热键没反应**：如果游戏以管理员身份运行，本程序也要用管理员身份启动，否则热键送不进去。
- **想看日志**：托盘菜单 → 打开日志，或直接看主程序同目录的 `overlay-log.txt`。
- 多显示器和多倍 DPI 场景没有做严格测试。
