$now=Get-Date
if($now.DayOfWeek -in @('Saturday','Sunday') -or $now.TimeOfDay -lt [timespan]'15:30' -or $now.TimeOfDay -ge [timespan]'16:00'){exit}
$remaining=[int][Math]::Ceiling(($now.Date.AddHours(16)-$now).TotalSeconds)
& (Join-Path $PSScriptRoot 'UpdateOverlay.ps1') -Seconds $remaining
