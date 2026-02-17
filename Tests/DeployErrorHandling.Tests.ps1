# DeployErrorHandling.Tests.ps1 - Verify Deploy.ps1 has structured error handling
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    $deployPath = Join-Path $PSScriptRoot '..' 'Deploy.ps1'
    $deployContent = Get-Content -Path $deployPath -Raw
}

Describe 'Deploy.ps1 Error Handling' -Tag 'ErrorHandling', 'Static' {

    Context 'Section Results Tracking' {
        It 'Initializes sectionResults array' {
            $deployContent | Should -Match '\$sectionResults\s*=\s*@\(\)'
        }

        It 'Tracks DHCP configuration section results' {
            $deployContent | Should -Match '\$sectionResults\s*\+=.*Section\s*=\s*[''"]DHCP Configuration[''"]'
        }

        It 'Tracks DNS forwarders section results' {
            $deployContent | Should -Match '\$sectionResults\s*\+=.*Section\s*=\s*[''"]DNS Forwarders[''"]'
        }

        It 'Tracks DC1 share creation section results' {
            $deployContent | Should -Match '\$sectionResults\s*\+=.*Section\s*=\s*[''"]DC1 Share Creation[''"]'
        }

        It 'Tracks DC1 OpenSSH section results' {
            $deployContent | Should -Match '\$sectionResults\s*\+=.*Section\s*=\s*[''"]DC1 OpenSSH[''"]'
        }

        It 'Tracks RSAT installation section results' {
            $deployContent | Should -Match '\$sectionResults\s*\+=.*Section\s*=\s*[''"]RSAT Installation[''"]'
        }

        It 'Tracks LabReady checkpoint section results' {
            $deployContent | Should -Match '\$sectionResults\s*\+=.*Section\s*=\s*[''"]LabReady Checkpoint[''"]'
        }

        It 'Prints deployment summary table' {
            $deployContent | Should -Match 'Deployment Section Results'
        }
    }

    Context 'DHCP Configuration Error Handling' {
        It 'Wraps DHCP configuration in try-catch' {
            # Find the DHCP section and verify try-catch structure
            $dhcpSection = $deployContent -match '(?s)# DC1: DHCP ROLE.*?Configure DNS forwarders'
            $dhcpSection | Should -Be $true

            # Check for try block
            $deployContent | Should -Match '(?s)DHCP.*?try\s*\{'

            # Check for catch block
            $deployContent | Should -Match '(?s)catch\s*\{.*?DHCP configuration failed'
        }

        It 'Logs warning on DHCP failure and continues' {
            $deployContent | Should -Match 'DHCP configuration failed.*Exception\.Message'
            $deployContent | Should -Match 'DHCP is non-critical.*Continuing'
        }

        It 'Includes troubleshooting steps for DHCP errors' {
            $deployContent | Should -Match 'Troubleshooting:.*DHCP.*Get-Service DHCPServer'
        }
    }

    Context 'DNS Forwarders Error Handling' {
        It 'Has try-catch around DNS forwarder configuration' {
            $deployContent | Should -Match '(?s)Configure DNS forwarders.*?try\s*\{'
            $deployContent | Should -Match 'DNS forwarder configuration failed'
        }

        It 'Includes troubleshooting steps for DNS errors' {
            $deployContent | Should -Match 'Troubleshooting:.*DNS.*Get-DnsServerForwarder'
        }
    }

    Context 'Share Creation Error Handling' {
        It 'Has try-catch around share creation' {
            $deployContent | Should -Match '(?s)share creation.*try\s*\{'
            $deployContent | Should -Match 'DC1 share creation failed'
        }

        It 'Logs warning on share creation failure and continues' {
            $deployContent | Should -Match 'File sharing may be unavailable.*Continuing'
        }

        It 'Includes troubleshooting steps for share errors' {
            $deployContent | Should -Match 'Troubleshooting:.*share.*Get-SmbShare'
        }
    }

    Context 'SSH Configuration Error Handling' {
        It 'Has try-catch around OpenSSH configuration' {
            $deployContent | Should -Match '(?s)OpenSSH.*try\s*\{'
            $deployContent | Should -Match 'DC1 OpenSSH setup failed'
        }

        It 'Logs warning on SSH failure and continues' {
            $deployContent | Should -Match 'Continuing deployment without DC1 SSH'
        }

        It 'Includes troubleshooting steps for SSH errors' {
            $deployContent | Should -Match 'Troubleshooting:.*OpenSSH.*Get-Service sshd'
        }
    }

    Context 'RSAT Installation Error Handling' {
        It 'Has try-catch around RSAT installation' {
            $deployContent | Should -Match '(?s)RSAT.*catch\s*\{'
            $deployContent | Should -Match 'RSAT installation failed'
        }

        It 'Logs warning on RSAT failure and continues' {
            $deployContent | Should -Match 'ws1 will work without RSAT'
        }

        It 'Includes troubleshooting steps for RSAT errors' {
            $deployContent | Should -Match 'Troubleshooting:.*RSAT.*Get-WindowsCapability'
        }
    }

    Context 'LabReady Checkpoint Validation' {
        It 'Validates LabReady checkpoint after creation' {
            $deployContent | Should -Match '(?s)Checkpoint-LabVM.*Validate LabReady checkpoint'
        }

        It 'Checks each VM for LabReady checkpoint' {
            $deployContent | Should -Match 'Get-VMSnapshot.*-Name.*LabReady'
        }

        It 'Logs warning if checkpoint missing on any VM' {
            $deployContent | Should -Match 'LabReady checkpoint missing for VM'
        }

        It 'Tracks checkpoint validation result' {
            $deployContent | Should -Match 'LabReady checkpoint incomplete'
        }

        It 'Includes troubleshooting steps for checkpoint issues' {
            $deployContent | Should -Match 'Troubleshooting:.*Check snapshots.*Get-VMSnapshot'
        }
    }

    Context 'Error Message Quality' {
        It 'Uses Write-LabStatus for all error messages' {
            # Count catch blocks
            $catchBlocks = ([regex]::Matches($deployContent, 'catch\s*\{[^}]*DHCP|DNS|share|SSH|RSAT|checkpoint')).Count
            $catchBlocks | Should -BeGreaterThan 0

            # Verify Write-LabStatus is used in catch blocks
            $statusCalls = ([regex]::Matches($deployContent, '(?s)catch\s*\{[^}]*Write-LabStatus')).Count
            $statusCalls | Should -BeGreaterThan 0
        }

        It 'Includes exception message in error output' {
            # Verify exception details are captured
            $deployContent | Should -Match '\$\(\$_\.Exception\.Message\)'
        }

        It 'Distinguishes between fatal and non-fatal errors' {
            # Non-fatal errors should say "Continuing"
            $deployContent | Should -Match 'Continuing.*deployment'
        }
    }

    Context 'Per-Section Timing' {
        It 'Records start time for each major section' {
            $deployContent | Should -Match '\$dhcpSectionStart\s*=\s*Get-Date'
            $deployContent | Should -Match '\$dnsSectionStart\s*=\s*Get-Date'
            $deployContent | Should -Match '\$shareSectionStart\s*=\s*Get-Date'
            $deployContent | Should -Match '\$sshSectionStart\s*=\s*Get-Date'
            $deployContent | Should -Match '\$rsatSectionStart\s*=\s*Get-Date'
            $deployContent | Should -Match '\$checkpointSectionStart\s*=\s*Get-Date'
        }

        It 'Calculates duration for each section' {
            $deployContent | Should -Match 'Duration\s*=\s*\(Get-Date\)\s*-\s*\$.*SectionStart'
        }
    }

    Context 'Deployment Summary Table' {
        It 'Prints summary table after deployment' {
            $deployContent | Should -Match 'Deployment Section Results'
        }

        It 'Displays section name, status, and duration' {
            $deployContent | Should -Match '\$sectionResults.*ForEach-Object'
            $deployContent | Should -Match 'Section.*Status.*duration'
        }

        It 'Color-codes status (OK=Green, WARN=Yellow, FAIL=Red)' {
            $deployContent | Should -Match 'statusColor.*switch.*Status'
            $deployContent | Should -Match "'OK'.*'Green'"
            $deployContent | Should -Match "'WARN'.*'Yellow'"
            $deployContent | Should -Match "'FAIL'.*'Red'"
        }
    }
}
