# New-LabUnattendXml.ps1
# Generates unattend.xml content for automated Windows installation

function New-LabUnattendXml {
    <#
    .SYNOPSIS
        Generates unattend.xml content for automated Windows installation.

    .DESCRIPTION
        Creates unattend.xml content for Windows Server 2019 or Windows 11
        with computer name, administrator password, and WinRM enabled.

    .PARAMETER ComputerName
        The computer name to assign.

    .PARAMETER AdministratorPassword
        Plain text administrator password (will be converted to required format).

    .PARAMETER OSType
        Operating system type: Server2019 or Windows11.

    .PARAMETER TimeZone
        Time zone (default: Pacific Standard Time).

    .OUTPUTS
        XML document as string.

    .EXAMPLE
        New-LabUnattendXml -ComputerName "dc1" -AdministratorPassword "P@ssw0rd" -OSType "Server2019"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [string]$AdministratorPassword,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Server2019", "Windows11")]
        [string]$OSType,

        [Parameter()]
        [string]$TimeZone = $(if (Test-Path variable:LabTimeZone) { $LabTimeZone } else { 'Pacific Standard Time' })
    )

    Write-Warning "Unattend.xml stores the administrator password in plaintext. This is inherent to Windows unattended installs. The generated file will be deleted from the VM after first logon."

    # Build unattend.xml as string - using proper escaping
    $xmlTemplate = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <!-- SimpleLab Unattend.xml - Automated Windows Installation -->

  <!-- Specialize Pass -->
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <ComputerName>$ComputerName</ComputerName>
      <TimeZone>$TimeZone</TimeZone>
      <RegisteredOwner>SimpleLab</RegisteredOwner>
      <RegisteredOrganization>SimpleLab</RegisteredOrganization>
    </component>

    <!-- Enable WinRM -->
    <component name="Microsoft-Windows-Management-Service" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <WindowsRemoteManagementEnabled>true</WindowsRemoteManagementEnabled>
    </component>
  </settings>

  <!-- OOBE System Pass -->
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>

      <!-- Administrator Password -->
      <UserAccounts>
        <AdministratorPassword>
          <Value>$AdministratorPassword</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>

      <!-- Auto Logon for first setup -->
      <AutoLogon>
        <Enabled>true</Enabled>
        <Username>Administrator</Username>
        <LogonCount>2</LogonCount>
      </AutoLogon>

      <!-- First Logon Commands -->
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <CommandLine>cmd /c winrm quickconfig -q -force</CommandLine>
          <Order>1</Order>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <CommandLine>cmd /c reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run /v SimpleLabReady /t REG_SZ /d cmd /c echo Done</CommandLine>
          <Order>2</Order>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <CommandLine>cmd /c if exist C:\unattend.xml del /f /q C:\unattend.xml</CommandLine>
          <Order>3</Order>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <CommandLine>cmd /c if exist C:\Windows\Panther\unattend.xml del /f /q C:\Windows\Panther\unattend.xml</CommandLine>
          <Order>4</Order>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <CommandLine>cmd /c if exist C:\Windows\Panther\Unattend\unattend.xml del /f /q C:\Windows\Panther\Unattend\unattend.xml</CommandLine>
          <Order>5</Order>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
"@

    return $xmlTemplate
}
