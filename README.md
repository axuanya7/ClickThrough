# ClickThrough

把任意一个窗口浮在**游戏画面之上**：正常显示、正常播放，但**鼠标点击完全穿透过去落到游戏上**，全程不抢焦点。适合挂机打游戏时在旁边看视频、看文档。

纯 Win32 实现，只给目标窗口加三个扩展窗口样式，没有任何注入、没有 API Hook。

- 系统要求：Windows 10 / 11
- 不需要管理员权限（除非游戏本身以管理员身份运行，见下文）

---

## 下载安装

到 [Releases](../../releases) 页下载 `ClickThrough-Setup.exe`，双击安装。装到 `%LOCALAPPDATA%\Programs\ClickThrough`，同时会创建开始菜单快捷方式，可勾选桌面快捷方式和开机自启。

不想安装也可以直接下 `ClickThrough.exe` 便携版，双击即用，配置和日志写在 exe 同目录。

### 首次运行时 Windows 会拦一下

这个程序用 AutoHotkey 编译，会注册全局热键、修改别的窗口样式，**Defender 和国产杀软大概率误报**，这是 AutoHotkey 这类工具的共性，不是真的有恶意代码。处理方式：

- SmartScreen 蓝屏提示 → 「更多信息」→「仍要运行」
- Defender 直接删了文件 → 把它加进排除项，或者给解压目录加白名单
- 实在不放心 → 源码全部在这个仓库里，`src\ClickThrough.ahk` 就是全部逻辑，自己看，自己用 `build.ps1` 编译

---

## 怎么用

启动后没有主窗口，只在右下角托盘有个图标。

第一次用：按 `Ctrl+Alt+2` 选「顶层窗口」——也就是你想浮在上面看的那个（浏览器、播放器等）。然后按 `Ctrl+Alt+D` 锁定。锁定之后那个窗口就变成置顶、可看可播、但鼠标点它等于点在游戏上。

| 热键 | 作用 |
|---|---|
| `Ctrl+Alt+1` | 选择**底层窗口**（游戏本体，点击穿透后落到的那个） |
| `Ctrl+Alt+2` | 选择**顶层窗口**（浮在上面看的那个） |
| `Ctrl+Alt+D` | 锁定 / 解锁 |
| `Ctrl+Alt+S` | 不透明度 100% ↔ 0% 对切（0 = 完全看不见，但还在播放） |
| `Ctrl+Alt+Q` | 退出（会弹确认框） |

托盘图标右键菜单里还有：系统设置、检查更新、打开日志、关于。双击托盘图标也能开系统设置。

### 系统设置

一个独立窗口，可以：

- 手动选顶层 / 底层窗口（比记热键直观，每个选项都带说明）
- 开关开机自启、开关「启动后自动锁定」
- 立即锁定 / 解锁、打开日志、检查更新

---

## 锁住了解不开怎么办

穿透之后那个窗口是**点不到**的，这是设计使然。所以有三道后路：

1. 按 `Ctrl+Alt+D` 解锁
2. **再双击一次程序**——第二次启动会被当成求救信号，顺手把粘住的窗口解开并弹窗告诉你
3. 看门狗子进程——主进程被强杀或卡死时，它会在几秒内自动解锁

还有最后一道：命令行跑 `ClickThrough.exe --unlock`，一次性把全系统处于穿透状态的窗口都解开，然后把结果写进 `unlock-log.txt`。

---

## 原理

给目标窗口 `SetWindowLong(GWL_EXSTYLE)` 加三个扩展样式，再配 `SetWindowPos(HWND_TOPMOST)`：

| 样式 | 值 | 作用 |
|---|---|---|
| `WS_EX_LAYERED` | `0x00080000` | 分层窗口，是下面那个生效的前提 |
| `WS_EX_TRANSPARENT` | `0x00000020` | 鼠标命中测试穿透，点击落到 z-order 下层窗口 |
| `WS_EX_NOACTIVATE` | `0x08000000` | 永不抢焦点 |

透明度用 `SetLayeredWindowAttributes(hwnd, 0, alpha, LWA_ALPHA)`。

解锁时顺序不能乱：先摘 `TRANSPARENT`，再摘 `NOACTIVATE`，再摘 `LAYERED`，最后关置顶、复位透明度、强制重绘。

为什么锁定时要先激活底层窗口：穿透的点击落到的是 z-order 下方的窗口，不先把你指定的游戏顶上来，点击可能落到别的窗口上。

### 为什么是两个进程

单进程做不到自我救援——脚本被强杀时它自己没机会清理样式，窗口就永久粘在穿透状态。所以主进程每秒写一次心跳文件，看门狗子进程每秒检查：有窗口还带着穿透样式 且 心跳超过 5 秒没更新 → 判定主进程失联 → 摘样式 → 自杀。

---

## 已知问题

- **游戏以管理员身份运行时热键可能送不进去**，这时本程序也要用管理员身份运行
- 多显示器 / 高 DPI 场景没做过严格测试
- 由 `WS_EX_TRANSPARENT` 决定的穿透是整窗口级的，不能只让窗口的一部分可点
- 杀软误报，见上文

### 排查用日志

- 程序运行日志：`overlay-log.txt`，在主程序同目录（托盘菜单里也能直接打开）
- 安装器日志：`%TEMP%\ClickThrough-Setup.log`

---

## 从源码构建

需要 AutoHotkey v2 和 Ahk2Exe（[下载](https://github.com/AutoHotkey/Ahk2Exe/releases)，解压到 AutoHotkey 目录下的 `Compiler\` 里）。

```powershell
# AutoHotkey 目录下应有 v2\AutoHotkey64.exe 和 Compiler\Ahk2Exe.exe
.\build.ps1 -AhkRoot "C:\Program Files\AutoHotkey"

# 指定版本号（默认读 version.txt）
.\build.ps1 -AhkRoot "C:\Program Files\AutoHotkey" -Version 1.1.0
```

产物在 `dist\`：

- `ClickThrough.exe` —— 主程序
- `ClickThrough-Setup.exe` —— 单文件安装包，自带卸载器

改版本号只改 `version.txt` 一处，构建时会自动替换源码里的 `@@VERSION@@`。

---

## 自动更新

托盘菜单 →「检查更新」，会去 GitHub 查最新 release：

- 有新版本 → 读 release 说明，问你要不要装
- 确认后自动下载 `ClickThrough-Setup.exe` 到临时目录，主进程退出，安装器静默覆盖并重新启动

所以更新链依赖 release 里有一个名叫 `ClickThrough-Setup.exe` 的附件，发版脚本要注意这个命名。

---

## 目录结构

```
src\ClickThrough.ahk            主程序（单文件：主模式 + 看门狗 + 一次性解锁）
src\ClickThrough-Setup.ahk      安装包（FileInstall 把主程序和卸载器嵌进去）
src\ClickThrough-Uninstall.ahk  卸载器
assets\icon.ico                 图标
tools\make_icon.py              生成图标
build.ps1                       构建脚本
version.txt                     版本号（唯一来源）
```

运行时会在主程序同目录生成 `overlay-config.ini`（你选的窗口）、`overlay-log.txt`（日志）、`overlay-heartbeat.txt`（心跳）。

---

## License

MIT
