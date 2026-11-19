using System;
using System.IO;
using System.Linq;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using System.Runtime.InteropServices;
public class QuantumOverlay : Form {
 public static string AnimationPath;
 static Image animation;
 static int[] frameEnds;
 static int loopMilliseconds;
 static void LoadAnimation(){
  if(animation!=null)return;
  animation=Image.FromFile(AnimationPath);
  int count=animation.GetFrameCount(System.Drawing.Imaging.FrameDimension.Time);
  byte[] delays=animation.GetPropertyItem(0x5100).Value;
  frameEnds=new int[count];
  for(int i=0;i<count;i++){loopMilliseconds+=Math.Max(20,BitConverter.ToInt32(delays,i*4)*10);frameEnds[i]=loopMilliseconds;}
 }
 readonly Timer timer=new Timer(); readonly DateTime start=DateTime.UtcNow;
 int seconds; string logs; string[] lines=new string[]{"Checking updates..."}; int ticks;
 [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint flags);
 public QuantumOverlay(int duration,string path) {
  seconds=duration; logs=path; FormBorderStyle=FormBorderStyle.None; ShowInTaskbar=false; TopMost=true;
  LoadAnimation();
  StartPosition=FormStartPosition.Manual; Bounds=SystemInformation.VirtualScreen; BackColor=Color.FromArgb(49,49,49);
  DoubleBuffered=true; KeyPreview=true; KeyDown+=(s,e)=>{if(e.KeyCode==Keys.Escape)Close();};
  if (logs == null) lines = new string[0];
  timer.Interval=33; timer.Tick+=(s,e)=>{if((DateTime.UtcNow-start).TotalSeconds>=seconds){Close();return;} if(logs!=null && ticks++%30==0)ReadLogs(); Invalidate();};
  Shown+=(s,e)=>{SetThreadExecutionState(0x80000003);timer.Start();};
  FormClosed+=(s,e)=>{timer.Stop();timer.Dispose();SetThreadExecutionState(0x80000000);};
 }
 void ReadLogs(){try{lines=Directory.GetFiles(logs,DateTime.Now.ToString("yyyy-MM-dd")+"-*.log").SelectMany(p=>File.ReadAllLines(p).Where(x=>!String.IsNullOrWhiteSpace(x))).OrderBy(x=>x).Reverse().Take(7).Reverse().ToArray();}catch{}}
 protected override void OnPaint(PaintEventArgs e){Draw(e.Graphics,ClientSize,(DateTime.UtcNow-start).TotalSeconds,seconds,lines,logs==null);}
 static void DrawText(Graphics g,string s,string face,float size,Color color,float x,float y){using(var f=new Font(face,size,FontStyle.Regular,GraphicsUnit.Pixel))using(var b=new SolidBrush(color))g.DrawString(s,f,b,x,y);}
 static void Draw(Graphics g,Size size,double t,int duration,string[] log,bool demo=false){
  LoadAnimation();
  g.SmoothingMode=SmoothingMode.AntiAlias;g.Clear(Color.FromArgb(49,49,49));
  float w=size.Width,h=size.Height,cx=w/2;
  int ms=(int)((t*1000*0.65)%loopMilliseconds),frame=0;
  while(frame<frameEnds.Length-1 && ms>=frameEnds[frame])frame++;
  animation.SelectActiveFrame(System.Drawing.Imaging.FrameDimension.Time,frame);
  float side=Math.Min(500,h*.52f);
  g.InterpolationMode=InterpolationMode.HighQualityBicubic;
  g.DrawImage(animation,cx-side/2,h*.34f-side/2,side,side);
  var center=new StringFormat{Alignment=StringAlignment.Center};
  using(var f=new Font("Segoe UI Light",32,FontStyle.Regular,GraphicsUnit.Pixel))using(var b=new SolidBrush(Color.FromArgb(239,240,241)))g.DrawString(demo?"Update animation preview":"Updating the system",f,b,cx,h*.62f,center);
  using(var f=new Font("Segoe UI",15,FontStyle.Regular,GraphicsUnit.Pixel))using(var b=new SolidBrush(Color.FromArgb(180,185,190)))g.DrawString(demo?"Press Esc to close":"Checking updates",f,b,cx,h*.68f,center);
  float left=w*.23f,top=h*.78f;int remaining=Math.Max(0,duration-(int)t);
  DrawText(g,"WINDOWS  /  APPS  /  DRIVERS", "Consolas",12,Color.FromArgb(102,147,174),left,top-30);
  DrawText(g,TimeSpan.FromSeconds(remaining).ToString(@"mm\:ss")+"  until display returns", "Consolas",12,Color.FromArgb(102,147,174),w*.62f,top-30);
  for(int i=0;i<Math.Min(log.Length,7);i++){string line=log[i];if(line.Length>110)line=line.Substring(0,107)+"...";DrawText(g,line,"Consolas",12,Color.FromArgb(129,157,178),left,top+i*18);}
  using(var b=new SolidBrush(Color.FromArgb(26,47,65)))g.FillRectangle(b,left,h*.96f,w*.54f,2);
  using(var b=new SolidBrush(Color.FromArgb(103,205,244)))g.FillRectangle(b,left,h*.96f,(float)(w*.54*Math.Min(1,t/duration)),2);
 }
 public static void Run(int seconds,string logs){Application.EnableVisualStyles();Application.Run(new QuantumOverlay(seconds,logs));}
 public static void Preview(string path){using(var bmp=new Bitmap(1600,1000))using(var g=Graphics.FromImage(bmp)){Draw(g,bmp.Size,136,900,new[]{"03:30:00 Checking updates / System","03:30:01 Scanning Microsoft Update: software and hardware drivers.","03:30:02 Checking updates / Apps","Preview — live update results appear here during the scheduled run."});bmp.Save(path,System.Drawing.Imaging.ImageFormat.Png);}}
}
