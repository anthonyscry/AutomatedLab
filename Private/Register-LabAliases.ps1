# Register-LabAliases.ps1 -- Register backward-compatible aliases
Set-Alias -Name Remove-VMHardSafe -Value Remove-HyperVVMStale

# Backward-compatible aliases (permanent -- never remove)
Set-Alias -Name Get-LIN1IPv4               -Value Get-LinuxVMIPv4
Set-Alias -Name Get-LIN1DhcpLeaseIPv4      -Value Get-LinuxVMDhcpLeaseIPv4
Set-Alias -Name Invoke-BashOnLIN1          -Value Invoke-BashOnLinuxVM
Set-Alias -Name New-LIN1VM                 -Value New-LinuxVM
Set-Alias -Name Finalize-LIN1InstallMedia  -Value Finalize-LinuxInstallMedia

# Standard-name aliases (Ensure- -> Test-Lab pattern)
Set-Alias -Name Test-LabVMRunning        -Value Ensure-VMRunning
Set-Alias -Name Test-LabVMsReady         -Value Ensure-VMsReady
Set-Alias -Name Test-LabSSHKey           -Value Ensure-SSHKey
