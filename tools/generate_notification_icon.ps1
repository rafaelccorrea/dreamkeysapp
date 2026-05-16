# Gera o ícone branco monocromático para a notificação Android (small icon).
#
# Android exige que o ícone pequeno da notificação seja uma silhueta branca
# com fundo transparente — o sistema aplica o tint (cor da marca) por cima.
# Se mandar um PNG colorido, o Android Material desenha um quadradinho
# branco genérico em vez do logo. Aí fica feio em qualquer telefone moderno.
#
# Este script lê `drawable-*/ic_launcher_foreground.png` (logo Intellisys
# já isolada em transparente) e gera `drawable-*/ic_notification.png` na
# mesma resolução, recolorindo cada pixel não-transparente para branco puro
# e preservando o alpha original (anti-aliasing nas bordas continua suave).
#
# Roda no Windows com PowerShell — não precisa de Sharp/Jimp/ImageMagick.

Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$resRoot = Join-Path $repoRoot 'android\app\src\main\res'

$buckets = @(
    @{ Source = 'drawable-mdpi';    Target = 'drawable-mdpi' }
    @{ Source = 'drawable-hdpi';    Target = 'drawable-hdpi' }
    @{ Source = 'drawable-xhdpi';   Target = 'drawable-xhdpi' }
    @{ Source = 'drawable-xxhdpi';  Target = 'drawable-xxhdpi' }
    @{ Source = 'drawable-xxxhdpi'; Target = 'drawable-xxxhdpi' }
)

foreach ($b in $buckets) {
    $srcPath = Join-Path (Join-Path $resRoot $b.Source) 'ic_launcher_foreground.png'
    $dstPath = Join-Path (Join-Path $resRoot $b.Target) 'ic_notification.png'

    if (-not (Test-Path $srcPath)) {
        Write-Warning "skip: $srcPath não existe"
        continue
    }

    $bmp = [System.Drawing.Bitmap]::FromFile($srcPath)
    $w = $bmp.Width
    $h = $bmp.Height

    # Trabalhar numa cópia do mesmo tamanho com canal alpha
    $out = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $srcData = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $dstData = $out.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

    $byteCount = $srcData.Stride * $h
    $buffer = New-Object Byte[] $byteCount
    [System.Runtime.InteropServices.Marshal]::Copy($srcData.Scan0, $buffer, 0, $byteCount)

    # Format32bppArgb em little-endian: bytes B,G,R,A por pixel.
    # Recolore: B=G=R=255 (branco puro), mantém A.
    for ($i = 0; $i -lt $byteCount; $i += 4) {
        $a = $buffer[$i + 3]
        if ($a -eq 0) {
            # transparente — mantém zerado para evitar pixels brancos invisíveis
            $buffer[$i]     = 0
            $buffer[$i + 1] = 0
            $buffer[$i + 2] = 0
        } else {
            $buffer[$i]     = 255
            $buffer[$i + 1] = 255
            $buffer[$i + 2] = 255
        }
    }

    [System.Runtime.InteropServices.Marshal]::Copy($buffer, 0, $dstData.Scan0, $byteCount)
    $out.UnlockBits($dstData)
    $bmp.UnlockBits($srcData)

    $out.Save($dstPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $out.Dispose()
    $bmp.Dispose()

    Write-Host "✅ $($b.Target)/ic_notification.png  ($($w)x$($h))"
}

Write-Host ""
Write-Host "Pronto. Atualize app_push_service.dart para usar 'ic_notification' como"
Write-Host "small icon do canal e do AndroidNotificationDetails."
