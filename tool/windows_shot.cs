using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

// QA helper: per-monitor scale (read/set) and capture of one window.
public static class Shot {
  [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint Low; public int High; }
  [StructLayout(LayoutKind.Sequential)] public struct HDR { public int type; public int size; public LUID adapter; public uint id; }
  [StructLayout(LayoutKind.Sequential)] public struct GETS { public HDR h; public int min; public int cur; public int max; }
  [StructLayout(LayoutKind.Sequential)] public struct SETS { public HDR h; public int scale; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct SRCNAME { public HDR h; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string name; }
  [StructLayout(LayoutKind.Sequential)] public struct PATH { public LUID sa; public uint sid; public uint smode; public uint sstat; public LUID ta; public uint tid; public uint tmode; public uint tech; public uint rot; public uint scal; public uint rn; public uint rd; public uint scan; public uint tavail; public uint tstat; public uint flags; }
  [StructLayout(LayoutKind.Sequential)] public struct MODE { [MarshalAs(UnmanagedType.ByValArray, SizeConst = 64)] public byte[] raw; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }

  [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint f, out uint p, out uint m);
  [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint f, ref uint np, [Out] PATH[] p, ref uint nm, [Out] MODE[] m, IntPtr t);
  [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")] static extern int GetName(ref SRCNAME r);
  [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")] static extern int GetScale(ref GETS r);
  [DllImport("user32.dll", EntryPoint = "DisplayConfigSetDeviceInfo")] static extern int SetScale(ref SETS r);
  [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int cy, uint flags);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);

  static readonly int[] Steps = { 100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500 };
  public static void Aware() { SetProcessDpiAwarenessContext((IntPtr)(-4)); }

  static List<PATH> Paths() {
    uint np, nm;
    GetDisplayConfigBufferSizes(2, out np, out nm);
    var p = new PATH[np]; var m = new MODE[nm];
    int rc = QueryDisplayConfig(2, ref np, p, ref nm, m, IntPtr.Zero);
    if (rc != 0) throw new Exception("QueryDisplayConfig " + rc);
    var list = new List<PATH>();
    for (int i = 0; i < np; i++) list.Add(p[i]);
    return list;
  }
  static string Name(PATH p) {
    var n = new SRCNAME();
    n.h.type = 1; n.h.size = Marshal.SizeOf(typeof(SRCNAME)); n.h.adapter = p.sa; n.h.id = p.sid;
    int rc = GetName(ref n);
    if (rc != 0) throw new Exception("GetName " + rc);
    return n.name;
  }
  static GETS Read(PATH p) {
    var g = new GETS();
    g.h.type = -3; g.h.size = Marshal.SizeOf(typeof(GETS)); g.h.adapter = p.sa; g.h.id = p.sid;
    int rc = GetScale(ref g);
    if (rc != 0) throw new Exception("GetScale " + rc);
    return g;
  }
  public static string List() {
    var s = "";
    foreach (var p in Paths()) {
      var g = Read(p);
      int rec = -g.min;
      s += string.Format("{0}: atual {1}% recomendado {2}% faixa {3}%-{4}%\n", Name(p), Steps[rec + g.cur], Steps[rec], Steps[0], Steps[rec + g.max]);
    }
    return s;
  }
  public static int Current(string display) {
    foreach (var p in Paths()) if (Name(p) == display) { var g = Read(p); return Steps[-g.min + g.cur]; }
    throw new Exception("display " + display);
  }
  public static void Set(string display, int percent) {
    foreach (var p in Paths()) {
      if (Name(p) != display) continue;
      var g = Read(p);
      int target = Array.IndexOf(Steps, percent);
      if (target < 0) throw new Exception("escala invalida");
      var s = new SETS();
      s.h.type = -4; s.h.size = Marshal.SizeOf(typeof(SETS)); s.h.adapter = p.sa; s.h.id = p.sid;
      s.scale = target - (-g.min);
      int rc = SetScale(ref s);
      if (rc != 0) throw new Exception("SetScale " + rc);
      return;
    }
    throw new Exception("display " + display);
  }
  public static uint Dpi(IntPtr h) { return GetDpiForWindow(h); }
  public static void Place(IntPtr h, int x, int y, int w, int height) {
    ShowWindow(h, 9);
    SetWindowPos(h, IntPtr.Zero, x, y, w, height, 0x0014);
  }
  public static void Maximize(IntPtr h) { ShowWindow(h, 3); }
  public static string Save(IntPtr h, string path) {
    RECT c; GetClientRect(h, out c);
    RECT w; GetWindowRect(h, out w);
    int width = w.R - w.L, height = w.B - w.T;
    using (var bmp = new Bitmap(width, height, PixelFormat.Format32bppArgb)) {
      using (var g = Graphics.FromImage(bmp)) {
        var dc = g.GetHdc();
        PrintWindow(h, dc, 2);
        g.ReleaseHdc(dc);
      }
      bmp.Save(path, ImageFormat.Png);
    }
    return string.Format("{0}x{1} client {2}x{3} dpi {4}", width, height, c.R, c.B, GetDpiForWindow(h));
  }
}
