# ISOs

Place your Windows/Linux ISO files here (`C:\LabSources\ISOs`).

Required/expected ISOs:

- **Windows Server 2019 Evaluation** - For DC, MemberServer, FileServer, WebServer roles
- **Windows 11 Enterprise Evaluation** - For Client role
- **Ubuntu Server** - Optional for Linux scenarios

Download sources:

- Windows Server 2019 Evaluation:
  `https://www.microsoft.com/en-us/evalcenter/download-windows-server-2019`
- Windows 11 Enterprise Evaluation:
  `https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise`
- Ubuntu Server:
  `https://ubuntu.com/download/server`

Validation tip:

```powershell
Get-LabAvailableOperatingSystem -Path 'C:\LabSources\ISOs'
```

Use this output to confirm the editions in your ISOs match what lab roles request.

ISOs are not tracked in git due to size.
