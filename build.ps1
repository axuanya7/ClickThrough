#Requires -Version 5.1
<#
.SYNOPSIS
    构建 ClickThrough：主程序 + 卸载器 + 单文件安装包。

.DESCRIPTION
    产物：
        dist\ClickThrough.exe          主程序（便携版，直接双击可用）
        dist\ClickThrough-Setup.exe    安装包（自带卸载器，安装到 %LOCALAPPDATA%\Programs\ClickThrough）

    依赖 AutoHotkey v2 与 Ahk2Exe。用 -AhkRoot 指定 AutoHotkey 安装目录，
    该目录下应有 v2\AutoHotkey64.exe 和 Compiler\Ahk2Exe.exe。
    不给 -AhkRoot 时会尝试从注册表和常见位置自动探测。

.EXAMPLE
    .\build.ps1 -AhkRoot "C:\Program Files\AutoHotkey"

.EXAMPLE
    .\build.ps1 -AhkRoot "D:\Tools\AutoHotkey" -Version 1.2.0
#>
[CmdletBinding()]
param(
    [string]$AhkRoot,
    [string]$Version,
    [switch]$NoSetup,
    [switch]$KeepBuild
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
Set-Location $Root

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

#--------------------------------------------------------------- 版本号
$VersionFile = Join-Path $Root 'version.txt'
if (-not $Version) {
    if (Test-Path $VersionFile) {
        $Version = (Get-Content $VersionFile -Raw).Trim()
    }
    else {
        $Version = '1.0.0'
    }
}
if ($Version -notmatch '^\d+\.\d+\.\d+') {
    throw "版本号格式不对：$Version（应为 1.2.3 这种）"
}
Write-Step "版本 $Version"

#--------------------------------------------------------------- 找工具链
function Resolve-AhkChain {
    param([string]$RootPath)

    $roots = @()
    if ($RootPath) { $roots += $RootPath }

    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($rp in $regPaths) {
        try {
            Get-ItemProperty $rp -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like 'AutoHotkey*' -and $_.InstallLocation } |
                ForEach-Object { $roots += $_.InstallLocation }
        }
        catch { }
    }

    $cmd = Get-Command 'AutoHotkey64.exe' -ErrorAction SilentlyContinue
    if ($cmd) { $roots += (Split-Path $cmd.Source -Parent) }
    $roots += @('C:\Program Files\AutoHotkey', 'C:\Program Files (x86)\AutoHotkey')

    foreach ($r in $roots) {
        if (-not $r) { continue }
        $base = @(
            (Join-Path $r 'v2\AutoHotkey64.exe'),
            (Join-Path $r 'AutoHotkey64.exe')
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
        $compiler = (Join-Path $r 'Compiler\Ahk2Exe.exe')
        if ($base -and (Test-Path $compiler)) {
            return [pscustomobject]@{ Base = $base; Compiler = $compiler; Root = $r }
        }
    }
    return $null
}

$chain = Resolve-AhkChain -RootPath $AhkRoot
if (-not $chain) {
    throw @"
没找到 AutoHotkey v2 + Ahk2Exe。需要：
  <AutoHotkey 目录>\v2\AutoHotkey64.exe
  <AutoHotkey 目录>\Compiler\Ahk2Exe.exe
用 -AhkRoot 指过去，例如： .\build.ps1 -AhkRoot "C:\Program Files\AutoHotkey"
Ahk2Exe 单独下载： https://github.com/AutoHotkey/Ahk2Exe/releases
"@
}
$BaseExe = $chain.Base
$Compiler = $chain.Compiler
Write-Step "AutoHotkey  $BaseExe"
Write-Step "Ahk2Exe     $Compiler"

#--------------------------------------------------------------- 目录
$SrcDir = Join-Path $Root 'src'
$AssetDir = Join-Path $Root 'assets'
$BuildDir = Join-Path $Root 'build'
$DistDir = Join-Path $Root 'dist'
$PayloadDir = Join-Path $BuildDir 'payload'

if (-not $KeepBuild -and (Test-Path $BuildDir)) {
    Remove-Item $BuildDir -Recurse -Force
}
foreach ($d in @($BuildDir, $DistDir, $PayloadDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}

$Icon = Join-Path $AssetDir 'icon.ico'
if (-not (Test-Path $Icon)) { $Icon = $null }

#--------------------------------------------------------------- 工具函数
function New-BuildCopy {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path $Source)) { throw "缺少源文件：$Source" }
    $text = [System.IO.File]::ReadAllText($Source, [System.Text.UTF8Encoding]::new($false))
    $text = $text.Replace('@@VERSION@@', $Version)
    [System.IO.File]::WriteAllText($Destination, $text, [System.Text.UTF8Encoding]::new($true))
    return $Destination
}

function Invoke-Compile {
    param([string]$In, [string]$Out, [string]$IconPath)

    if (Test-Path $Out) { Remove-Item $Out -Force }
    $argv = @('/in', $In, '/out', $Out, '/base', $BaseExe)
    if ($IconPath) { $argv += @('/icon', $IconPath) }
    $argv += '/silent'

    & $Compiler @argv | Out-Null
    if (-not (Test-Path $Out)) { throw "编译失败：$Out" }
    $size = (Get-Item $Out).Length
    Write-Host ("    -> {0}  ({1:N0} KB)" -f (Split-Path $Out -Leaf), ($size / 1KB)) -ForegroundColor DarkGray
}

#--------------------------------------------------------------- 1. 主程序
Write-Step '编译主程序'
$mainBuild = New-BuildCopy -Source (Join-Path $SrcDir 'ClickThrough.ahk') -Destination (Join-Path $BuildDir 'ClickThrough.build.ahk')
Invoke-Compile -In $mainBuild -Out (Join-Path $DistDir 'ClickThrough.exe') -IconPath $Icon

if ($NoSetup) {
    Write-Step '跳过安装包（-NoSetup）'
    return
}

#--------------------------------------------------------------- 2. 卸载器
Write-Step '编译卸载器'
$uninstBuild = New-BuildCopy -Source (Join-Path $SrcDir 'ClickThrough-Uninstall.ahk') -Destination (Join-Path $BuildDir 'Uninstall.build.ahk')
Invoke-Compile -In $uninstBuild -Out (Join-Path $PayloadDir 'Uninstall.exe') -IconPath $Icon

#--------------------------------------------------------------- 3. 安装包
Write-Step '编译安装包'
Copy-Item (Join-Path $DistDir 'ClickThrough.exe') (Join-Path $PayloadDir 'ClickThrough.exe') -Force
$setupBuild = New-BuildCopy -Source (Join-Path $SrcDir 'ClickThrough-Setup.ahk') -Destination (Join-Path $BuildDir 'ClickThrough-Setup.build.ahk')
Invoke-Compile -In $setupBuild -Out (Join-Path $DistDir 'ClickThrough-Setup.exe') -IconPath $Icon

Write-Step '完成'
Get-ChildItem $DistDir | Sort-Object Name | Format-Table Name, @{N = 'Size'; E = { '{0:N0} KB' -f ($_.Length / 1KB) } } -AutoSize
Write-Host ''
Write-Host "版本 $Version · 打 tag: git tag v$Version" -ForegroundColor Green
