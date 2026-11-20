# Genera los iconos de RealPhone para iOS a partir de la corona de la app Android.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File ios\marca\generar_iconos.ps1
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Resolve-Path (Join-Path $Here "..\..")
$Crown = [System.Drawing.Image]::FromFile((Join-Path $Root "engine-src\integracion\realphone\src\main\res\drawable-nodpi\crown_logo.png"))

# Fondo RP.Black de Theme.kt
$Black = [System.Drawing.Color]::FromArgb(255, 5, 7, 6)

function New-Icon([int]$size, [string]$name, [string]$mode) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    if ($mode -eq "opaque") { $g.Clear($Black) } else { $g.Clear([System.Drawing.Color]::Transparent) }
    # La corona ocupa el 62 % del ancho: queda dentro de la zona segura de la máscara redondeada de iOS
    $w = [int]($size * 0.62)
    $h = [int]($w * $Crown.Height / $Crown.Width)
    $rect = New-Object System.Drawing.Rectangle([int](($size - $w) / 2), [int](($size - $h) / 2), $w, $h)
    $attrs = New-Object System.Drawing.Imaging.ImageAttributes
    if ($mode -eq "mono") {
        # Silueta blanca con el alfa original, para el modo de iconos tintados de iOS 18
        $m = New-Object System.Drawing.Imaging.ColorMatrix
        $m.Matrix00 = 0; $m.Matrix11 = 0; $m.Matrix22 = 0
        $m.Matrix40 = 1; $m.Matrix41 = 1; $m.Matrix42 = 1
        $m.Matrix33 = 1; $m.Matrix44 = 1
        $attrs.SetColorMatrix($m)
    }
    $g.DrawImage($Crown, $rect, 0, 0, $Crown.Width, $Crown.Height, [System.Drawing.GraphicsUnit]::Pixel, $attrs)
    $g.Dispose()
    $bmp.Save((Join-Path $Here $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "  $name ($size px)"
}

function New-Logo([int]$width, [string]$name) {
    $h = [int]($width * $Crown.Height / $Crown.Width)
    $bmp = New-Object System.Drawing.Bitmap($width, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($Crown, 0, 0, $width, $h)
    $g.Dispose()
    $bmp.Save((Join-Path $Here $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "  $name (${width}x$h px)"
}

Write-Host "Iconos de RealPhone para iOS:"
New-Icon 1024 "AppIcon-1024.png" "opaque"
New-Icon 1024 "AppIcon-1024-Transparent.png" "transparent"
New-Icon 1024 "AppIcon-1024-Mono.png" "mono"
New-Icon 120 "AppIcon-120.png" "opaque"
New-Icon 152 "AppIcon-152.png" "opaque"
# Logo de la barra del menú: 40 pt de ancho a @3x
New-Logo 120 "AppLogo@3x.png"
# Corona de la pantalla de acceso: 88 pt de ancho a @3x
New-Logo 264 "RPCrown@3x.png"
$Crown.Dispose()
