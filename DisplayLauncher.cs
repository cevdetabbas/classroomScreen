using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

static class DisplayLauncher
{
    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length > 1 || (args.Length == 1 && args[0] != "--widget" && args[0] != "--check"))
            return 2;

        var mode = args.Length == 0 ? "" : args[0];
        var directory = AppDomain.CurrentDomain.BaseDirectory;
        var script = Path.Combine(directory, mode == "--widget" ? "DesktopControl.ps1" : "DisplaySchedule.ps1");
        try
        {
            if (!File.Exists(script))
                throw new FileNotFoundException("Keep the executable in the System2 folder.", script);
            var powershell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            var start = new ProcessStartInfo(powershell,
                "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + script + "\"" + (mode == "--check" ? " -Check" : ""));
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.WorkingDirectory = directory;
            using (var process = Process.Start(start))
            {
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "System2 Classroom Display", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
