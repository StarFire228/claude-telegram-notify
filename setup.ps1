# Первичная настройка:
#  1) проверяет токен бота;
#  2) находит твой chat_id по сообщению боту;
#  3) прописывает хуки Stop и Notification в ~/.claude/settings.json;
#  4) шлёт тестовое уведомление.
param(
    [string]$SettingsPath = (Join-Path $env:USERPROFILE ".claude\settings.json")
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgPath = Join-Path $here "config.json"

if (-not (Test-Path $cfgPath)) {
    Copy-Item (Join-Path $here "config.example.json") $cfgPath
    Write-Host "Создан config.json. Впиши в него токен бота (поле bot_token) и запусти setup ещё раз." -ForegroundColor Yellow
    exit 1
}
$cfgText = Get-Content $cfgPath -Raw -Encoding UTF8
$cfg = $cfgText | ConvertFrom-Json

if (-not $cfg.bot_token -or $cfg.bot_token -like "*ВСТАВЬ*") {
    Write-Host "Сначала впиши токен бота в config.json (поле bot_token)." -ForegroundColor Yellow
    exit 1
}

$curl = "$env:SystemRoot\System32\curl.exe"
$curlArgs = @("-s", "-m", "15")
if ($cfg.proxy) { $curlArgs += @("-x", [string]$cfg.proxy) }

# --- 1. токен ---
Write-Host "Проверяю токен..."
$me = (& $curl @curlArgs "https://api.telegram.org/bot$($cfg.bot_token)/getMe") -join ""
if ($me -notmatch '"ok":true') {
    Write-Host "Telegram не принял токен или недоступен: $me" -ForegroundColor Red
    Write-Host "Если Telegram не открывается без VPN — впиши в config.json proxy, например socks5h://127.0.0.1:10808"
    exit 1
}
$botName = ($me | ConvertFrom-Json).result.username
Write-Host "Бот найден: @$botName" -ForegroundColor Green

# --- 2. chat_id ---
if (-not $cfg.chat_id) {
    $upd = ((& $curl @curlArgs "https://api.telegram.org/bot$($cfg.bot_token)/getUpdates") -join "") | ConvertFrom-Json
    $chat = $null
    foreach ($u in @($upd.result)) {
        if ($u.message -and $u.message.chat.type -eq "private") { $chat = $u.message.chat }
    }
    if (-not $chat) {
        Write-Host "Не вижу сообщений боту. Открой https://t.me/$botName, нажми Start (или напиши что угодно) и запусти setup ещё раз." -ForegroundColor Yellow
        exit 1
    }
    $cfgText = $cfgText -replace '"chat_id"\s*:\s*"[^"]*"', ('"chat_id": "' + $chat.id + '"')
    [IO.File]::WriteAllText($cfgPath, $cfgText, (New-Object Text.UTF8Encoding($false)))
    Write-Host "chat_id сохранён: $($chat.id)" -ForegroundColor Green
} else {
    Write-Host "chat_id уже задан: $($cfg.chat_id)"
}

# --- 3. хуки Claude Code ---
$notify = Join-Path $here "notify.ps1"
function New-HookEntry([string]$evt) {
    [pscustomobject]@{ hooks = @([pscustomobject]@{
        type    = "command"
        command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$notify`" -Event $evt"
        timeout = 30
    }) }
}

if (Test-Path $SettingsPath) {
    $raw = Get-Content $SettingsPath -Raw -Encoding UTF8
    $settings = if ($raw.Trim()) { $raw | ConvertFrom-Json } else { [pscustomobject]@{} }
    Copy-Item $SettingsPath "$SettingsPath.bak" -Force
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
        $list += New-HookEntry $evt
        if ($settings.hooks.PSObject.Properties[$evt]) { $settings.hooks.$evt = $list }
        else { $settings.hooks | Add-Member -NotePropertyName $evt -NotePropertyValue $list }
        $changed = $true
    }
}
if ($changed) {
    $json = $settings | ConvertTo-Json -Depth 32
    [IO.File]::WriteAllText($SettingsPath, $json, (New-Object Text.UTF8Encoding($false)))
    Write-Host "Хуки прописаны в $SettingsPath (старая версия — .bak)" -ForegroundColor Green
} else {
    Write-Host "Хуки уже прописаны в $SettingsPath"
}

# --- 4. тест ---
& $notify -Test
Write-Host "Тестовое сообщение отправлено — проверь Telegram. Подробности в notify.log."
