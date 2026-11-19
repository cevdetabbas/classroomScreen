$ErrorActionPreference = 'Stop'
$taskName = 'System2 Classroom Display'
$backup = Join-Path $PSScriptRoot 'original-settings.json'
if (-not (Test-Path $backup)) {
    $desktop = Get-ItemProperty 'HKCU:\Control Panel\Desktop'
    $scheme = [regex]::Match((powercfg /getactivescheme | Out-String),'[a-f0-9-]{36}').Value
    powercfg /query $scheme | Set-Content (Join-Path $PSScriptRoot 'original-power.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Power backup failed.' }
    @{ Scheme=$scheme; ScreenSaveActive=$desktop.ScreenSaveActive } | ConvertTo-Json | Set-Content $backup
}
foreach ($setting in @('standby-timeout-ac','standby-timeout-dc','hibernate-timeout-ac','hibernate-timeout-dc')) {
    powercfg /change $setting 0
    if ($LASTEXITCODE -ne 0) { throw "powercfg failed: $setting" }
}
powercfg /change monitor-timeout-ac 5
if ($LASTEXITCODE -ne 0) { throw 'AC display setting failed.' }
powercfg /change monitor-timeout-dc 5
if ($LASTEXITCODE -ne 0) { throw 'DC display setting failed.' }
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name ScreenSaveActive -Value '0'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$exe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$action = New-ScheduledTaskAction -Execute $exe -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'DisplaySchedule.ps1') + '"') -WorkingDirectory $PSScriptRoot
$logon = New-ScheduledTaskTrigger -AtLogOn -User $identity
$config = Get-Content (Join-Path $PSScriptRoot 'display-config.json') -Raw | ConvertFrom-Json
$morning = New-ScheduledTaskTrigger -Daily -At ([datetime]::Today.Add([timespan]::Parse($config.start)))
$watchdog = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -WakeToRun -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([timespan]::Zero) -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($logon,$watchdog,$morning) -Principal $principal -Settings $settings -Description 'Classroom display and after-hours screen saver. Schedule is set through the desktop gear. Requires a signed-in session.' -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Get-ScheduledTask -TaskName $taskName | Select-Object TaskName,State
