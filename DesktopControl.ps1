param([switch]$Preview)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DesktopHost {
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr z,int x,int y,int w,int height,uint flags);
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(uint pid);
}
'@
[void][DesktopHost]::SetProcessDPIAware()
$mutex = [Threading.Mutex]::new($false,'Local\System2DesktopControl')
if (-not $Preview -and -not $mutex.WaitOne(0)) { exit }
$flag = Join-Path $PSScriptRoot 'display-paused.flag'
$window = [Windows.Markup.XamlReader]::Load([Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'DesktopControl.xaml')))
$button=$window.FindName('Power'); $ring=$window.FindName('Ring'); $icon=$window.FindName('PowerIcon'); $halo=$window.FindName('Halo')
$settingsButton=$window.FindName('Settings')
$settingsEvent=[Threading.Mutex]::new($false,'Local\System2DisplaySettings')
$settingsButton.Add_Click({
 $path=Join-Path $PSScriptRoot 'display-config.json'
 try {
  $config=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  $dialog=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'DisplaySettings.xaml')))
  $dialog.Owner=$window
  $start=$dialog.FindName('StartTime'); $end=$dialog.FindName('EndTime')
  $animate=$dialog.FindName('Animate'); $keep=$dialog.FindName('KeepDisplay'); $status=$dialog.FindName('Status')
  $start.Text=$config.start; $end.Text=$config.end
  $animate.IsChecked=$config.animateSaver -ne $false
  $keep.IsChecked=$config.keepDisplayAfterHours -ne $false
  $dialog.FindName('PowerOptions').Add_Click({
   try { Start-Process control.exe -ArgumentList '/name Microsoft.PowerOptions' } catch { $status.Text=$_.Exception.Message }
  })
  $dialog.FindName('UpdatePreview').Add_Click({
   try {
    Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'UpdateOverlay.ps1') + '" -Seconds 12 -Demo')
    $dialog.Close()
   } catch { $status.Text=$_.Exception.Message }
  })
  $dialog.FindName('Save').Add_Click({
   $first=$start.Text.Trim(); $last=$end.Text.Trim()
   if($first -notmatch '^(?:[01]\d|2[0-3]):[0-5]\d$' -or $last -notmatch '^(?:[01]\d|2[0-3]):[0-5]\d$' -or $first -eq $last){
    $status.Text='Enter two different times in 24-hour HH:mm format.'
    return
   }
   $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
   try {
    $config.start=$first; $config.end=$last
    $config | Add-Member -NotePropertyName animateSaver -NotePropertyValue ([bool]$animate.IsChecked) -Force
    $config | Add-Member -NotePropertyName keepDisplayAfterHours -NotePropertyValue ([bool]$keep.IsChecked) -Force
    [IO.File]::WriteAllText($temp,($config | ConvertTo-Json -Depth 6))
    [IO.File]::Replace($temp,$path,[NullString]::Value)
    $dialog.DialogResult=$true
   } catch { $status.Text=$_.Exception.Message }
   finally { if([IO.File]::Exists($temp)){ [IO.File]::Delete($temp) } }
  })
  try { [void]$settingsEvent.WaitOne() } catch [Threading.AbandonedMutexException] {}
  try { [void]$dialog.ShowDialog() } finally { $settingsEvent.ReleaseMutex() }
 } catch { [void][Windows.MessageBox]::Show($_.Exception.Message,'Display settings') }
})
function Update-State {
 $enabled=-not (Test-Path -LiteralPath $flag)
 $ring.Stroke=if($enabled){'#55F7A0'}else{'#52606B'}
 $icon.Stroke=if($enabled){'#8FFFC0'}else{'#C7D1D9'}
 $halo.Opacity=if($enabled){0.34}else{0}
 $button.ToolTip=if($enabled){'Pause automatic display'}else{'Enable automatic display'}
}
function Attach-Desktop {
 $handle=[Windows.Interop.WindowInteropHelper]::new($window).Handle
 $area=[Windows.SystemParameters]::WorkArea
 $source=[Windows.PresentationSource]::FromVisual($window)
 $scale=$source.CompositionTarget.TransformToDevice.M11
 [void][DesktopHost]::SetWindowPos($handle,[IntPtr]::new(-1),[int](($area.Right-$window.Width-28)*$scale),[int](($area.Bottom-$window.Height-24)*$scale),0,0,0x11)
}
$button.Add_Click({
 try {
  if(Test-Path -LiteralPath $flag){
   $pidFile=Join-Path $PSScriptRoot 'display-controller.pid'
   if(Test-Path -LiteralPath $pidFile){
    [void][DesktopHost]::AllowSetForegroundWindow([uint32]([IO.File]::ReadAllText($pidFile).Trim()))
   }
   Remove-Item -LiteralPath $flag
  }else{[IO.File]::WriteAllText($flag,'paused')}
  Update-State
 } catch {[Windows.MessageBox]::Show('Could not save selection: '+$_.Exception.Message)}
})
Update-State
if($Preview){
 $window.Content.Measure([Windows.Size]::new(180,190))
 $window.Content.Arrange([Windows.Rect]::new(0,0,180,190))
 foreach($state in @('on','off')){
  $ring.Stroke=if($state -eq 'on'){'#55F7A0'}else{'#52606B'}
  $icon.Stroke=if($state -eq 'on'){'#8FFFC0'}else{'#C7D1D9'}
  $halo.Opacity=if($state -eq 'on'){0.34}else{0}
  $window.Content.UpdateLayout()
  $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(720,760,384,384,[Windows.Media.PixelFormats]::Pbgra32)
  $bitmap.Render($window.Content)
  $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
  $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
  $stream=[IO.File]::Create((Join-Path $PSScriptRoot "desktop-control-$state.png"))
  try{$encoder.Save($stream)}finally{$stream.Dispose()}
 }
 exit
}
$window.Add_SourceInitialized({Attach-Desktop})
$timer=[Windows.Threading.DispatcherTimer]::new()
$timer.Interval=[TimeSpan]::FromSeconds(2)
$timer.Add_Tick({Update-State;Attach-Desktop})
$timer.Start()
try{[void]$window.ShowDialog()}finally{$timer.Stop();$settingsEvent.Dispose();$mutex.ReleaseMutex();$mutex.Dispose()}
