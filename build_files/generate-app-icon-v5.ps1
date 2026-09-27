param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectRoot
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeIcon {
  [DllImport("user32.dll", CharSet=CharSet.Auto)]
  public static extern bool DestroyIcon(IntPtr handle);
}
"@

$srcDir = Join-Path $ProjectRoot "src"
New-Item -ItemType Directory -Force $srcDir | Out-Null
$out = Join-Path $srcDir "app.ico"

$size = 128
$bmp = New-Object System.Drawing.Bitmap $size,$size,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)

$bgRect = New-Object System.Drawing.Rectangle 6,6,116,116
$bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($bgRect,[System.Drawing.Color]::FromArgb(255,3,15,28),[System.Drawing.Color]::FromArgb(255,20,18,55),35)
$g.FillEllipse($bgBrush,6,6,116,116)

$outerGlow = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(110,38,225,255),8)
$outerGlow.Alignment = [System.Drawing.Drawing2D.PenAlignment]::Center
$g.DrawEllipse($outerGlow,9,9,110,110)

$outer = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,55,235,255),3)
$g.DrawEllipse($outer,10,10,108,108)

$mid = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(230,117,87,255),3)
$g.DrawEllipse($mid,28,28,72,72)

$inner = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210,56,193,255),2)
$g.DrawEllipse($inner,39,39,50,50)

$coreBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,126,91,255))
$g.FillEllipse($coreBrush,56,56,16,16)

$playPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$playPath.AddPolygon([System.Drawing.Point[]]@(
  (New-Object System.Drawing.Point 49,43),
  (New-Object System.Drawing.Point 49,85),
  (New-Object System.Drawing.Point 84,64)
))
$playBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(225,217,251,255))
$g.FillPath($playBrush,$playPath)

$shine = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(135,220,255,255),2)
$g.DrawArc($shine,18,18,92,92,205,105)

$hIcon = $bmp.GetHicon()
$icon = [System.Drawing.Icon]::FromHandle($hIcon)
$fs = [System.IO.File]::Open($out,[System.IO.FileMode]::Create)
$icon.Save($fs)
$fs.Close()

[NativeIcon]::DestroyIcon($hIcon) | Out-Null
$icon.Dispose(); $g.Dispose(); $bmp.Dispose()
$bgBrush.Dispose(); $outerGlow.Dispose(); $outer.Dispose(); $mid.Dispose(); $inner.Dispose(); $coreBrush.Dispose(); $playPath.Dispose(); $playBrush.Dispose(); $shine.Dispose()

if (-not (Test-Path $out)) { throw "app.ico was not generated" }
Write-Host "Generated app icon: $out"
