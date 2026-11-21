# Local IIS lab for Godzilla shells

This script enables IIS and deploys the three upstream Godzilla shells used by
Matrix:

- `CSHAP_ASMX_AES_BASE64` (`.asmx`)
- `CSHAP_EVAL_AES_BASE64` (`.aspx`)
- `ASP_EVAL_BASE64` (`.asp`)

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
| `http://localhost:8080/godzilla_csharp_asmx_aes_base64.asmx` | `aspx_godzilla` | `CSHAP_ASMX_AES_BASE64` |
| `http://localhost:8080/godzilla_csharp_eval_aes_base64.aspx` | `aspx_godzilla` | `CSHAP_EVAL_AES_BASE64` |
| `http://localhost:8080/godzilla_asp_eval_base64.asp` | `asp_godzilla` | `ASP_EVAL_BASE64` |

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
