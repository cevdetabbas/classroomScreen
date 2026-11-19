# Classroom Screen

Windows classroom display scheduler with a desktop power switch and settings gear. After scheduled hours, it displays a moving icon on a black background.

Set the classroom URL in display-config.json. Keep System2Display.exe alongside the scripts and double-click it to run the display. Use Install-DisplaySchedule.ps1 to register automatic startup. The installer sets Windows sleep, hibernation, and monitor timeouts. It requires a signed-in user session to display the interface.

If Windows Application Control blocks the unsigned executable, the scheduled task uses Windows PowerShell. Run Build-Display.ps1 to rebuild the EXE. Use DisplaySchedule.ps1 -Check to validate the time windows.

The update animation preview is available from the gear. Start-UpdateOverlay.ps1 runs the animation during the existing weekday maintenance window. See Quarks-NOTICE.txt for animation attribution and licensing.
