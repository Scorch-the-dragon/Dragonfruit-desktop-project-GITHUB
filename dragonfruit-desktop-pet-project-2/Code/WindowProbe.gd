# Windows-only, read-only window discovery. Embedded so exported games include it.
extends RefCounted

const SCRIPT = """
param([string]$OutputPath, [int]$PetProcess, [int]$Samples = 0)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class PetWindowProbe {
 public delegate bool Callback(IntPtr h, IntPtr p);
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
 [DllImport("user32.dll")] static extern bool EnumWindows(Callback cb, IntPtr p);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
 [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out Rect r, int n);
 [DllImport("dwmapi.dll", EntryPoint="DwmGetWindowAttribute")] static extern int GetCloaked(IntPtr h, int a, out int r, int n);
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
 public class Item { public string id; public int x,y,w,h; }
 public static List<Item> Read(int ownPid) {
  var result = new List<Item>();
  EnumWindows(delegate(IntPtr h, IntPtr p) {
   uint pid; GetWindowThreadProcessId(h, out pid);
   if (pid == ownPid || !IsWindowVisible(h) || IsIconic(h)) return true;
   int cloaked; if (GetCloaked(h,14,out cloaked,4)==0 && cloaked!=0) return true;
   var cls = new StringBuilder(256); GetClassName(h,cls,256);
   if (cls.ToString()=="Progman" || cls.ToString()=="WorkerW" || cls.ToString().Contains("TrayWnd")) return true;
   Rect r; if (DwmGetWindowAttribute(h,9,out r,16)!=0) return true;
   if(r.Right>r.Left && r.Bottom>r.Top) result.Add(new Item {id=h.ToInt64().ToString(), x=r.Left-GetSystemMetrics(76),y=r.Top-GetSystemMetrics(77),w=r.Right-r.Left,h=r.Bottom-r.Top});
   return true;
  },IntPtr.Zero);
  return result;
 }
}
'@
[PetWindowProbe]::SetProcessDPIAware() | Out-Null
while (Get-Process -Id $PetProcess -ErrorAction SilentlyContinue) {
 $items = @([PetWindowProbe]::Read($PetProcess))
 $json = ConvertTo-Json -InputObject $items -Compress
 [IO.File]::WriteAllText($OutputPath + '.tmp', $json)
 Move-Item -LiteralPath ($OutputPath + '.tmp') -Destination $OutputPath -Force
 if ($Samples -gt 0) { $Samples--; if ($Samples -eq 0) { break } }
 Start-Sleep -Milliseconds 250
}
"""
