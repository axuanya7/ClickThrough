#Requires AutoHotkey v2.0
#SingleInstance Force
;==================================================================
;  ClickThrough 安装程序
;  https://github.com/axuanya7/ClickThrough   ·   MIT License
;
;  单文件安装包：主程序和卸载器用 FileInstall 嵌在自己里面。
;  安装到 %LOCALAPPDATA%\Programs\ClickThrough，不需要管理员权限。
;
;  参数：
;    /S 或 /SILENT        静默安装，不显示界面
;    /UPDATE              升级模式：等旧进程退出后覆盖，装完自动启动
;    /NODESKTOP           不创建桌面快捷方式
;    /NOLAUNCH            装完不自动运行
;    /DIR=<路径>          自定义安装目录（调试用）
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
InstallDir := (customDir != "") ? customDir : LocalAppData "\Programs\" APPNAME
ExePath    := InstallDir "\" APPNAME ".exe"
UninstPath := InstallDir "\Uninstall.exe"
UninstKey  := "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\" APPNAME
RunKey     := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"

if updateMode {
    makeDesk := false                       ; 升级时不动快捷方式
    makeAuto := false
}

if (silent || updateMode) {
    DoInstall()
    ExitApp()
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
    g.Add("Text", "x110 y88 w430 cGray", InstallDir)

    cbDesk := g.Add("CheckBox", "x20 y122 w420 Checked", "创建桌面快捷方式")
    cbAuto := g.Add("CheckBox", "x20 y148 w420", "开机自动启动")
    cbRun  := g.Add("CheckBox", "x20 y174 w420 Checked", "安装完成后立即运行")

    g.SetFont("s9", "Microsoft YaHei UI")
    g.Add("Text", "x20 y208 w520 cGray", "不需要管理员权限。卸载走「设置 → 应用」里的 " APPNAME "，或安装目录里的 Uninstall.exe。")

    bOK     := g.Add("Button", "x300 y244 w110 Default", "安装")
    bCancel := g.Add("Button", "x420 y244 w110", "取消")

    bOK.OnEvent("Click", (*) => InstallFromGui(cbDesk.Value, cbAuto.Value, cbRun.Value))
    bCancel.OnEvent("Click", (*) => ExitApp())
    g.OnEvent("Close", (*) => ExitApp())
    g.OnEvent("Escape", (*) => ExitApp())
    g.Show("w560 h290")
}

installDone := false

InstallFromGui(desk, auto, run) {
    global makeDesk, makeAuto, runAfter, installDone, APPNAME, InstallDir
    if installDone
        return
    installDone := true
    makeDesk := desk
    makeAuto := auto
    runAfter := run
    if DoInstall() {
        MsgBox(APPNAME " 已安装。`n`n安装位置：" InstallDir "`n`n用法：右键托盘图标 → 系统设置；或按 Ctrl+Alt+2 选要浮在上面的窗口，Ctrl+Alt+D 锁定。", "安装完成", "Iconi T15")
        ExitApp()
    }
}

;==================================================================
DoInstall() {
    global APPNAME, AppVer, InstallDir, ExePath, UninstPath, UninstKey, RunKey, RepoWeb
    global updateMode, makeDesk, makeAuto, runAfter

    ;--- 1. 处理正在运行的实例 ---
    if ProcessExist(APPNAME ".exe") {
        if updateMode {
            waited := 0
            while (ProcessExist(APPNAME ".exe") && waited < 25000) {
                Sleep(300)
                waited += 300
            }
            if ProcessExist(APPNAME ".exe") {
                try ProcessClose(APPNAME ".exe")
                Sleep(600)
            }
        } else {
            try ProcessClose(APPNAME ".exe")
            Sleep(600)
        }
    }

    ;--- 2. 建目录、放文件 ---
    if !DirExist(InstallDir) {
        try DirCreate(InstallDir)
        catch as e {
            MsgBox("创建安装目录失败：`n" e.Message, APPNAME " 安装程序", "Icon! T12")
            return false
        }
    }

    try {
        FileInstall("payload\ClickThrough.exe", ExePath, 1)
        FileInstall("payload\Uninstall.exe", UninstPath, 1)
    } catch as e {
        MsgBox("复制文件失败：`n" e.Message, APPNAME " 安装程序", "Icon! T12")
        return false
    }

    ;--- 3. 快捷方式 ---
    MakeShortcut(A_StartMenu "\Programs\" APPNAME ".lnk", ExePath, InstallDir)
    if makeDesk
        MakeShortcut(A_Desktop "\" APPNAME ".lnk", ExePath, InstallDir)
    else if !updateMode
        try FileDelete(A_Desktop "\" APPNAME ".lnk")

    ;--- 4. 系统「应用和功能」里的卸载项 ---
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
    }

    ;--- 5. 开机自启 ---
    if (makeAuto && !updateMode) {
        try RegWrite('"' ExePath '"', "REG_SZ", RunKey, APPNAME)
    }

    ;--- 6. 装完直接跑起来 ---
    if (runAfter && FileExist(ExePath)) {
        try Run('"' ExePath '"')
    }

    return true
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
    }
}
