# Generates the colored tray icon variants from app/assets/tray/tray.png.
# The source alpha channel is preserved exactly; only the RGB of pixels
# with alpha > 0 is replaced with the variant color.
#
# Usage: powershell -ExecutionPolicy Bypass -File tool/tray_icons.ps1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$trayDir = Join-Path $repoRoot 'app\assets\tray'
$sourcePath = Join-Path $trayDir 'tray.png'

$variants = @(
    [pscustomobject]@{ Name = 'tray_ok.png';   R = 61;  G = 220; B = 151 },
    [pscustomobject]@{ Name = 'tray_warn.png'; R = 245; G = 196; B = 81  },
    [pscustomobject]@{ Name = 'tray_crit.png'; R = 255; G = 107; B = 107 }
)

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Source icon not found: $sourcePath"
}

$source = [System.Drawing.Bitmap]::FromFile($sourcePath)
try {
    foreach ($variant in $variants) {
        $target = New-Object System.Drawing.Bitmap(
            $source.Width,
            $source.Height,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        try {
            for ($y = 0; $y -lt $source.Height; $y++) {
                for ($x = 0; $x -lt $source.Width; $x++) {
                    $pixel = $source.GetPixel($x, $y)
                    if ($pixel.A -gt 0) {
                        $target.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($pixel.A, $variant.R, $variant.G, $variant.B))
                    }
                    else {
                        $target.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 0, 0, 0))
                    }
                }
            }

            $outPath = Join-Path $trayDir $variant.Name
            $target.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
            Write-Host "wrote $outPath"
        }
        finally {
            $target.Dispose()
        }
    }
}
finally {
    $source.Dispose()
}

# --- Verification -------------------------------------------------------
$allPassed = $true

foreach ($variant in $variants) {
    $path = Join-Path $trayDir $variant.Name
    $image = [System.Drawing.Bitmap]::FromFile($path)
    try {
        $dimsOk = ($image.Width -eq 64 -and $image.Height -eq 64)
        $formatOk = ($image.PixelFormat -eq [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

        $corners = @(
            $image.GetPixel(0, 0),
            $image.GetPixel($image.Width - 1, 0),
            $image.GetPixel(0, $image.Height - 1),
            $image.GetPixel($image.Width - 1, $image.Height - 1)
        )
        $cornersOk = ($corners | Where-Object { $_.A -eq 0 }).Count -eq 4

        $colorFound = $false
        for ($y = 0; $y -lt $image.Height -and -not $colorFound; $y++) {
            for ($x = 0; $x -lt $image.Width; $x++) {
                $pixel = $image.GetPixel($x, $y)
                if ($pixel.A -eq 255 -and $pixel.R -eq $variant.R -and $pixel.G -eq $variant.G -and $pixel.B -eq $variant.B) {
                    $colorFound = $true
                    break
                }
            }
        }

        $passed = $dimsOk -and $formatOk -and $cornersOk -and $colorFound
        if (-not $passed) { $allPassed = $false }

        $status = if ($passed) { 'PASS' } else { 'FAIL' }
        Write-Host ("{0}: {1}x{2} {3} | 32bppARGB={4} | cornersAlpha0={5} | targetRGB(#{6:X2}{7:X2}{8:X2})Alpha255={9} => {10}" -f `
            $variant.Name, $image.Width, $image.Height, $image.PixelFormat, $formatOk, $cornersOk, $variant.R, $variant.G, $variant.B, $colorFound, $status)
    }
    finally {
        $image.Dispose()
    }
}

if (-not $allPassed) {
    throw 'Tray icon verification failed.'
}
