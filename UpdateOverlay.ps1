param([int]$Seconds=900,[string]$PreviewPath,[switch]$Demo)
$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'UpdateOverlay.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing
[QuantumOverlay]::AnimationPath = Join-Path $PSScriptRoot 'quarks.gif'
if($PreviewPath) { [QuantumOverlay]::Preview($PreviewPath); exit }
$mutex=[Threading.Mutex]::new($false,'Local\System2QuantumOverlay')
if(-not $mutex.WaitOne(0)){exit}
try {
    $logs=if($Demo){$null}else{Join-Path $env:ProgramData 'System2Updates'}
    [QuantumOverlay]::Run($Seconds,$logs)
}
finally {$mutex.ReleaseMutex();$mutex.Dispose()}
