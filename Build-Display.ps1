$ErrorActionPreference = 'Stop'
$compiler = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
}
& $compiler /nologo /target:winexe /optimize+ /reference:System.Windows.Forms.dll "/out:$PSScriptRoot\System2Display.exe" "$PSScriptRoot\DisplayLauncher.cs"
if ($LASTEXITCODE -ne 0) { throw 'System2Display.exe compilation failed.' }
