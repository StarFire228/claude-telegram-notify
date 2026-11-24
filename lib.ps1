# Общие функции для setup.ps1 и settings.ps1 (окна настроек).
$script:NotifyDir = $PSScriptRoot
$script:CfgPath = Join-Path $PSScriptRoot "config.json"
$script:DefaultSettingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"

function Read-NotifyConfig {
    if (-not (Test-Path $script:CfgPath)) {
        Copy-Item (Join-Path $script:NotifyDir "config.example.json") $script:CfgPath
    }
    $c = Get-Content $script:CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($c.bot_token -like "*ВСТАВЬ*") { $c.bot_token = "" }
    return $c
}

function Save-NotifyConfig($c) {
    $q = { param($s) '"' + ([string]$s -replace '\\', '\\' -replace '"', '\"') + '"' }
    $text = "{`n" +
        "  `"enabled`": $(([bool]$c.enabled).ToString().ToLower()),`n" +
        "  `"bot_token`": $(& $q $c.bot_token),`n" +
        "  `"chat_id`": $(& $q $c.chat_id),`n" +
        "  `"idle_minutes`": $([int]$c.idle_minutes),`n" +
        "  `"max_chars`": $([int]$c.max_chars),`n" +
        "  `"proxy`": $(& $q $c.proxy)`n}`n"
    [IO.File]::WriteAllText($script:CfgPath, $text, (New-Object Text.UTF8Encoding($false)))
}

# Вызов Telegram Bot API через curl.exe (умеет прокси). Возвращает разобранный JSON или $null.
function Invoke-TgApi([string]$token, [string]$proxy, [string]$method) {
    $a = @("-s", "-m", "15")
    if ($proxy) { $a += @("-x", $proxy) }
    $a += "https://api.telegram.org/bot$token/$method"
    $raw = (& "$env:SystemRoot\System32\curl.exe" @a) -join ""
    if (-not $raw) { return $null }
    try { return $raw | ConvertFrom-Json } catch { return $null }
}

# Имя бота или $null, если токен не принят / Telegram недоступен.
function Get-BotName([string]$token, [string]$proxy) {
    $r = Invoke-TgApi $token $proxy "getMe"
    if ($r -and $r.ok) { return $r.result.username }
    return $null
}

# Последний личный чат, написавший боту, или $null.
function Find-BotChat([string]$token, [string]$proxy) {
    $r = Invoke-TgApi $token $proxy "getUpdates"
    $chat = $null
    foreach ($u in @($r.result)) {
        if ($u.message -and $u.message.chat.type -eq "private") { $chat = $u.message.chat }
    }
    return $chat
}

function Test-HooksRegistered([string]$SettingsPath = $script:DefaultSettingsPath) {
    if (-not (Test-Path $SettingsPath)) { return $false }
    try { $s = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $false }
    if (-not $s -or -not $s.hooks) { return $false }
    foreach ($evt in "Stop", "Notification") {
        $found = @($s.hooks.$evt) | Where-Object { $_.hooks | Where-Object { $_.command -like "*notify.ps1*" } }
        if (-not $found) { return $false }
    }
    return $true
}

# Дописывает хуки Stop и Notification в settings.json Claude Code, не трогая остальное.
# Возвращает $true, если файл изменён.
function Register-NotifyHooks([string]$SettingsPath = $script:DefaultSettingsPath) {
    $notify = Join-Path $script:NotifyDir "notify.ps1"
    if (Test-Path $SettingsPath) {
        $raw = Get-Content $SettingsPath -Raw -Encoding UTF8
        $settings = if ($raw.Trim()) { $raw | ConvertFrom-Json } else { [pscustomobject]@{} }
    } else {
        New-Item -ItemType Directory -Force (Split-Path $SettingsPath) | Out-Null
        $settings = [pscustomobject]@{}
    }
    if (-not $settings.PSObject.Properties["hooks"]) {
        $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
    }
    $changed = $false
    foreach ($evt in "Stop", "Notification") {
        $list = @()
        if ($settings.hooks.PSObject.Properties[$evt]) { $list = @($settings.hooks.$evt) }
        $already = $list | Where-Object { $_.hooks | Where-Object { $_.command -like "*notify.ps1*" } }
        if (-not $already) {
            $list += [pscustomobject]@{ hooks = @([pscustomobject]@{
                type    = "command"
                command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$notify`" -Event $evt"
                timeout = 30
            }) }
            if ($settings.hooks.PSObject.Properties[$evt]) { $settings.hooks.$evt = $list }
            else { $settings.hooks | Add-Member -NotePropertyName $evt -NotePropertyValue $list }
            $changed = $true
        }
    }
    if ($changed) {
        if (Test-Path $SettingsPath) { Copy-Item $SettingsPath "$SettingsPath.bak" -Force }
        $json = $settings | ConvertTo-Json -Depth 32
        [IO.File]::WriteAllText($SettingsPath, $json, (New-Object Text.UTF8Encoding($false)))
    }
    return $changed
}

# Отправляет тестовое сообщение. Возвращает последнюю строку notify.log.
function Send-TestNotification {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:NotifyDir "notify.ps1") -Test | Out-Null
    $log = Join-Path $script:NotifyDir "notify.log"
    if (Test-Path $log) { return (Get-Content $log -Tail 1 -Encoding UTF8) }
    return ""
}
