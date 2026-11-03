#Requires AutoHotkey v2.0
#SingleInstance Off
;==================================================================
;  ClickThrough —— 窗口穿透浮层
;
;  把任意窗口浮在游戏画面上：正常显示、正常播放，
;  鼠标点击完全穿透到下面的窗口，全程不抢焦点。
;
;  https://github.com/axuanya7/ClickThrough   ·   MIT License
;
;  Ctrl+Alt+1   选择底层窗口（点击落到的那个，一般是游戏）
;  Ctrl+Alt+2   选择顶层窗口（浮在上面看的那个）
;  Ctrl+Alt+D   锁定 / 解锁（置顶 + 鼠标穿透 + 不抢焦点）
;  Ctrl+Alt+S   不透明度 100% <-> 0%
;  Ctrl+Alt+Q   退出脚本（弹确认框）
;
;  三道保险：
;    1. 热键走系统级 RegisterHotKey，不用低级键盘钩子
;    2. OnExit：退出时自动摘掉穿透样式
;    3. 看门狗子进程：主进程被强杀或卡死，自动解锁
;
;  热键全部失灵时：再双击一次本程序，它会把这次启动当成求救信号，
;  顺手解开粘住的窗口并弹窗告诉你。
;==================================================================

APPNAME     := "ClickThrough"
AppVer      := "@@VERSION@@"
RepoSlug    := "axuanya7/ClickThrough"
RepoWeb     := "https://github.com/axuanya7/ClickThrough"
if InStr(AppVer, "@@")
    AppVer := "0.0.0-dev"                   ; 直接跑源码（未经过 build.ps1）时的版本号

Dir         := A_ScriptDir
IniFile     := Dir "\overlay-config.ini"
HeartFile   := Dir "\overlay-heartbeat.txt"
LogFile     := Dir "\overlay-log.txt"

TopExe      := IniRead(IniFile, "target", "top_exe", "")
TopTitle    := IniRead(IniFile, "target", "top_title", "")
BottomExe   := IniRead(IniFile, "target", "bottom_exe", "")
BottomTitle := IniRead(IniFile, "target", "bottom_title", "")

alphas      := [255, 0]
alphaIdx    := 1
lockedHwnd  := 0
WatchdogPid := 0
SettingsGui := 0
Updating    := false

if (A_Args.Length > 0) {
    switch A_Args[1] {
        case "--watchdog": WatchdogMode()
        case "--unlock":   UnlockMode()
        case "--settings": SettingsMode()
        case "--check-update":
            CheckUpdate(true)
            ExitApp()
        default:           MainMode()
    }
} else {
    MainMode()
}

;==================================================================
;  主模式
;==================================================================
MainMode() {
    global IniFile, TopExe, TopTitle, BottomExe, BottomTitle, WatchdogPid, HeartFile, APPNAME, AppVer

    hMutex := DllCall("CreateMutexW", "Ptr", 0, "Int", 0, "WStr", "Local\ClickThroughMain", "Ptr")
    if (A_LastError = 183) {
        ; 已有实例 → 把这次启动当成求救信号
        n := CleanupAll()
        MsgBox(APPNAME " 已经在运行中。`n`n已顺带帮你解锁 " n " 个窗口。`n`n（故意这么设计：热键失灵、窗口点不动时，再双击一次本程序也能救回来）", APPNAME, "Iconi T8")
        ExitApp()
    }

    OnExit(OnExitHandler)

    n := CleanupAll()
    Log("启动 v" AppVer " · 清扫残留 " n " 个窗口")
    Log("当前配置 · 顶层=" (TopExe = "" ? "未设置" : TopExe " | " TopTitle) " · 底层=" (BottomExe = "" ? "未设置" : BottomExe " | " BottomTitle))

    Heartbeat()
    SetTimer(Heartbeat, 1000)

    try {
        ; 编译成 exe 后 A_AhkPath 与 A_ScriptFullPath 都指向 exe 自身。
        ; 若还照原样拼两个路径，--watchdog 会掉进 A_Args[2]，子进程按 A_Args[1]
        ; 走成主模式 → 撞 mutex → 弹"已在运行"并把窗口解锁。所以编译版只传 exe 本身。
        wdCmd := A_IsCompiled
            ? '"' A_ScriptFullPath '" --watchdog'
            : '"' A_AhkPath '" "' A_ScriptFullPath '" --watchdog"'
        WatchdogPid := Run(wdCmd)
        Log("看门狗已拉起")
    } catch as e {
        Log("看门狗启动失败: " e.Message)
    }

    Reg("^!1", PickBottom, "Ctrl+Alt+1")
    Reg("^!2", PickTop,    "Ctrl+Alt+2")
    Reg("^!d", ToggleOverlay, "Ctrl+Alt+D")
    Reg("^!s", ToggleAlpha,   "Ctrl+Alt+S")
    Reg("^!q", QuitApp,       "Ctrl+Alt+Q")

    BuildTrayMenu()

    if (IniRead(IniFile, "app", "auto_lock", "0") = "1") {
        Log("按设置自动锁定")
        SetTimer(DoAutoLock, -1500)
    }

    if (TopExe = "")
        Tip("ClickThrough 就绪 · 先按 Ctrl+Alt+2 选要浮在上面的窗口")
    else
        Tip("ClickThrough 就绪 · Ctrl+Alt+D 锁定")
}

DoAutoLock(*) {
    global TopExe
    if (TopExe = "") {
        Log("自动锁定跳过 · 未设置顶层窗口")
        return
    }
    ToggleOverlay()
}

BuildTrayMenu() {
    global APPNAME
    A_IconTip := APPNAME " · 窗口穿透浮层"
    m := A_TrayMenu
    m.Delete()
    m.Add("系统设置(&S)…", (*) => OpenSettings())
    m.Add("检查更新(&U)…", (*) => CheckUpdate(true))
    m.Add()
    m.Add("选择底层窗口`tCtrl+Alt+1", PickBottom)
    m.Add("选择顶层窗口`tCtrl+Alt+2", PickTop)
    m.Add("锁定 / 解锁`tCtrl+Alt+D", ToggleOverlay)
    m.Add("不透明度 100%/0%`tCtrl+Alt+S", ToggleAlpha)
    m.Add()
    m.Add("打开日志", (*) => OpenLog())
    m.Add("关于", (*) => About())
    m.Add()
    m.Add("退出`tCtrl+Alt+Q", QuitApp)
    m.Default := "系统设置(&S)…"
    m.ClickCount := 2
}

Reg(key, fn, label) {
    try {
        Hotkey(key, fn)
        Log("热键 " label " 注册成功")
    } catch as e {
        Log("热键 " label " 注册失败: " e.Message)
    }
}

;==================================================================
;  选择窗口
;==================================================================
PickBottom(*) {
    PickWindow("bottom")
}

PickTop(*) {
    PickWindow("top")
}

PickWindow(which, onPicked := 0) {
    label := (which = "top") ? "顶层窗口（浮在上面看，点不动）" : "底层窗口（游戏，点击落到它上面）"

    g := Gui("+AlwaysOnTop +Resize", "选择窗口 —— " label)
    g.SetFont("s10", "Microsoft YaHei UI")
    g.MarginX := 10
    g.MarginY := 10

    tip := (which = "top")
        ? "挑一个要浮在游戏上面的窗口（浏览器、播放器等）。锁定后它会置顶，但鼠标点击会穿透过去。"
        : "挑一个接收点击的窗口，一般是游戏本体窗口。锁定时会先激活它，保证穿透的点击落在它身上。"
    g.Add("Text", "x10 y10 w780 cGray", tip)

    lv := g.Add("ListView", "x10 y38 w780 h400", ["HWND", "进程", "标题"])
    lv.ModifyCol(1, 110)
    lv.ModifyCol(2, 170)
    lv.ModifyCol(3, 480)

    entries := []
    for hwnd in WinGetList() {
        try {
            if !DllCall("IsWindowVisible", "Ptr", hwnd)
                continue
            title := WinGetTitle(hwnd)
            if (title = "")
                continue
            exe := ProcessGetName(WinGetPID(hwnd))
            if (exe = "AutoHotkey64.exe" || exe = "AutoHotkey.exe" || exe = "AutoHotkeyUX.exe" || exe = "ClickThrough.exe")
                continue
            entries.Push({ hwnd: hwnd, exe: exe, title: title })
            lv.Add(, Format("0x{:X}", hwnd), exe, title)
        }
    }

    okBtn := g.Add("Button", "Default w120 x10 y446", "选这个")
    cancelBtn := g.Add("Button", "w120 x140 y446", "取消")

    doPick(*) {
        row := lv.GetNext()
        if !row {
            MsgBox("先在列表里点一行。", "选择窗口", "Iconi T3")
            return
        }
        e := entries[row]
        g.Destroy()
        SaveTarget(which, e.hwnd)
        Tip("已选择：" e.exe " — " e.title)
        if IsObject(onPicked)
            onPicked.Call()
    }

    okBtn.OnEvent("Click", doPick)
    cancelBtn.OnEvent("Click", (*) => g.Destroy())
    lv.OnEvent("DoubleClick", doPick)
    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.Show()
}

SaveTarget(which, hwnd) {
    global IniFile, TopExe, TopTitle, BottomExe, BottomTitle
    exe := ProcessGetName(WinGetPID(hwnd))
    title := WinGetTitle(hwnd)
    if (which = "top") {
        TopExe := exe
        TopTitle := title
        IniWrite(exe, IniFile, "target", "top_exe")
        IniWrite(title, IniFile, "target", "top_title")
        Log("设定顶层窗口: " exe " | " title)
    } else {
        BottomExe := exe
        BottomTitle := title
        IniWrite(exe, IniFile, "target", "bottom_exe")
        IniWrite(title, IniFile, "target", "bottom_title")
        Log("设定底层窗口: " exe " | " title)
    }
}

;==================================================================
;  系统设置窗口
;==================================================================
OpenSettings(*) {
    global SettingsGui, IniFile, TopExe, TopTitle, BottomExe, BottomTitle, APPNAME, AppVer, RepoWeb

    if (SettingsGui) {
        try {
            WinActivate(SettingsGui)
            return
        } catch {
            SettingsGui := 0
        }
    }

    g := Gui("+AlwaysOnTop +Resize -MaximizeBox", APPNAME " 系统设置")
    SettingsGui := g
    g.SetFont("s10", "Microsoft YaHei UI")
    g.MarginX := 16
    g.MarginY := 12

    g.SetFont("s10 Bold")
    g.Add("Text", "x16 y12 w620", "顶层窗口 —— 浮在上面看的那个")
    g.SetFont("s9", "Microsoft YaHei UI")
    g.Add("Text", "x16 y34 w620 cGray", "浏览器、播放器之类。锁定后它会被置顶、鼠标点击完全穿透、且永不抢焦点。")
    g.SetFont("s10", "Microsoft YaHei UI")
    edTop := g.Add("Edit", "x16 y56 w520 ReadOnly", "")
    btnTop := g.Add("Button", "x548 y55 w100", "选择…")

    g.SetFont("s10 Bold")
    g.Add("Text", "x16 y100 w620", "底层窗口 —— 点击穿透后落到的那个")
    g.SetFont("s9", "Microsoft YaHei UI")
    g.Add("Text", "x16 y122 w620 cGray", "一般是游戏本体。锁定时会先把它激活，保证穿透的鼠标点击落在它身上。")
    g.SetFont("s10", "Microsoft YaHei UI")
    edBottom := g.Add("Edit", "x16 y144 w520 ReadOnly", "")
    btnBottom := g.Add("Button", "x548 y143 w100", "选择…")

    cbAutoStart := g.Add("CheckBox", "x16 y188 w400", "开机自动启动")
    cbAutoLock  := g.Add("CheckBox", "x16 y214 w400", "启动后自动锁定（需先设置顶层窗口）")

    g.SetFont("s9", "Microsoft YaHei UI")
    g.Add("Text", "x16 y248 w620 cGray", "热键：Ctrl+Alt+1 底层 · 2 顶层 · D 锁定/解锁 · S 透明度 · Q 退出")

    g.SetFont("s10", "Microsoft YaHei UI")
    bLock  := g.Add("Button", "x16 y280 w140", "立即锁定 / 解锁")
    bLog   := g.Add("Button", "x166 y280 w100", "打开日志")
    bUpd   := g.Add("Button", "x276 y280 w110", "检查更新")
    bAbout := g.Add("Button", "x396 y280 w100", "关于")
    bClose := g.Add("Button", "x506 y280 w100 Default", "关闭")

    g.SetFont("s9", "Microsoft YaHei UI")
    g.Add("Text", "x16 y318 w620 cGray", "v" AppVer "   ·   " RepoWeb)

    Refresh(*) {
        global TopExe, TopTitle, BottomExe, BottomTitle
        edTop.Value := (TopExe = "") ? "（未设置 —— 点右边「选择…」挑一个）" : TopExe "   —   " TopTitle
        edBottom.Value := (BottomExe = "") ? "（未设置 —— 可选，会被激活到最前）" : BottomExe "   —   " BottomTitle
    }

    onClose(*) {
        global SettingsGui
        SettingsGui := 0
        g.Destroy()
    }

    cbAutoStart.Value := (IniRead(IniFile, "app", "autostart", "0") = "1")
    cbAutoLock.Value  := (IniRead(IniFile, "app", "auto_lock", "0") = "1")

    btnTop.OnEvent("Click", (*) => PickWindow("top", Refresh))
    btnBottom.OnEvent("Click", (*) => PickWindow("bottom", Refresh))
    cbAutoStart.OnEvent("Click", (ctrl, *) => SetAutoStart(ctrl.Value))
    cbAutoLock.OnEvent("Click", (ctrl, *) => SetAutoLock(ctrl.Value))
    bLock.OnEvent("Click", (*) => ToggleOverlay())
    bLog.OnEvent("Click", (*) => OpenLog())
    bUpd.OnEvent("Click", (*) => CheckUpdate(true))
    bAbout.OnEvent("Click", (*) => About())
    bClose.OnEvent("Click", onClose)
    g.OnEvent("Close", onClose)
    g.OnEvent("Escape", onClose)

    Refresh()
    g.Show("w680 h350")
}

SetAutoStart(on) {
    global IniFile, APPNAME
    key := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
    try {
        if (on)
            RegWrite('"' A_ScriptFullPath '"', "REG_SZ", key, APPNAME)
        else
            RegDelete(key, APPNAME)
    } catch as e {
        Log("开机自启写入失败: " e.Message)
        MsgBox("写入开机自启失败：`n" e.Message, APPNAME, "Icon! T8")
    }
    IniWrite(on ? 1 : 0, IniFile, "app", "autostart")
    Log("开机自启 " (on ? "已开启" : "已关闭"))
}

SetAutoLock(on) {
    global IniFile
    IniWrite(on ? 1 : 0, IniFile, "app", "auto_lock")
    Log("启动自动锁定 " (on ? "已开启" : "已关闭"))
}

About() {
    global AppVer, RepoWeb
    MsgBox("ClickThrough  v" AppVer "`n`n把任意窗口浮在游戏上层，正常显示、正常播放，"
        . "鼠标点击完全穿透到下层窗口，全程不抢焦点。`n`n"
        . "热键：Ctrl+Alt+1 / 2 选窗口，D 锁定解锁，S 调透明度，Q 退出。`n`n"
        . RepoWeb "`n`nMIT License", "关于 ClickThrough", "Iconi T25")
}

OpenLog() {
    global LogFile
    if !FileExist(LogFile) {
        Tip("还没有日志文件，运行一会儿再看")
        return
    }
    Run('notepad.exe "' LogFile '"')
}

;==================================================================
;  锁定 / 解锁
;==================================================================
ToggleOverlay(*) {
    global TopExe, TopTitle, BottomExe, BottomTitle, lockedHwnd, alphas, alphaIdx, APPNAME
    try {
        ; 已经锁定 → 解锁
        if (lockedHwnd && WinExist(lockedHwnd) && (WinGetExStyle(lockedHwnd) & 0x20)) {
            ClearClickThrough(lockedHwnd)
            Log("解锁 hwnd=" Format("0x{:X}", lockedHwnd))
            lockedHwnd := 0
            Tip("已解锁 · 可以操作了")
            return
        }
        ; 兜底：可能残留，按配置扫一遍
        m := CleanupByConfig()
        if (m > 0) {
            Log("解锁（扫描）" m " 个窗口")
            Tip("已解锁")
            return
        }

        hwnd := FindTopWindow()
        if !hwnd {
            MsgBox("还没选顶层窗口。`n`n按 Ctrl+Alt+2 选一个要浮在上面的窗口，或右键托盘图标 → 系统设置。", APPNAME, "Icon! T6")
            return
        }

        ; 先把底层窗口（游戏）顶到前面，保证穿透的点击落在它身上
        bh := FindBottomWindow()
        if (bh && bh != hwnd) {
            try WinActivate(bh)
            Sleep(80)
        }

        WinSetAlwaysOnTop(true, hwnd)
        alphaIdx := 1
        SetAlpha(hwnd, alphas[alphaIdx])
        WinSetExStyle("+0x80000", hwnd)      ; WS_EX_LAYERED     —— 穿透的前提
        WinSetExStyle("+0x20", hwnd)         ; WS_EX_TRANSPARENT —— 鼠标穿透
        WinSetExStyle("+0x8000000", hwnd)    ; WS_EX_NOACTIVATE  —— 不抢焦点

        lockedHwnd := hwnd
        Log("锁定 hwnd=" Format("0x{:X}", hwnd) " 标题=" WinGetTitle(hwnd))
        Tip("已锁定 · 鼠标穿透到下层（Ctrl+Alt+D 解锁）")
    } catch as e {
        Log("异常: " e.Message " @" e.Line)
        CleanupByConfig()
        MsgBox("出错了，已强制恢复：`n" e.Message, APPNAME, "Icon! T10")
    }
}

ToggleAlpha(*) {
    global alphas, alphaIdx, lockedHwnd
    hwnd := 0
    if (lockedHwnd && WinExist(lockedHwnd) && (WinGetExStyle(lockedHwnd) & 0x20))
        hwnd := lockedHwnd
    else {
        for h in WinGetList() {
            try {
                if (WinGetExStyle(h) & 0x80000) && (WinGetExStyle(h) & 0x20) && (WinGetExStyle(h) & 0x8000000) {
                    hwnd := h
                    break
                }
            }
        }
    }
    if !hwnd {
        Tip("先按 Ctrl+Alt+D 锁定，再调透明度")
        return
    }
    alphaIdx := (alphaIdx = 1) ? 2 : 1
    SetAlpha(hwnd, alphas[alphaIdx])
    Tip("不透明度 " Round(alphas[alphaIdx] / 255 * 100) "%")
}

QuitApp(*) {
    r := MsgBox("确定退出 ClickThrough？`n`n退出后 Ctrl+Alt 热键全部失效，想再用得重新启动。",
                "退出确认", "Icon? YesNo Default2 T15")
    if (r = "Yes")
        ExitApp()
}

;==================================================================
;  找窗口 / 清理
;==================================================================
FindTopWindow() {
    global TopExe, TopTitle
    if (TopTitle && TopExe) {
        h := WinExist(TopTitle " ahk_exe " TopExe)
        if h
            return h
    }
    if (TopExe) {
        h := WinExist("ahk_exe " TopExe)
        if h
            return h
    }
    return 0
}

FindBottomWindow() {
    global BottomExe, BottomTitle
    if (BottomTitle && BottomExe) {
        h := WinExist(BottomTitle " ahk_exe " BottomExe)
        if h
            return h
    }
    if (BottomExe) {
        h := WinExist("ahk_exe " BottomExe)
        if h
            return h
    }
    return 0
}

CleanupByConfig() {
    global TopExe
    n := 0
    if (TopExe = "")
        return 0
    for hwnd in WinGetList("ahk_exe " TopExe) {
        try {
            if (WinGetExStyle(hwnd) & 0x20) {
                ClearClickThrough(hwnd)
                n++
            }
        }
    }
    return n
}

CleanupAll() {
    global lockedHwnd
    n := 0
    if (lockedHwnd && WinExist(lockedHwnd)) {
        try {
            if (WinGetExStyle(lockedHwnd) & 0x20) {
                ClearClickThrough(lockedHwnd)
                n++
            }
        }
    }
    n += CleanupByConfig()
    lockedHwnd := 0
    return n
}

ClearClickThrough(hwnd) {
    try WinSetExStyle("-0x20", hwnd)
    try WinSetExStyle("-0x8000000", hwnd)
    try WinSetExStyle("-0x80000", hwnd)
    try WinSetAlwaysOnTop(false, hwnd)
    try DllCall("SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0, "UChar", 255, "UInt", 2)
    try WinSetTransparent("Off", hwnd)
    try WinRedraw(hwnd)
}

SetAlpha(hwnd, a) {
    try {
        DllCall("SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0, "UChar", a, "UInt", 2)
        WinRedraw(hwnd)
    }
}

;==================================================================
;  看门狗模式（由主进程自动拉起，别手动开）
;==================================================================
WatchdogMode() {
    A_IconHidden := true          ; 看门狗不占托盘，只留主进程一个图标
    Log("看门狗启动")
    SetTimer(WatchdogCheck, 1000)
}

WatchdogCheck(*) {
    global HeartFile, IniFile
    ; 每轮重读配置，主进程改了立刻跟上
    exe := IniRead(IniFile, "target", "top_exe", "")

    stuck := 0
    if (exe != "") {
        for hwnd in WinGetList("ahk_exe " exe) {
            try {
                if (WinGetExStyle(hwnd) & 0x20) {
                    stuck := hwnd
                    break
                }
            }
        }
    }

    if stuck {
        if IsMainAlive()
            return
        n := 0
        for hwnd in WinGetList("ahk_exe " exe) {
            try {
                if (WinGetExStyle(hwnd) & 0x20) {
                    ClearClickThrough(hwnd)
                    n++
                }
            }
        }
        Log("看门狗救援 · 主进程失联，已解锁 " n " 个窗口")
        try FileDelete(HeartFile)
        ExitApp()
    }

    ; 没有粘住的窗口，且主进程已经结束 → 自己收工
    if !IsMainAlive() {
        Log("看门狗退出 · 主进程已结束")
        ExitApp()
    }
}

IsMainAlive() {
    global HeartFile
    if !FileExist(HeartFile)
        return false
    try {
        age := DateDiff(A_Now, FileGetTime(HeartFile, "M"), "Seconds")
        return age < 5
    }
    return false
}

;==================================================================
;  一次性解锁模式（兜底）
;==================================================================
UnlockMode() {
    log := ""
    n := 0
    for hwnd in WinGetList() {
        try {
            ex := WinGetExStyle(hwnd)
            ; 只处理"确实被本程序锁过"的窗口：LAYERED + TRANSPARENT + NOACTIVATE 三个齐全，
            ; 免得把别的程序自己的透明浮层（比如各种游戏内覆盖层）也顺手改掉。
            if (ex & 0x80000) && (ex & 0x20) && (ex & 0x8000000) {
                ClearClickThrough(hwnd)
                log .= Format("解锁  hwnd=0x{:X}  旧样式={:#010x}  标题={}`n", hwnd, ex, WinGetTitle(hwnd))
                n++
            }
        }
    }
    if (n = 0)
        log := "没有发现处于穿透状态的窗口，无需处理。`n"
    else
        log .= "`n共解锁 " n " 个窗口。`n"

    try {
        f := FileOpen(A_ScriptDir "\unlock-log.txt", "w", "UTF-8")
        f.Write(log)
        f.Close()
    }
    MsgBox(log, "解锁结果", "Iconi T8")
    ExitApp()
}

;==================================================================
;  单独打开设置窗口（--settings，也方便装完直接调设置）
;==================================================================
SettingsMode() {
    global SettingsGui
    OpenSettings()
    SetTimer(WatchSettingsClosed, 400)
}

WatchSettingsClosed(*) {
    global SettingsGui
    if (!SettingsGui)
        ExitApp()
}

;==================================================================
;  检查更新
;==================================================================
CheckUpdate(manual := true) {
    global AppVer, RepoSlug, RepoWeb, Updating, APPNAME

    if Updating
        return

    json := ""
    try {
        json := HttpGet("https://api.github.com/repos/" RepoSlug "/releases/latest")
    } catch as e {
        Log("检查更新失败: " e.Message)
        if manual
            MsgBox("检查更新失败：`n" e.Message "`n`n也可能是网络不通或 GitHub 被墙。", APPNAME, "Icon! T8")
        return
    }

    rel := ParseRelease(json)
    if !rel {
        if manual
            MsgBox("没能从 GitHub 的返回里读到版本信息。", APPNAME, "Iconi T6")
        return
    }

    latest := RegExReplace(rel.tag, "^[vV]")
    Log("检查更新 · 线上=" latest " 本地=" AppVer)

    if !IsNewer(latest, AppVer) {
        if manual
            MsgBox("已经是最新版本：" AppVer,  "检查更新", "Iconi T5")
        return
    }

    msg := "发现新版本 " latest "（当前 " AppVer "）"
    if (rel.body != "")
        msg .= "`n`n" SubStr(rel.body, 1, 700)
    msg .= "`n`n现在下载并安装？程序会自动退出，装完再自己启动。"

    r := MsgBox(msg, "检查更新", "Iconi YesNo Default1 T60")
    if (r != "Yes")
        return

    if (rel.url = "") {
        MsgBox("这个版本没找到安装包（ClickThrough-Setup.exe），请到 release 页手动下载：`n" RepoWeb, APPNAME, "Icon! T12")
        return
    }

    dest := A_Temp "\ClickThrough-Setup.exe"
    Tip("正在下载 " latest " …")
    if !Download(rel.url, dest) {
        MsgBox("下载失败了，请到 release 页手动下载：`n" RepoWeb, APPNAME, "Icon! T12")
        return
    }
    if (FileGetSize(dest) < 100000) {
        MsgBox("下载到的文件不完整，已放弃自动升级。`n请到 release 页手动下载。", APPNAME, "Icon! T12")
        return
    }

    Log("下载完成 · 交给安装器升级: " dest)
    Updating := true
    try Run('"' dest '" /S /UPDATE')
    catch as e {
        Updating := false
        MsgBox("启动安装器失败：`n" e.Message, APPNAME, "Icon! T10")
        return
    }
    ExitApp()
}

ParseRelease(json) {
    if !RegExMatch(json, '"tag_name"\s*:\s*"([^"]+)"', &t)
        return 0
    url := ""
    if RegExMatch(json, '"browser_download_url"\s*:\s*"([^"]*ClickThrough-Setup\.exe)"', &u)
        url := u[1]
    body := ""
    if RegExMatch(json, '"body"\s*:\s*"((?:[^"\\]|\\.)*)"', &b)
        body := JsonUnescape(b[1])
    return { tag: t[1], url: url, body: body }
}

JsonUnescape(s) {
    s := StrReplace(s, '\r\n', "`n")
    s := StrReplace(s, '\n', "`n")
    s := StrReplace(s, '\r', "`r")
    s := StrReplace(s, '\t', "`t")
    s := StrReplace(s, '\"', '"')
    s := StrReplace(s, '\/', "/")
    s := StrReplace(s, '\\', "\")
    return s
}

HttpGet(url) {
    global AppVer
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.Open("GET", url, false)
    req.SetRequestHeader("User-Agent", "ClickThrough/" AppVer)
    req.SetRequestHeader("Accept", "application/vnd.github+json")
    req.Send()
    if (req.Status != 200)
        throw Error("HTTP " req.Status)
    return req.ResponseText
}

Download(url, dest) {
    try FileDelete(dest)
    r := DllCall("urlmon\URLDownloadToFileW", "Ptr", 0, "WStr", url, "WStr", dest, "UInt", 0, "Ptr", 0, "UInt")
    return (r = 0 && FileExist(dest))
}

VerNum(s) {
    if !RegExMatch(s, "^\d+(?:\.\d+)*", &m)
        return [0]
    return StrSplit(m[0], ".")
}

IsNewer(a, b) {
    pa := VerNum(a)
    pb := VerNum(b)
    loop 3 {
        x := (A_Index <= pa.Length) ? Integer(pa[A_Index]) : 0
        y := (A_Index <= pb.Length) ? Integer(pb[A_Index]) : 0
        if (x > y)
            return true
        if (x < y)
            return false
    }
    return false
}

;==================================================================
;  杂项
;==================================================================
Heartbeat() {
    global HeartFile
    try {
        f := FileOpen(HeartFile, "w")
        f.Write(A_Now)
        f.Close()
    }
}

Log(msg) {
    global LogFile
    try {
        f := FileOpen(LogFile, "a", "UTF-8")
        f.Write(FormatTime(A_Now, "HH:mm:ss") "  " msg "`n")
        f.Close()
    }
}

Tip(msg) {
    ToolTip(msg)
    SetTimer(() => ToolTip(), -1800)
}

OnExitHandler(reason, code) {
    global WatchdogPid, HeartFile
    n := CleanupAll()
    Log("退出(" reason ") · 解锁 " n " 个窗口")
    try FileDelete(HeartFile)
    if (WatchdogPid && ProcessExist(WatchdogPid))
        try ProcessClose(WatchdogPid)
}
