using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public static class ClassroomWindow {
 static System.Collections.Generic.List<Form> blackout = new System.Collections.Generic.List<Form>();
 public static bool BlackoutVisible { get { return blackout.Count != 0; } }
 public static void ShowBlackout(bool animate) {
   HideBlackout();
   foreach (var screen in Screen.AllScreens) {
     var form = new SaverForm(animate);
     form.FormBorderStyle = FormBorderStyle.None;
     form.StartPosition = FormStartPosition.Manual;
     form.Bounds = screen.Bounds;
     form.BackColor = System.Drawing.Color.Black;
     form.ShowInTaskbar = false;
     form.TopMost = true;
     form.KeyPreview = true;
     form.KeyDown += delegate(object sender, KeyEventArgs e) { e.SuppressKeyPress = true; HideBlackout(); };
     form.MouseDown += delegate { HideBlackout(); };
     blackout.Add(form);
     form.Show();
   }
   Application.DoEvents();
 }
 sealed class SaverForm : Form {
   readonly Timer animation = new Timer();
   readonly System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
   readonly bool animate;
   public SaverForm(bool animate) {
     this.animate = animate;
     DoubleBuffered = true;
     if (!animate) return;
     animation.Interval = 125;
     animation.Tick += delegate { Invalidate(); };
     Shown += delegate { animation.Start(); };
   }
   protected override void OnPaint(PaintEventArgs e) {
     base.OnPaint(e);
     if (!animate) return;
     var t = clock.Elapsed.TotalSeconds;
     var size = Math.Min(34, Math.Min(ClientSize.Width, ClientSize.Height) / 8);
     if (size < 4) return;
     float x = (float)(ClientSize.Width * (0.5 + 0.36 * Math.Sin(t / 17)));
     float y = (float)(ClientSize.Height * (0.5 + 0.34 * Math.Sin(t / 23)));
     e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
     using (var pen = new System.Drawing.Pen(System.Drawing.Color.FromArgb(93, 182, 143), 2)) {
       var r = size / 2f;
       e.Graphics.DrawArc(pen, x-r, y-r, size, size, -55, 290);
       e.Graphics.DrawLine(pen, x, y-r-2, x, y);
     }
   }
   protected override void Dispose(bool disposing) {
     if (disposing) animation.Dispose();
     base.Dispose(disposing);
   }
 }
 public static void HideBlackout() {
   var windows = blackout.ToArray();
   blackout.Clear();
   foreach (var form in windows) { form.Close(); form.Dispose(); }
 }
 public static void PumpEvents() { Application.DoEvents(); }
 [StructLayout(LayoutKind.Sequential)] struct LASTINPUT { public uint size, time; }
 [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUT info);
 [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
 [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int index);
 [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h, int index, int value);
 [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
 [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr h, int cmd);
 [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p,IntPtr l);
 [StructLayout(LayoutKind.Sequential)] struct RECT { public int left,top,right,bottom; }
 public static IntPtr FindBrowserWindow(int processId) {
   IntPtr found=IntPtr.Zero;
   EnumWindows(delegate(IntPtr h,IntPtr l) { uint pid; GetWindowThreadProcessId(h,out pid);
     if(pid==(uint)processId && IsWindowVisible(h)) { found=h; return false; } return true;
   },IntPtr.Zero); return found;
 }
 public static bool IsPresented(IntPtr h) {
   if(h==IntPtr.Zero || !IsWindow(h) || IsIconic(h) || !IsWindowVisible(h) || GetForegroundWindow()!=h) return false;
   RECT r; if(!GetWindowRect(h,out r)) return false;
   var screen=Screen.FromHandle(h).Bounds;
   return r.left==screen.Left && r.top==screen.Top && r.right==screen.Right && r.bottom==screen.Bottom;
 }
 static IntPtr current;
 static int style;
 public static bool Escape() { return (GetAsyncKeyState(27) & 0x8000) != 0; }
 public static double IdleSeconds() { var i = new LASTINPUT(); i.size = (uint)Marshal.SizeOf(i); GetLastInputInfo(ref i); return unchecked((uint)Environment.TickCount - i.time)/1000.0; }
 public static bool Full(IntPtr h) {
   if (h == IntPtr.Zero || !IsWindow(h)) return false;
   if (IsPresented(h)) return true;
   if (current != h) { Restore(); current=h; style=GetWindowLong(h,-16); }
   var r=Screen.FromHandle(h).Bounds;
   if(IsIconic(h)) ShowWindowAsync(h,9);
   SetWindowLong(h,-16,style & ~0x00CF0000);
   SetWindowPos(h,IntPtr.Zero,r.X,r.Y,r.Width,r.Height,0x4020);
   SetForegroundWindow(h);
   return IsPresented(h);
 }
 public static void Restore() {
   if (current==IntPtr.Zero) return;
   if (IsWindow(current)) {
     SetWindowLong(current,-16,style);
     var r=Screen.FromHandle(current).WorkingArea;
     ShowWindowAsync(current,9);
     SetWindowPos(current, new IntPtr(-2),r.X+60,r.Y+60,Math.Max(640,r.Width-120),Math.Max(480,r.Height-120),0x4060);
   }
   current=IntPtr.Zero;
 }
}
