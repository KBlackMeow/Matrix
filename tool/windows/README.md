# Local IIS lab for Godzilla shells

This script enables IIS and deploys the Windows shells used by Matrix:

- Godzilla ASPX: AES Base64 / AES Raw / ASMX / C# Eval
- Godzilla ASP: Base64 / Raw / XOR Base64 / XOR Raw / Eval
- Behinder ASPX, ASPX CMD, ASP WScript
- SUO5 ASPX (deployed separately)

## Requirements

- Windows 10/11 **Pro / Enterprise / Education**.
  Windows 11 Home does not include IIS.
- **Windows PowerShell 5.1**, run as Administrator. Do not use PowerShell 7
  (`pwsh`); `WebAdministration` is a Windows PowerShell module.
- The three shell files from
  `assets/defaults/payloads/godzilla/` copied next to the script in a
  `payloads\` folder, or passed with `-Source`.

## Copy payloads from macOS

```bash
# From the Matrix repository on the Mac
ssh user@windows-vm 'mkdir C:\matrix-lab\payloads'
scp assets/defaults/payloads/godzilla/godzilla_csharp_asmx_aes_base64.asmx \
    assets/defaults/payloads/godzilla/godzilla_csharp_eval_aes_base64.aspx \
    assets/defaults/payloads/godzilla/godzilla_asp_eval_base64.asp \
    user@windows-vm:'C:/matrix-lab/payloads/'
```

Or copy the whole `godzilla` folder through a shared folder / RDP clipboard
and point `-Source` at it.

## Run

In an Administrator Windows PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup_iis_godzilla.ps1
```

If the script exits with code `3010`, reboot Windows and run it again.

Useful options:

```powershell
.\setup_iis_godzilla.ps1 -Port 80
.\setup_iis_godzilla.ps1 -Source 'D:\matrix\payloads' -SkipFirewall
```

## Matrix connection

| URL | connector | cryption |
| --- | --- | --- |
| `godzilla_aspx_aes_base64.aspx` | `aspx_godzilla` | `CSHAP_AES_BASE64` |
| `godzilla_aspx_aes_raw.aspx` | `aspx_godzilla` | `CSHAP_AES_RAW` |
| `godzilla_csharp_asmx_aes_base64.asmx` | `aspx_godzilla` | `CSHAP_ASMX_AES_BASE64` |
| `godzilla_csharp_eval_aes_base64.aspx` | `aspx_godzilla` | `CSHAP_EVAL_AES_BASE64` |
| `godzilla_asp_base64.asp` | `asp_godzilla` | `ASP_BASE64` |
| `godzilla_asp_raw.asp` | `asp_godzilla` | `ASP_RAW` |
| `godzilla_asp_xor_base64.asp` | `asp_godzilla` | `ASP_XOR_BASE64` |
| `godzilla_asp_xor_raw.asp` | `asp_godzilla` | `ASP_XOR_RAW` |
| `godzilla_asp_eval_base64.asp` | `asp_godzilla` | `ASP_EVAL_BASE64` |
| `aspx_behinder.aspx` | `aspx_behinder` | — |
| `aspx_cmd_post.aspx` | `aspx_cmd` | — |
| `asp_wscript_get.asp` | `asp_wscript` | — |
| `suo5.aspx` | SUO5 代理 | — |

Default password: `mAtrix_911`; secret key: `key`.

A GET on the `.asp` eval shell can return HTTP 500; use Matrix to send the
POST request. The GET check in the script only reports whether IIS serves the
page.

## Troubleshooting

- **`WebAdministration` not found**: use Windows PowerShell 5.1, not `pwsh`.
- **ASP.NET not registered**: run
  `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\aspnet_regiis.exe -i`.
- **Classic ASP 500**: check `IIS-ASP` and `IIS-ClassicAsp` are enabled, and
  try toggling the app pool's `enable32BitAppOnWin64`.
- **IIS features missing**: Windows 11 Home cannot install IIS; use Pro or
  Enterprise/Education.
- The script writes a lab `web.config` that disables ASP.NET request
  validation so the eval shells can receive code in POST parameters. Do not
  reuse that setting outside this lab.

## Enable SSH (for scp from macOS)

In an Administrator **Windows PowerShell** inside the VM:

```powershell
# 1. Install OpenSSH Server (once)
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# 2. Start it and make it persistent
Set-Service -Name sshd -StartupType Automatic
Start-Service -Name sshd

# 3. Allow TCP 22 on the VM's firewall
New-NetFirewallRule `
  -Name 'OpenSSH-Server-In-TCP' `
  -DisplayName 'OpenSSH Server (sshd)' `
  -Enabled True `
  -Direction Inbound `
  -Protocol TCP `
  -Action Allow `
  -LocalPort 22
```

Check the VM IP:

```powershell
ipconfig
whoami
```

From the Mac:

```bash
ssh <windows-user>@<vm-ip>
```

If the Windows account is a Microsoft account, password SSH may fail; create
a local account instead:

```powershell
net user matrixlab 'ChangeMe-Str0ng!' /add
net localgroup administrators matrixlab /add
```

Then use `ssh matrixlab@<vm-ip>`.

For key-only login, put the public key in
`C:\Users\<user>\.ssh\authorized_keys` for a normal user, or in
`C:\ProgramData\ssh\administrators_authorized_keys` for an administrator.
The administrators file must be readable only by Administrators and SYSTEM.

Common checks:

```powershell
Get-Service sshd
Get-WinEvent -LogName OpenSSH/Operational -MaxEvents 30
```

Do not expose port 22 to the public internet; use the VM's NAT/shared network
and a strong password or key.
