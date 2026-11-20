# Mouse-style background input for a point within a known application window.
if (-not ('VortexBackgroundMouse' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
public static class VortexBackgroundMouse {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; public POINT(int x, int y) { X=x; Y=y; } }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll", SetLastError=true)] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", SetLastError=true)] static extern bool ScreenToClient(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] static extern IntPtr ChildWindowFromPointEx(IntPtr h, POINT p, uint flags);
  [DllImport("user32.dll", SetLastError=true)] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  public static void Click(IntPtr root, int x, int y) {
    RECT rect;
    if (root == IntPtr.Zero || !GetWindowRect(root, out rect) || x < rect.Left || x >= rect.Right || y < rect.Top || y >= rect.Bottom)
      throw new InvalidOperationException("Click point is outside the target window.");
    IntPtr target = root;
    for (int i=0; i<16; i++) {
      POINT local = new POINT(x,y);
      if (!ScreenToClient(target, ref local)) throw new InvalidOperationException("Could not map click point.");
      IntPtr child = ChildWindowFromPointEx(target, local, 7);
      if (child == IntPtr.Zero || child == target) break;
      target = child;
    }
    POINT point = new POINT(x,y);
    if (!ScreenToClient(target, ref point)) throw new InvalidOperationException("Could not map target point.");
    if (point.X < -32768 || point.X > 32767 || point.Y < -32768 || point.Y > 32767)
      throw new InvalidOperationException("Target coordinates are out of range.");
    int packed = (point.X & 0xffff) | ((point.Y & 0xffff) << 16);
    IntPtr pos = new IntPtr(packed);
    if (!PostMessage(target, 0x0200, IntPtr.Zero, pos)) throw new InvalidOperationException("Mouse move could not be posted.");
    if (!PostMessage(target, 0x0201, new IntPtr(1), pos)) throw new InvalidOperationException("Mouse down could not be posted.");
    Thread.Sleep(35);
    if (!PostMessage(target, 0x0202, IntPtr.Zero, pos)) throw new InvalidOperationException("Mouse up could not be posted.");
  }
}
'@
}
function Send-BackgroundMouseClick([IntPtr]$WindowHandle, [int]$ScreenX, [int]$ScreenY) {
  [VortexBackgroundMouse]::Click($WindowHandle, $ScreenX, $ScreenY)
}
