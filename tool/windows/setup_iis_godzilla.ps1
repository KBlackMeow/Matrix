#Requires -Version 5.1
<#
.SYNOPSIS
  在本地 Windows 上启用 IIS，并部署 Matrix 的三个 Godzilla 服务端壳。

.DESCRIPTION
  适配 Windows 11 ARM64 / x64 与 Windows Server。脚本做五件事：
  1. 启用 IIS、ASP.NET 4.x、经典 ASP
  2. 创建独立应用池和站点（默认 8080）
  3. 把 payloads 目录里的 Godzilla 壳复制到站点根目录
  4. 配置目录权限和本机防火墙
  5. 逐个请求三个壳，打印 HTTP 状态和 Matrix 连接参数

  默认密码 mAtrix_911，secretKey key。

.PARAMETER Source
  Godzilla 壳所在目录。默认是脚本旁边的 payloads\；
  如果不存在，会尝试仓库相对路径 ..\..\assets\defaults\payloads\godzilla。

.PARAMETER Port
  IIS 站点端口，默认 8080。

.EXAMPLE
  # 右键“使用 PowerShell 运行”（管理员），或在管理员 Windows PowerShell 中：
  Set-ExecutionPolicy -Scope Process Bypass
  .\setup_iis_godzilla.ps1

.EXAMPLE
  .\setup_iis_godzilla.ps1 -Port 80 -Source D:\matrix\payloads
#>
[CmdletBinding()]
param(
    [int]$Port = 8080,
    [string]$SiteName = 'MatrixLab',
    [string]$AppPoolName = 'MatrixLab',
    [string]$SitePath = 'C:\matrix-lab\wwwroot',
    [string]$Source = '',
    [switch]$SkipFirewall
)

$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw '请以管理员身份运行 Windows PowerShell 5.1。'
    }
}

function Resolve-PayloadSource {
    if ($Source -and (Test-Path -LiteralPath $Source)) {
        return (Resolve-Path -LiteralPath $Source).Path
    }

    $candidates = @(
        (Join-Path $PSScriptRoot 'payloads'),
        (Join-Path $PSScriptRoot '..\..\assets\defaults\payloads\godzilla')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw @"
找不到 Godzilla 壳目录。
请把 Matrix 仓库里的 assets\defaults\payloads\godzilla 整个目录
复制到脚本旁边的 payloads\ 下，或用 -Source 指定目录。
当前查找过：
$($candidates -join "`n")
"@
}

function Enable-IisFeature {
    param([string]$Name)

    $feature = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction SilentlyContinue
    if ($null -eq $feature) {
        Write-Warning "当前系统没有功能 $Name，已跳过。"
        return $false
    }
    if ($feature.State -eq 'Enabled') {
        Write-Host "  [已启用] $Name"
        return $false
    }

    Write-Host "  [启用中] $Name"
    $result = Enable-WindowsOptionalFeature -Online -FeatureName $Name -All -NoRestart
    if ($result.RestartNeeded) {
        return $true
    }
    return $false
}

Assert-Administrator

if (-not (Get-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole -ErrorAction SilentlyContinue)) {
    throw '当前 Windows 版本没有 IIS。Windows 11 Home 不支持 IIS，请使用 Windows 10/11 Pro/Enterprise/Education。'
}

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw '请使用 Windows PowerShell 5.1（不是 PowerShell 7 / pwsh）运行，WebAdministration 模块只随 Windows PowerShell 提供。'
}

$payloadSource = Resolve-PayloadSource
Write-Host "Payload 目录: $payloadSource"

# ── 1. IIS 功能 ──────────────────────────────────────────────────────────────
Write-Host "`n[1/5] 启用 IIS / ASP.NET / 经典 ASP"
$features = @(
    'IIS-WebServerRole',
    'IIS-WebServer',
    'IIS-CommonHttpFeatures',
    'IIS-StaticContent',
    'IIS-DefaultDocument',
    'IIS-HttpErrors',
    'IIS-HttpLogging',
    'IIS-RequestFiltering',
    'IIS-ApplicationDevelopment',
    'IIS-ASPNET45',
    'IIS-NetFxExtensibility45',
    'IIS-ISAPIExtensions',
    'IIS-ISAPIFilter',
    'IIS-ClassicAsp',
    'IIS-ASP',
    'IIS-ManagementConsole'
)

$restartNeeded = $false
foreach ($featureName in $features) {
    if (Enable-IisFeature -Name $featureName) {
        $restartNeeded = $true
    }
}

if ($restartNeeded) {
    Write-Host "`nIIS 功能已启用，但需要重启 Windows 后才会完全生效。" -ForegroundColor Yellow
    Write-Host "请重启后再次运行本脚本，脚本会自动继续创建站点。" -ForegroundColor Yellow
    exit 3010
}

Import-Module WebAdministration -ErrorAction Stop
Set-Service -Name W3SVC -StartupType Automatic
Start-Service -Name W3SVC

# ── 2. 站点目录和应用池 ──────────────────────────────────────────────────────
Write-Host "`n[2/5] 准备站点目录和应用池"
New-Item -ItemType Directory -Path $SitePath -Force | Out-Null

if (Test-Path "IIS:\Sites\$SiteName") {
    Write-Host "  移除旧站点 $SiteName"
    Remove-Website -Name $SiteName
}
if (Test-Path "IIS:\AppPools\$AppPoolName") {
    Write-Host "  移除旧应用池 $AppPoolName"
    Remove-WebAppPool -Name $AppPoolName
}

New-WebAppPool -Name $AppPoolName | Out-Null
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name managedRuntimeVersion -Value 'v4.0'
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name managedPipelineMode -Value 'Integrated'
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name enable32BitAppOnWin64 -Value $false

New-Website -Name $SiteName -Port $Port -PhysicalPath $SitePath -ApplicationPool $AppPoolName | Out-Null
Write-Host "  站点: http://localhost:$Port/"
Write-Host "  目录: $SitePath"

# ── 3. 复制壳 ────────────────────────────────────────────────────────────────
Write-Host "`n[3/5] 复制 Godzilla 壳"
$shells = @(
    'godzilla_aspx_aes_base64.aspx',
    'godzilla_aspx_aes_raw.aspx',
    'godzilla_csharp_asmx_aes_base64.asmx',
    'godzilla_csharp_eval_aes_base64.aspx',
    'godzilla_asp_base64.asp',
    'godzilla_asp_raw.asp',
    'godzilla_asp_xor_base64.asp',
    'godzilla_asp_xor_raw.asp',
    'godzilla_asp_eval_base64.asp'
)
foreach ($shell in $shells) {
    $sourceFile = Join-Path $payloadSource $shell
    if (-not (Test-Path -LiteralPath $sourceFile)) {
        Write-Warning "缺少 $shell（$sourceFile）"
        continue
    }
    Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $SitePath $shell) -Force
    Write-Host "  [OK] $shell"
}

# eval 壳会把代码放在 POST 参数里，需要关闭 ASP.NET 请求验证。
$webConfig = @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.web>
    <httpRuntime requestValidationMode="2.0" />
    <pages validateRequest="false" />
  </system.web>
</configuration>
'@
Set-Content -LiteralPath (Join-Path $SitePath 'web.config') -Value $webConfig -Encoding UTF8
Write-Host "  [OK] web.config（关闭请求验证，仅用于本地实验）"

# ── 4. 权限和防火墙 ──────────────────────────────────────────────────────────
Write-Host "`n[4/5] 配置权限和防火墙"
$acl = Get-Acl -LiteralPath $SitePath
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    'IIS_IUSRS',
    'ReadAndExecute',
    'ContainerInherit,ObjectInherit',
    'None',
    'Allow'
)
$acl.SetAccessRule($rule)
Set-Acl -LiteralPath $SitePath -AclObject $acl
Write-Host "  [OK] IIS_IUSRS 读取权限"

if (-not $SkipFirewall) {
    $firewallName = "MatrixLab IIS $Port"
    Remove-NetFirewallRule -DisplayName $firewallName -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName $firewallName `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort $Port `
        -Profile Private,Domain | Out-Null
    Write-Host "  [OK] 入站规则 $firewallName（Private/Domain）"
}

# ── 5. 探测 ──────────────────────────────────────────────────────────────────
Write-Host "`n[5/5] 探测三个壳"
foreach ($shell in $shells) {
    $url = "http://127.0.0.1:$Port/$shell"
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
        Write-Host ("  [{0}] {1}" -f $response.StatusCode, $url) -ForegroundColor Green
    }
    catch {
        $status = $null
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        if ($status) {
            Write-Host ("  [{0}] {1}" -f $status, $url) -ForegroundColor Yellow
        }
        else {
            Write-Host ("  [ERR] {0}: {1}" -f $url, $_.Exception.Message) -ForegroundColor Red
        }
    }
}

Write-Host @"

完成。

Matrix 连接参数：
- CSHAP_ASMX_AES_BASE64  -> connector: aspx_godzilla
- CSHAP_EVAL_AES_BASE64  -> connector: aspx_godzilla
- ASP_EVAL_BASE64        -> connector: asp_godzilla

默认密码: mAtrix_911
默认密钥: key

URL:
  http://localhost:$Port/godzilla_csharp_asmx_aes_base64.asmx
  http://localhost:$Port/godzilla_csharp_eval_aes_base64.aspx
  http://localhost:$Port/godzilla_asp_eval_base64.asp

注意：
- .asmx/.aspx 的 GET 返回 200 只代表 IIS 能执行页面；
  真正连接请在 Matrix 里用对应 connector + cryption 发 POST。
- .asp 的 eval 壳直接 GET 可能返回 500，这是正常的；
  用 Matrix 连接验证。
- 如果 .aspx 报 ASP.NET 未注册，执行：
  C:\Windows\Microsoft.NET\Framework64\v4.0.30319\aspnet_regiis.exe -i
- 如果 500 且事件日志提示 32/64 位问题，把应用池
  enable32BitAppOnWin64 改为 True 再试。
"@ -ForegroundColor Cyan
