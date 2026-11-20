$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System.Windows.Forms;
public class MouseProbeControl : Control {
  public int Downs, Ups, LastX, LastY;
  protected override void WndProc(ref Message m) {
    if (m.Msg == 0x201) { Downs++; LastX = (short)((long)m.LParam & 65535); LastY = (short)(((long)m.LParam >> 16) & 65535); }
    if (m.Msg == 0x202) Ups++;
    base.WndProc(ref m);
  }
}
'@
. (Join-Path $PSScriptRoot 'vortex-mouse.ps1')
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Vortex mouse click test'
$form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point(100, 100)
$form.Size = New-Object System.Drawing.Size(300, 180)
$button = New-Object MouseProbeControl
$button.Location = New-Object System.Drawing.Point(40, 40)
$button.Size = New-Object System.Drawing.Size(150, 45)
$form.Controls.Add($button)
try {
  $form.Show()
  [System.Windows.Forms.Application]::DoEvents()
  $center = $button.PointToScreen((New-Object System.Drawing.Point(75, 22)))
  Send-BackgroundMouseClick $form.Handle $center.X $center.Y
  $until = [DateTime]::UtcNow.AddSeconds(2)
  while ($button.Ups -lt 1 -and [DateTime]::UtcNow -lt $until) {
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 20
  }
  if ($button.Downs -ne 1 -or $button.Ups -ne 1 -or $button.LastX -ne 75 -or $button.LastY -ne 22) {
    throw "FAIL: mouse messages/coordinates incorrect: down=$($button.Downs), up=$($button.Ups), x=$($button.LastX), y=$($button.LastY)"
  }
  Write-Output 'PASS: background mouse messages reach the target at its current coordinates'
} finally { $form.Close(); $form.Dispose() }
