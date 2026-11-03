#Requires AutoHotkey v2.0
#SingleInstance Ignore
;==================================================================
;  ClickThrough 卸载程序
;  https://github.com/axuanya7/ClickThrough   ·   MIT License
;
;  由安装器复制到安装目录，系统「应用和功能」里的卸载项指向这里。
;  参数：/S 静默卸载，不弹确认框。
;
;  【安全底线】只删本程序自己装进去的那几个文件，其它一律不碰。
;  万一安装目录是用户自己挑的、里面还有别的东西，绝不能整个目录清空。
;==================================================================

APPNAME := "ClickThrough"
AppVer  := "@@VERSION@@"
RepoWeb := "https://github.com/axuanya7/ClickThrough"
if InStr(AppVer, "@@")
    AppVer := "0.0.0-dev"

InstallDir := A_ScriptDir

; 本程序会在安装目录里放这些东西，只有这些可以被删
OwnFiles := [
    "ClickThrough.exe",
    "Uninstall.exe",
    "overlay-config.ini",
    "overlay-log.txt",
    "overlay-heartbeat.txt",
    "unlock-log.txt",
    "README.md"
]

silent := false
for a in A_Args {
    if (a = "/S" || a = "/SILENT")
        silent := true
}

; AHK 自带的 MsgBox 没法自己置顶，会被别的置顶窗口压住看不见。
; 弹之前挂个定时器，框一出来就把它顶到最前（实测 MsgBox 期间定时器照常跑）。
MsgTop(text, title, opts := "") {
    SetTimer(PinDialog, 60)
    r := MsgBox(text, title, opts)
    SetTimer(PinDialog, 0)
    return r
}

PinDialog(*) {
    h := WinExist("ahk_class #32770 ahk_pid " ProcessExist())
    if h
        try WinSetAlwaysOnTop(true, h)
}

if !silent {
    r := MsgTop("确定卸载 " APPNAME " " AppVer " ？`n`n将删除：`n  " InstallDir " 里的 ClickThrough.exe、Uninstall.exe 和配置文件`n  开始菜单 / 桌面快捷方式`n  开机自启项`n`n该目录里其它文件不会被删除。", "卸载 " APPNAME, "Icon? YesNo Default2 T30")
    if (r != "Yes")
        ExitApp()
}

;--- 1. 关掉正在运行的实例 ---
loop 20 {
    if !ProcessExist(APPNAME ".exe")
        break
    try ProcessClose(APPNAME ".exe")
    Sleep(300)
}

;--- 2. 快捷方式 ---
for f in [
    A_StartMenu "\Programs\" APPNAME ".lnk",
    A_Desktop "\" APPNAME ".lnk"
]
    try FileDelete(f)

;--- 3. 注册表：自启（删值）+ 卸载项（删整键）---
try RegDelete("HKCU\Software\Microsoft\Windows\CurrentVersion\Run", APPNAME)
; 注意：AHK v2 的 RegDelete 省略 ValueName 时并不会删掉整个子键（实测抛 error 2），
; 所以这里直接走 advapi32。HKEY_CURRENT_USER = 0x80000001。
try DllCall("advapi32\RegDeleteTreeW", "Ptr", 0x80000001
    , "WStr", "Software\Microsoft\Windows\CurrentVersion\Uninstall\" APPNAME, "UInt")

;--- 4. 只删自己的文件（跳过正在运行的自己） ---
for name in OwnFiles {
    if (name = A_ScriptName)          ; 自己留到最后交给 cmd 删
        continue
    f := InstallDir "\" name
    if FileExist(f)
        try FileDelete(f)
}

;--- 5. 目录是空的才删，非空说明里面还有用户自己的东西，保留 ---
remaining := 0
if DirExist(InstallDir) {
    loop files, InstallDir "\*", "FD"
        remaining++
}
dirKept := (remaining > 0)

;--- 6. 删掉自己：写一个临时 ps1，等本进程退出后再删自己，最后只在目录空了才移除目录 ---
; 直接用 cmd 延时删在交互模式下会失败（弹窗期间进程还活着，文件被占用），所以让脚本等进程消失。
PsQuote(s) {
    return "'" StrReplace(s, "'", "''") "'"
}

selfPid := ProcessExist()
tmpPs := A_Temp "\ClickThrough-uninstall-" selfPid ".ps1"
try {
    body := ""
    body .= 'while (Get-Process -Id ' selfPid ' -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 200 }' "`r`n"
    body .= 'Start-Sleep -Milliseconds 300' "`r`n"
    body .= "Remove-Item -LiteralPath " PsQuote(A_ScriptFullPath) " -Force -ErrorAction SilentlyContinue" "`r`n"
    body .= "if ((Get-ChildItem -LiteralPath " PsQuote(InstallDir) " -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) { Remove-Item -LiteralPath " PsQuote(InstallDir) " -Force -ErrorAction SilentlyContinue }" "`r`n"
    body .= "Remove-Item -LiteralPath " PsQuote(tmpPs) " -Force -ErrorAction SilentlyContinue" "`r`n"
    f := FileOpen(tmpPs, "w", "UTF-8")
    f.Write(body)
    f.Close()
    Run('powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' tmpPs '"', A_Temp, "Hide")
} catch as e {
    ; 兜底：只删自己，绝不动目录
    try Run('cmd.exe /c ping -n 4 127.0.0.1 >nul & del /f /q "' A_ScriptFullPath '"', A_Temp, "Hide")
}

if !silent {
    msg := APPNAME " 已卸载。"
    if !dirKept
        msg .= "`n`n安装目录里还有其它文件，已原样保留：`n" InstallDir
    msg .= "`n`n想重新用的话，到 release 页重新下载：`n" RepoWeb
    MsgTop(msg, "卸载完成", "Iconi T15")
}

ExitApp()
