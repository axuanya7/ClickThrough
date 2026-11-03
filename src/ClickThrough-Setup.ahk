#Requires AutoHotkey v2.0
#SingleInstance Force
;==================================================================
;  ClickThrough 安装程序
;  https://github.com/axuanya7/ClickThrough   ·   MIT License
;
;  单文件安装包：主程序和卸载器用 FileInstall 嵌在自己里面。
;  默认装到 %LOCALAPPDATA%\Programs\ClickThrough，安装界面里可以改成别的目录，不需要管理员权限。
;
;  参数：
;    /S 或 /SILENT        静默安装，不显示界面
;    /UPDATE              升级模式：等旧进程退出后覆盖，装完自动启动
;    /NODESKTOP           不创建桌面快捷方式
;    /NOLAUNCH            装完不自动运行
;    /DIR=<路径>          自定义安装目录（调试用）
;
;  排查用日志：%TEMP%\ClickThrough-Setup.log
;==================================================================

APPNAME := "ClickThrough"
AppVer  := "@@VERSION@@"
RepoWeb := "https://github.com/axuanya7/ClickThrough"
if InStr(AppVer, "@@")
    AppVer := "0.0.0-dev"

silent     := false
updateMode := false
customDir  := ""
makeDesk   := true
makeAuto   := false
runAfter   := true

for a in A_Args {
    if (a = "/S" || a = "/SILENT")
        silent := true
    else if (a = "/UPDATE")
        updateMode := true
    else if (a = "/NODESKTOP")
        makeDesk := false
    else if (a = "/NOLAUNCH")
        runAfter := false
    else if (SubStr(a, 1, 5) = "/DIR=")
        customDir := SubStr(a, 6)
}
customDir := Trim(customDir, '"')

LocalAppData := EnvGet("LOCALAPPDATA")
InstallDir  := (customDir != "") ? customDir : LocalAppData "\Programs\" APPNAME
ExePath     := InstallDir "\" APPNAME ".exe"
UninstPath  := InstallDir "\Uninstall.exe"
UninstKey   := "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\" APPNAME
RunKey      := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"

if updateMode {
    makeDesk := false                       ; 升级时不动快捷方式
    makeAuto := false
}

SetupLog("=== 启动 v" AppVer "  args=" (A_Args.Length ? ArrayJoin(A_Args) : "(无)") "  silent=" silent "  update=" updateMode)
SetupLog("安装目录: " InstallDir)

if (silent || updateMode) {
    ok := DoInstall()
    SetupLog("DoInstall 返回 " ok)
    ExitApp(ok ? 0 : 1)
}

ShowGui()

;==================================================================
ShowGui() {
    global APPNAME, AppVer, InstallDir

    g := Gui("+AlwaysOnTop -MaximizeBox", APPNAME " 安装程序")
    g.SetFont("s12 Bold", "Microsoft YaHei UI")
    g.MarginX := 20
    g.MarginY := 16
    g.Add("Text", "x20 y16 w520", APPNAME "  " AppVer)

    g.SetFont("s9", "Microsoft YaHei UI")
    g.Add("Text", "x20 y46 w520 cGray", "把任意窗口浮在游戏画面之上，正常显示、正常播放，鼠标点击完全穿透到下层窗口，全程不抢焦点。")

    g.SetFont("s10", "Microsoft YaHei UI")
    g.Add("Text", "x20 y88 w90", "安装位置：")
    edDir := g.Add("Edit", "x110 y86 w420", InstallDir)
    btnBrowse := g.Add("Button", "x538 y85 w62", "浏览…")

    cbDesk := g.Add("CheckBox", "x20 y122 w460 Checked", "创建桌面快捷方式")
    cbAuto := g.Add("CheckBox", "x20 y148 w460", "开机自动启动")
    cbRun  := g.Add("CheckBox", "x20 y174 w460 Checked", "安装完成后立即运行")

    g.SetFont("s9", "Microsoft YaHei UI")
    g.Add("Text", "x20 y208 w580 cGray", "不需要管理员权限。卸载走「设置 → 应用」里的 " APPNAME "，或安装目录里的 Uninstall.exe。")

    bOK     := g.Add("Button", "x368 y244 w110 Default", "安装")
    bCancel := g.Add("Button", "x488 y244 w110", "取消")

    btnBrowse.OnEvent("Click", (*) => BrowseDir(edDir, g))
    bOK.OnEvent("Click", (*) => InstallFromGui(cbDesk.Value, cbAuto.Value, cbRun.Value, edDir.Value))
    bCancel.OnEvent("Click", (*) => ExitApp())
    g.OnEvent("Close", (*) => ExitApp())
    g.OnEvent("Escape", (*) => ExitApp())
    g.Show("w620 h290")
}

; 挑安装目录。选完只回填到输入框，真正生效是在点「安装」之后。
BrowseDir(edCtrl, ownerGui) {
    start := Trim(edCtrl.Value)
    if !DirExist(start) {
        SplitPath(start, , &parent)
        start := (parent != "" && DirExist(parent)) ? parent : ""
    }
    ; 安装窗口是置顶的，不临时撤掉置顶，系统的文件夹选择器会被压在它后面
    try ownerGui.Opt("-AlwaysOnTop")
    picked := ""
    try picked := DirSelect(start, 0, "选择安装位置")
    catch as e
        SetupLog("DirSelect 失败: " e.Message)
    try ownerGui.Opt("+AlwaysOnTop")
    if (picked != "")
        edCtrl.Value := picked
}

installDone := false

InstallFromGui(desk, auto, run, dir) {
    global makeDesk, makeAuto, runAfter, installDone, APPNAME, InstallDir, ExePath, UninstPath

    if installDone
        return

    dir := Trim(dir)
    if (dir = "") {
        MsgBox("先填一个安装位置。", APPNAME " 安装程序", "Iconi T5")
        return
    }
    if !RegExMatch(dir, "^(?:[A-Za-z]:[\\/]|\\\\)") {
        MsgBox("安装位置要填完整路径，比如：`nC:\Tools\ClickThrough`n`n也可以点右边的「浏览…」直接选。", APPNAME " 安装程序", "Iconi T8")
        return
    }
    dir := RTrim(dir, "\/")
    if (dir = "") || (SubStr(dir, -1) = ":") {
        MsgBox("不能直接装到盘符根目录，挑一个文件夹。", APPNAME " 安装程序", "Iconi T8")
        return
    }

    installDone := true
    makeDesk := desk
    makeAuto := auto
    runAfter := run
    InstallDir := dir
    ExePath := InstallDir "\" APPNAME ".exe"
    UninstPath := InstallDir "\Uninstall.exe"
    SetupLog("界面指定安装目录: " InstallDir)

    if DoInstall() {
        MsgBox(APPNAME " 已安装。`n`n安装位置：" InstallDir "`n`n用法：右键托盘图标 → 系统设置；或按 Ctrl+Alt+2 选要浮在上面的窗口，Ctrl+Alt+D 锁定。", "安装完成", "Iconi T15")
        ExitApp(0)
    }
    installDone := false
}

;==================================================================
DoInstall() {
    global APPNAME, AppVer, InstallDir, ExePath, UninstPath, UninstKey, RunKey, RepoWeb
    global updateMode, silent, makeDesk, makeAuto, runAfter

    ;--- 1. 旧进程先退干净，否则文件写不进去 ---
    if ProcessExist(APPNAME ".exe") {
        SetupLog("检测到正在运行的实例")
        if !updateMode {
            r := MsgBox(APPNAME " 正在运行，安装程序需要先关掉它。`n`n继续安装？", APPNAME " 安装程序", "Icon? YesNo Default2 T30")
            if (r != "Yes") {
                SetupLog("用户取消（程序在运行）")
                return false
            }
        }
        ; 先礼后兵：等它自己退（升级模式下它可能正在退出）
        limit := updateMode ? 15000 : 4000
        waited := 0
        while (ProcessExist(APPNAME ".exe") && waited < limit) {
            Sleep(300)
            waited += 300
        }
        if ProcessExist(APPNAME ".exe") {
            SetupLog("等待超时，强制关闭（等了 " waited "ms）")
            try ProcessClose(APPNAME ".exe")
            waited := 0
            while (ProcessExist(APPNAME ".exe") && waited < 8000) {
                Sleep(200)
                waited += 200
            }
        }
        SetupLog("旧进程已退出，用时 " waited "ms")
    }

    ;--- 2. 建目录 ---
    if !DirExist(InstallDir) {
        try DirCreate(InstallDir)
        catch as e {
            SetupLog("建目录失败: " e.Message)
            MsgBox("创建安装目录失败：`n" e.Message, APPNAME " 安装程序", "Icon! T12")
            return false
        }
    }

    ;--- 3. 写文件（带重试：刚被强杀的进程可能还锁着 exe） ---
    if !WritePayload("main", ExePath) {
        SetupLog("写主程序失败: " ExePath)
        MsgBox("写入主程序失败，目标文件可能仍被占用：`n" ExePath "`n`n先退出 " APPNAME " 再试一次。", APPNAME " 安装程序", "Icon! T15")
        return false
    }
    if !WritePayload("uninstall", UninstPath) {
        SetupLog("写卸载器失败: " UninstPath)
        MsgBox("写入卸载器失败，目标文件可能仍被占用：`n" UninstPath, APPNAME " 安装程序", "Icon! T15")
        return false
    }
    SetupLog("文件已写入，主程序 " (FileExist(ExePath) ? FileGetSize(ExePath) : 0) " 字节")

    ;--- 4. 快捷方式 ---
    MakeShortcut(A_StartMenu "\Programs\" APPNAME ".lnk", ExePath, InstallDir)
    if makeDesk
        MakeShortcut(A_Desktop "\" APPNAME ".lnk", ExePath, InstallDir)
    else if !updateMode
        try FileDelete(A_Desktop "\" APPNAME ".lnk")
    SetupLog("快捷方式已处理（桌面=" makeDesk "）")

    ;--- 5. 系统「应用和功能」里的卸载项 ---
    try {
        RegWrite(APPNAME, "REG_SZ", UninstKey, "DisplayName")
        RegWrite("axuanya7", "REG_SZ", UninstKey, "Publisher")
        RegWrite(AppVer, "REG_SZ", UninstKey, "DisplayVersion")
        RegWrite(ExePath, "REG_SZ", UninstKey, "DisplayIcon")
        RegWrite(InstallDir, "REG_SZ", UninstKey, "InstallLocation")
        RegWrite(RepoWeb, "REG_SZ", UninstKey, "URLInfoAbout")
        RegWrite('"' UninstPath '"', "REG_SZ", UninstKey, "UninstallString")
        RegWrite('"' UninstPath '" /S', "REG_SZ", UninstKey, "QuietUninstallString")
        RegWrite(1, "REG_DWORD", UninstKey, "NoModify")
        RegWrite(1, "REG_DWORD", UninstKey, "NoRepair")
        if FileExist(ExePath)
            RegWrite(Round(FileGetSize(ExePath) / 1024), "REG_DWORD", UninstKey, "EstimatedSize")
        SetupLog("卸载项已写入注册表")
    } catch as e {
        SetupLog("写注册表失败: " e.Message)
    }

    ;--- 6. 开机自启 ---
    if (makeAuto && !updateMode) {
        try RegWrite('"' ExePath '"', "REG_SZ", RunKey, APPNAME)
        SetupLog("开机自启已开启")
    }

    ;--- 7. 装完直接跑起来 ---
    if (runAfter && FileExist(ExePath)) {
        try {
            Run('"' ExePath '"')
            SetupLog("已启动程序")
        } catch as e {
            SetupLog("启动失败: " e.Message)
        }
    }

    SetupLog("安装完成")
    return true
}

; 写入内嵌的 payload。写之前先删目标文件，删不掉就说明还被占用，等一会儿再试。
WritePayload(kind, dest, tries := 30) {
    loop tries {
        try FileDelete(dest)
        if FileExist(dest) {
            Sleep(500)
            continue
        }
        try {
            if (kind = "main")
                FileInstall("payload\ClickThrough.exe", dest, 1)
            else
                FileInstall("payload\Uninstall.exe", dest, 1)
        }
        if FileExist(dest)
            return true
        Sleep(500)
    }
    return false
}

MakeShortcut(lnkPath, target, workDir) {
    SplitPath(lnkPath, , &dir)
    if !DirExist(dir)
        try DirCreate(dir)
    try {
        sc := ComObject("WScript.Shell").CreateShortcut(lnkPath)
        sc.TargetPath := target
        sc.WorkingDirectory := workDir
        sc.IconLocation := target ",0"
        sc.Description := "ClickThrough —— 窗口穿透浮层"
        sc.Save()
    } catch as e {
        SetupLog("建快捷方式失败: " lnkPath " · " e.Message)
    }
}

ArrayJoin(arr) {
    s := ""
    for i, v in arr
        s .= (i > 1 ? " " : "") v
    return s
}

SetupLog(msg) {
    try {
        f := FileOpen(EnvGet("TEMP") "\ClickThrough-Setup.log", "a", "UTF-8")
        f.Write(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "  " msg "`n")
        f.Close()
    }
}
