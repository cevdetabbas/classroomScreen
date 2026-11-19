param([switch]$Check)
$ErrorActionPreference = 'Stop'
$configPath = Join-Path $PSScriptRoot 'display-config.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
function Test-Active([datetime]$Time) {
    $start = [timespan]::Parse($config.start)
    $end = [timespan]::Parse($config.end)
    if ($start -gt $end -and $Time.TimeOfDay -lt $end) {
        return $config.days -contains $Time.AddDays(-1).DayOfWeek.ToString()
    }
    return ($config.days -contains $Time.DayOfWeek.ToString()) -and
        ($Time.TimeOfDay -ge $start) -and ($start -gt $end -or $Time.TimeOfDay -lt $end)
}
function Test-UpdateWindow([datetime]$Time) {
    return $Time.DayOfWeek -notin @('Saturday','Sunday') -and $Time.TimeOfDay -ge [timespan]'15:30' -and $Time.TimeOfDay -lt [timespan]'16:00'
}
function Test-OverlayRunning {
    try {
        if (-not $script:overlayMutex.WaitOne(0)) { return $true }
    } catch [Threading.AbandonedMutexException] {
        # Windows grants ownership after an overlay crash; release it below.
    }
    $script:overlayMutex.ReleaseMutex()
    return $false
}
Add-Type -Path (Join-Path $PSScriptRoot 'WindowControl.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing
function Test-Schedule {
    $savedConfig = $config
    $config = @{ start='07:30'; end='16:00'; days=@('Monday','Saturday') }
    foreach ($case in @(@('2026-09-14T07:29:00',$false),@('2026-09-14T07:30:00',$true),@('2026-09-14T15:59:59',$true),@('2026-09-14T16:00:00',$false),@('2026-09-19T10:00:00',$true))) {
        if ((Test-Active ([datetime]$case[0])) -ne $case[1]) { throw "Schedule failed: $($case[0])" }
    }
    $config = @{ start='22:00'; end='06:00'; days=@('Monday') }
    foreach ($case in @(@('2026-09-14T21:59:59',$false),@('2026-09-14T22:00:00',$true),@('2026-09-15T05:59:59',$true),@('2026-09-15T06:00:00',$false),@('2026-09-16T02:00:00',$false))) {
        if ((Test-Active ([datetime]$case[0])) -ne $case[1]) { throw "Overnight schedule failed: $($case[0])" }
    }
    $config = $savedConfig
    Write-Output "Schedule checks passed. Current active state: $(Test-Active (Get-Date))"
    foreach ($case in @(@('2026-11-03T15:29:59',$false),@('2026-11-03T15:30:00',$true),@('2026-11-03T15:59:59',$true),@('2026-11-03T16:00:00',$false),@('2026-11-07T15:35:00',$false))) {
        if ((Test-UpdateWindow ([datetime]$case[0])) -ne $case[1]) { throw "Update window failed: $($case[0])" }
    }
    Write-Output 'Update-window boundary checks passed.'
}
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DisplayNative {
 [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint mouseData, flags, time; public UIntPtr extraInfo; }
 [StructLayout(LayoutKind.Explicit)] struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mouse; }
 [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public INPUTUNION data; }
 [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint count, INPUT[] inputs, int size);
 public static bool WakeDisplay() {
   var input = new INPUT();
   input.data.mouse.flags = 1; // Relative zero-distance mouse movement; no click or key.
   return SendInput(1, new INPUT[] { input }, Marshal.SizeOf(typeof(INPUT))) == 1;
 }
 [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);
 [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, IntPtr wp, IntPtr lp, uint flags, uint timeout, out IntPtr result);
 [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint action, uint param, IntPtr value, uint flags);
 [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] public class MMDeviceEnumerator {}
 [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 public interface IMMDeviceEnumerator { void Skip(); void GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device); }
 [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 public interface IMMDevice { void Activate(ref Guid iid, int clsCtx, IntPtr activationParams, out IAudioEndpointVolume volume); }
 [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 public interface IAudioEndpointVolume { void RegisterControlChangeNotify(IntPtr n); void UnregisterControlChangeNotify(IntPtr n); void GetChannelCount(out uint n); void SetMasterVolumeLevel(float level, Guid context); void SetMasterVolumeLevelScalar(float level, Guid context); void GetMasterVolumeLevel(out float level); void GetMasterVolumeLevelScalar(out float level); void SetChannelVolumeLevel(uint channel, float level, Guid context); void SetChannelVolumeLevelScalar(uint channel, float level, Guid context); void GetChannelVolumeLevel(uint channel, out float level); void GetChannelVolumeLevelScalar(uint channel, out float level); void SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, Guid context); void GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute); }
 public static void SetAudio(float level) { var e = (IMMDeviceEnumerator)new MMDeviceEnumerator(); IMMDevice d; e.GetDefaultAudioEndpoint(0, 1, out d); var iid = typeof(IAudioEndpointVolume).GUID; IAudioEndpointVolume v; d.Activate(ref iid, 23, IntPtr.Zero, out v); v.SetMute(false, Guid.Empty); v.SetMasterVolumeLevelScalar(level, Guid.Empty); }
}
'@
if ($Check) { Test-Schedule; exit }
$mutex = [Threading.Mutex]::new($false, 'Local\System2DisplaySchedule')
if (-not $mutex.WaitOne(0)) { exit }
$overlayMutex = [Threading.Mutex]::new($false, 'Local\System2QuantumOverlay')
$settingsMutex = [Threading.Mutex]::new($false,'Local\System2DisplaySettings')
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'display-controller.pid'),[string]$PID)
$lastLaunch = [datetime]::MinValue
function Set-Monitor([int]$State) {
    $result = [IntPtr]::Zero
    [void][DisplayNative]::SendMessageTimeout([IntPtr]65535, 0x112, [IntPtr]0xF170, [IntPtr]$State, 2, 1000, [ref]$result)
}
function Set-ClassroomAudio { [DisplayNative]::SetAudio([single]0.70) }
function Open-Classroom {
    $profile = Join-Path $PSScriptRoot 'browser-profile'
    $running = Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($profile) -and $_.CommandLine -notmatch '--type=' }
    $handle = [IntPtr]::Zero
    foreach ($browser in $running) {
        $handle = [ClassroomWindow]::FindBrowserWindow([int]$browser.ProcessId)
        if ($handle -ne [IntPtr]::Zero) { return $handle }
    }
    if (((Get-Date) - $script:lastLaunch).TotalSeconds -ge 10) {
        $script:lastLaunch = Get-Date
        Start-Process 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' -ArgumentList @('--start-maximized', '--no-first-run', '--autoplay-policy=no-user-gesture-required', ('--user-data-dir="' + $profile + '"'), ('--app=' + $config.url))
    }
    return [IntPtr]::Zero
}
$previous = $null
$lastEscape = [datetime]::MinValue
$lastBrowserCheck = [datetime]::MinValue
$lastBring = [datetime]::MinValue
$wakeAttempts = 0
$nextWake = [datetime]::MaxValue
$widget = $null
$widgetCheck = [datetime]::MinValue
$wasPaused = $false
$wasUpdating = $false
$wasInSettings = $false
$configCheck = [datetime]::MinValue
$configStamp = [IO.File]::GetLastWriteTimeUtc($configPath)
try {
    [void][DisplayNative]::SystemParametersInfo(17, 0, [IntPtr]::Zero, 0)
    while ($true) {
        $maintenanceNow = Get-Date
        if ($maintenanceNow -ge $configCheck) {
            $configCheck = $maintenanceNow.AddSeconds(2)
            try {
                $stamp = [IO.File]::GetLastWriteTimeUtc($configPath)
                if ($stamp -ne $configStamp) {
                    $newConfig = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
                    [void][timespan]::Parse($newConfig.start)
                    [void][timespan]::Parse($newConfig.end)
                    $config = $newConfig
                    $configStamp = $stamp
                    [ClassroomWindow]::HideBlackout()
                    $previous = $null
                }
            } catch { Add-Content (Join-Path $PSScriptRoot 'display.log') "Config reload: $_" }
        }
        # Yield for the scheduled window AND for the overlay's actual lifetime.
        # This also covers slow startup/close and manual animation previews.
        $updating = (Test-UpdateWindow $maintenanceNow) -or (Test-OverlayRunning)
        if ($updating) {
            if (-not $wasUpdating) {
                [ClassroomWindow]::HideBlackout()
                [ClassroomWindow]::Restore()
                $wasUpdating = $true
                $previous = $null
                Add-Content (Join-Path $PSScriptRoot 'display.log') "$(Get-Date -Format o) update overlay: classroom and blackout suspended"
            }
            [void][DisplayNative]::SetThreadExecutionState([uint32]2147483651)
            [ClassroomWindow]::PumpEvents()
            Start-Sleep -Milliseconds 100
            continue
        }
        if ($wasUpdating) {
            $wasUpdating = $false; $previous = $null
            Add-Content (Join-Path $PSScriptRoot 'display.log') "$(Get-Date -Format o) update overlay ended: display schedule resumed"
        }
        if (((Get-Date) - $widgetCheck).TotalSeconds -ge 5) {
            $widgetCheck = Get-Date
            if ($null -eq $widget -or $widget.HasExited) {
                $widgetPath = Join-Path $PSScriptRoot 'System2Display.exe'
                if (Test-Path -LiteralPath $widgetPath) {
                    try { $widget = Start-Process -FilePath $widgetPath -ArgumentList '--widget' -PassThru } catch { $widget = $null }
                }
                if ($null -eq $widget -or $widget.HasExited) {
                    $widget = Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $PSScriptRoot 'DesktopControl.ps1') + '"') -PassThru
                }
            }
        }
        $inSettings = $true
        try { $inSettings = -not $settingsMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $inSettings = $false }
        if (-not $inSettings) { $settingsMutex.ReleaseMutex() }
        if ($inSettings) {
            if (-not $wasInSettings) {
                [ClassroomWindow]::HideBlackout()
                [ClassroomWindow]::Restore()
                $wasInSettings = $true
            }
            [void][DisplayNative]::SetThreadExecutionState([uint32]2147483651)
            [ClassroomWindow]::PumpEvents()
            Start-Sleep -Milliseconds 100
            continue
        }
        if ($wasInSettings) {
            $wasInSettings = $false
            $lastEscape = Get-Date
        }
        if (Test-Path (Join-Path $PSScriptRoot 'display-paused.flag')) {
            if (-not $wasPaused) {
                [ClassroomWindow]::Restore()
                [ClassroomWindow]::HideBlackout()
                $wasPaused = $true
                $previous = $null
                Add-Content (Join-Path $PSScriptRoot 'display.log') "$(Get-Date -Format o) manual pause enabled"
            }
            [void][DisplayNative]::SetThreadExecutionState([uint32]2147483651)
            [ClassroomWindow]::PumpEvents()
            Start-Sleep -Milliseconds 200
            continue
        }
        if ($wasPaused) {
            $wasPaused = $false
            $lastBring = [datetime]::MinValue
            $lastEscape = [datetime]::MinValue
            $lastBrowserCheck = [datetime]::MinValue
            Add-Content (Join-Path $PSScriptRoot 'display.log') "$(Get-Date -Format o) manual pause disabled"
        }
        $active = Test-Active (Get-Date)
        # Keep the display pipeline awake overnight: SC_MONITORPOWER off enters
        # Modern Standby on this device and suspends the morning wake code.
        # ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED.
        $flags = if ($active -or $config.keepDisplayAfterHours -ne $false) { [uint32]2147483651 } else { [uint32]2147483649 }
        if ([DisplayNative]::SetThreadExecutionState($flags) -eq 0) { throw 'Execution-state request failed.' }
        if ($active -ne $previous) {
            if ($active) {
                [ClassroomWindow]::HideBlackout()
                $wakeAttempts = 0
                $nextWake = Get-Date
            } else {
                [ClassroomWindow]::Restore()
                [ClassroomWindow]::ShowBlackout($config.animateSaver -ne $false)
            }
            Add-Content (Join-Path $PSScriptRoot 'display.log') "$(Get-Date -Format o) active=$active"
            $previous = $active
        }
        if (-not $active -and -not [ClassroomWindow]::BlackoutVisible -and [ClassroomWindow]::IdleSeconds() -ge 60) {
            [ClassroomWindow]::ShowBlackout($config.animateSaver -ne $false)
        }
        if ($active -and $wakeAttempts -lt 3 -and (Get-Date) -ge $nextWake) {
            Set-Monitor -1
            $wakeSent = [DisplayNative]::WakeDisplay()
            $wakeAttempts++
            $nextWake = (Get-Date).AddSeconds(15)
            Add-Content (Join-Path $PSScriptRoot 'display.log') "$(Get-Date -Format o) Wake attempt=$wakeAttempts inputSent=$wakeSent"
        }
        if ([ClassroomWindow]::Escape()) {
            [ClassroomWindow]::Restore()
            $lastEscape = Get-Date
        }
        if ($active -and ((Get-Date) - $lastBrowserCheck).TotalSeconds -ge 1) {
            $lastBrowserCheck = Get-Date
            try {
                $window = Open-Classroom
                if ($window -ne [IntPtr]::Zero -and ((Get-Date) - $lastEscape).TotalSeconds -ge $config.idleSeconds -and
                    -not [ClassroomWindow]::IsPresented($window)) {
                    $presented = [ClassroomWindow]::Full($window)
                    if (((Get-Date) - $lastBring).TotalSeconds -ge 10) {
                        Add-Content (Join-Path $PSScriptRoot 'display.log') "$(Get-Date -Format o) Present window=$window verified=$presented"
                    }
                    $lastBring = Get-Date
                }
            } catch { Add-Content (Join-Path $PSScriptRoot 'display.log') "$(Get-Date -Format o) Browser: $_" }
        }
        [ClassroomWindow]::PumpEvents()
        Start-Sleep -Milliseconds 50
    }
} finally {
    [ClassroomWindow]::HideBlackout()
    [ClassroomWindow]::Restore()
    [void][DisplayNative]::SetThreadExecutionState([uint32]2147483648)
    $mutex.ReleaseMutex()
    $mutex.Dispose()
    $overlayMutex.Dispose()
    $settingsMutex.Dispose()
}
