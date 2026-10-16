$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$brandRoot = Split-Path $PSScriptRoot -Parent
$assetRoot = Join-Path $brandRoot 'branding'
$iconSource = [System.Drawing.Image]::FromFile((Join-Path $assetRoot 'usce-app-icon.png'))
$frames = @{}
foreach ($size in @(16,32,48,64,128,256,512,1024)) {
    $bitmap = [System.Drawing.Bitmap]::new($size,$size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.DrawImage($iconSource,0,0,$size,$size)
    $stream = [System.IO.MemoryStream]::new()
    $bitmap.Save($stream,[System.Drawing.Imaging.ImageFormat]::Png)
    $frames[$size] = $stream.ToArray()
    [System.IO.File]::WriteAllBytes((Join-Path $brandRoot "icons/usce-icon_$size.png"),$frames[$size])
    $graphics.Dispose(); $bitmap.Dispose(); $stream.Dispose()
}
$iconSource.Dispose()
[System.IO.File]::WriteAllBytes((Join-Path $brandRoot 'game/resources/icons/usce-icon.png'),$frames[512])
$icoSizes = @(16,32,48,64,128,256)
$ico = [System.IO.MemoryStream]::new()
$writer = [System.IO.BinaryWriter]::new($ico)
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$icoSizes.Count)
$offset = 6 + 16*$icoSizes.Count
foreach ($size in $icoSizes) {
    $dimension = if ($size -eq 256) {0} else {$size}
    $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
    $writer.Write([byte]0); $writer.Write([byte]0)
    $writer.Write([uint16]1); $writer.Write([uint16]32)
    $writer.Write([uint32]$frames[$size].Length); $writer.Write([uint32]$offset)
    $offset += $frames[$size].Length
}
foreach ($size in $icoSizes) {$writer.Write([byte[]]$frames[$size])}
$writer.Flush()
[System.IO.File]::WriteAllBytes((Join-Path $brandRoot 'icons/usce.ico'),$ico.ToArray())
[System.IO.File]::WriteAllBytes((Join-Path $brandRoot 'installer/install.ico'),$ico.ToArray())
[System.IO.File]::WriteAllBytes((Join-Path $brandRoot 'installer/uninstall.ico'),$ico.ToArray())
$writer.Dispose(); $ico.Dispose()

function Write-BigEndian($stream,[int]$number) {
    $bytes = [System.BitConverter]::GetBytes($number)
    [Array]::Reverse($bytes)
    $stream.Write($bytes,0,4)
}
$icns = [System.IO.MemoryStream]::new()
$icns.Write([System.Text.Encoding]::ASCII.GetBytes('icns'),0,4)
$chunks = @{16='icp4';32='icp5';64='icp6';128='ic07';256='ic08';512='ic09';1024='ic10'}
$length = 8
foreach ($size in $chunks.Keys) {$length += 8+$frames[$size].Length}
Write-BigEndian $icns $length
foreach ($size in @($chunks.Keys | Sort-Object)) {
    $icns.Write([System.Text.Encoding]::ASCII.GetBytes($chunks[$size]),0,4)
    Write-BigEndian $icns (8+$frames[$size].Length)
    $icns.Write($frames[$size],0,$frames[$size].Length)
}
[System.IO.File]::WriteAllBytes((Join-Path $brandRoot 'icons/usce.icns'),$icns.ToArray())
$icns.Dispose()

function Convert-BrandBitmap($source,$target,[int]$width,[int]$height,$background) {
    $image=[System.Drawing.Image]::FromFile($source)
    $bitmap=[System.Drawing.Bitmap]::new($width,$height,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics=[System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.ColorTranslator]::FromHtml($background))
    $graphics.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $ratio=[Math]::Min($width/$image.Width,$height/$image.Height)
    $w=[int]($image.Width*$ratio); $h=[int]($image.Height*$ratio)
    $graphics.DrawImage($image,[int](($width-$w)/2),[int](($height-$h)/2),$w,$h)
    $bitmap.Save($target,[System.Drawing.Imaging.ImageFormat]::Bmp)
    $graphics.Dispose(); $bitmap.Dispose(); $image.Dispose()
}
Convert-BrandBitmap (Join-Path $assetRoot 'usce-logo-horizontal.png') (Join-Path $brandRoot 'installer/dependencies/images/header.bmp') 150 57 '#FFFFFF'
Convert-BrandBitmap (Join-Path $assetRoot 'usce-installer-sidebar.png') (Join-Path $brandRoot 'installer/dependencies/images/side.bmp') 328 628 '#030A24'
Write-Output 'Packaged USCE PNG, ICO, ICNS and installer BMP assets.'
