#Requires AutoHotkey v2.0
#SingleInstance Ignore
;==================================================================
;  ClickThrough 卸载程序
;  https://github.com/axuanya7/ClickThrough   ·   MIT License
;
;  由安装器复制到安装目录，系统「应用和功能」里的卸载项指向这里。
;  参数：/S 静默卸载，不弹确认框。
;==================================================================

APPNAME := "ClickThrough"
AppVer  := "@@VERSION@@"
RepoWeb := "https://github.com/axuanya7/ClickThrough"
if InStr(AppVer, "@@")
    AppVer := "0.0.0-dev"

InstallDir := A_ScriptDir

silent := false
for a in A_Args {
    if (a = "/S" || a = "/SILENT")
        silent := true
}

if !silent {
    r := MsgBox("确定卸载 " APPNAME " " AppVer " ？`n`n将删除：`n  " InstallDir "`n  开始菜单 / 桌面快捷方式`n  开机自启项`n  配置文件和日志`n`n如果程序正在运行，会先关掉它。", "卸载 " APPNAME, "Icon? YesNo Default2 T30")
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

;--- 4. 删文件，最后把自己和目录交给 cmd 延时清掉 ---
loop files, InstallDir "\*.*", "FD" {
    if (A_LoopFileName = A_ScriptName)
        continue
    try {
        if InStr(A_LoopFileAttrib, "D")
            DirDelete(A_LoopFileFullPath, true)
        else
            FileDelete(A_LoopFileFullPath)
    }
}

cmd := 'cmd.exe /c ping -n 3 127.0.0.1 >nul & del /f /q "' A_ScriptFullPath '" & rd /s /q "' InstallDir '"'
try Run(cmd, A_Temp, "Hide")

if !silent
    MsgBox(APPNAME " 已卸载。`n`n想重新用的话，到 release 页重新下载安装包：`n" RepoWeb, "卸载完成", "Iconi T15")

ExitApp()
