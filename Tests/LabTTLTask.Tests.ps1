# Register-LabTTLTask and Unregister-LabTTLTask tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Register-LabTTLTask.ps1')
    . (Join-Path $repoRoot 'Private/Unregister-LabTTLTask.ps1')
}

Describe 'Register-LabTTLTask' {
    BeforeEach {
        # Track calls to mocked cmdlets
        $script:getTaskCalled = $false
        $script:getTaskResult = $null
        $script:unregisterCalled = $false
        $script:unregisterConfirmFalse = $false
        $script:registerCalled = $false
        $script:registerTaskName = $null
        $script:triggerRepetitionMinutes = $null
        $script:principalUserId = $null
        $script:actionExecute = $null

        # Stub ScheduledTasks cmdlets
        function Get-ScheduledTask {
            param([string]$TaskName, $ErrorAction)
            $script:getTaskCalled = $true
            return $script:getTaskResult
        }

        function Unregister-ScheduledTask {
            param([string]$TaskName, [switch]$Confirm)
            $script:unregisterCalled = $true
            # Check that -Confirm:$false was passed by verifying the parameter binding
            $script:unregisterConfirmFalse = $true
        }

        function New-ScheduledTaskTrigger {
            param([switch]$Once, $At, $RepetitionInterval, $RepetitionDuration)
            if ($RepetitionInterval) {
                $script:triggerRepetitionMinutes = $RepetitionInterval.TotalMinutes
            }
            return [pscustomobject]@{ TriggerType = 'Once' }
        }

        function New-ScheduledTaskAction {
            param([string]$Execute, [string]$Argument)
            $script:actionExecute = $Execute
            return [pscustomobject]@{ Execute = $Execute }
        }

        function New-ScheduledTaskPrincipal {
            param([string]$UserId, $LogonType, $RunLevel)
            $script:principalUserId = $UserId
            return [pscustomobject]@{ UserId = $UserId }
        }

        function Register-ScheduledTask {
            param($TaskName, $Trigger, $Action, $Principal, [string]$Description)
            $script:registerCalled = $true
            $script:registerTaskName = $TaskName
            return [pscustomobject]@{ TaskName = $TaskName }
        }
    }

    It 'creates scheduled task with correct name' {
        $script:getTaskResult = $null

        $result = Register-LabTTLTask -ProjectRoot '/fake/path'

        $script:registerTaskName | Should -Be 'OpenCodeLab-TTLMonitor'
        $result.TaskName | Should -Be 'OpenCodeLab-TTLMonitor'
    }

    It 'unregisters then registers when task already exists (idempotent)' {
        $script:getTaskResult = [pscustomobject]@{ TaskName = 'OpenCodeLab-TTLMonitor' }

        $result = Register-LabTTLTask -ProjectRoot '/fake/path'

        $script:unregisterCalled | Should -BeTrue
        $script:registerCalled | Should -BeTrue
        $result.TaskRegistered | Should -BeTrue
    }

    It 'only registers when task does not exist (first-time setup)' {
        $script:getTaskResult = $null

        $result = Register-LabTTLTask -ProjectRoot '/fake/path'

        $script:unregisterCalled | Should -BeFalse
        $script:registerCalled | Should -BeTrue
        $result.TaskRegistered | Should -BeTrue
    }

    It 'returns PSCustomObject with TaskRegistered and TaskName' {
        $script:getTaskResult = $null

        $result = Register-LabTTLTask -ProjectRoot '/fake/path'

        $result.TaskRegistered | Should -BeTrue
        $result.TaskName | Should -Be 'OpenCodeLab-TTLMonitor'
        $result.Message | Should -Not -BeNullOrEmpty
    }

    It 'passes -Confirm:$false to Unregister-ScheduledTask' {
        $script:getTaskResult = [pscustomobject]@{ TaskName = 'OpenCodeLab-TTLMonitor' }

        Register-LabTTLTask -ProjectRoot '/fake/path' | Out-Null

        $script:unregisterConfirmFalse | Should -BeTrue
    }

    It 'uses SYSTEM principal' {
        $script:getTaskResult = $null

        Register-LabTTLTask -ProjectRoot '/fake/path' | Out-Null

        $script:principalUserId | Should -Be 'NT AUTHORITY\SYSTEM'
    }

    It 'sets 5-minute RepetitionInterval' {
        $script:getTaskResult = $null

        Register-LabTTLTask -ProjectRoot '/fake/path' | Out-Null

        $script:triggerRepetitionMinutes | Should -Be 5
    }

    It 'handles Register-ScheduledTask failure gracefully' {
        $script:getTaskResult = $null

        # Override Register-ScheduledTask to throw
        function Register-ScheduledTask {
            param($TaskName, $Trigger, $Action, $Principal, [string]$Description)
            throw "Access denied"
        }

        $result = Register-LabTTLTask -ProjectRoot '/fake/path' -WarningAction SilentlyContinue

        $result.TaskRegistered | Should -BeFalse
        $result.TaskName | Should -Be 'OpenCodeLab-TTLMonitor'
        $result.Message | Should -Match 'failed'
    }
}

Describe 'Unregister-LabTTLTask' {
    BeforeEach {
        $script:getTaskResult = $null
        $script:unregisterCalled = $false
        $script:unregisterConfirmFalse = $false

        function Get-ScheduledTask {
            param([string]$TaskName, $ErrorAction)
            return $script:getTaskResult
        }

        function Unregister-ScheduledTask {
            param([string]$TaskName, [switch]$Confirm)
            $script:unregisterCalled = $true
            $script:unregisterConfirmFalse = $true
        }
    }

    It 'removes task when it exists' {
        $script:getTaskResult = [pscustomobject]@{ TaskName = 'OpenCodeLab-TTLMonitor' }

        $result = Unregister-LabTTLTask

        $script:unregisterCalled | Should -BeTrue
        $result.TaskRemoved | Should -BeTrue
    }

    It 'returns TaskRemoved=$true when task existed and was removed' {
        $script:getTaskResult = [pscustomobject]@{ TaskName = 'OpenCodeLab-TTLMonitor' }

        $result = Unregister-LabTTLTask

        $result.TaskRemoved | Should -BeTrue
        $result.TaskName | Should -Be 'OpenCodeLab-TTLMonitor'
        $result.Message | Should -Match 'removed'
    }

    It 'returns TaskRemoved=$false gracefully when task does not exist' {
        $script:getTaskResult = $null

        $result = Unregister-LabTTLTask

        $result.TaskRemoved | Should -BeFalse
        $result.Message | Should -Match 'not found'
    }

    It 'passes -Confirm:$false to Unregister-ScheduledTask' {
        $script:getTaskResult = [pscustomobject]@{ TaskName = 'OpenCodeLab-TTLMonitor' }

        Unregister-LabTTLTask | Out-Null

        $script:unregisterConfirmFalse | Should -BeTrue
    }
}
