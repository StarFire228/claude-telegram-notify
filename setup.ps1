# Настройка из консоли (то же самое умеет окно settings.cmd):
#  1) проверяет токен бота;
#  2) находит твой chat_id по сообщению боту;
#  3) прописывает хуки Stop и Notification в ~/.claude/settings.json;
#  4) шлёт тестовое уведомление.
param(
    [string]$SettingsPath = (Join-Path $env:USERPROFILE ".claude\settings.json")
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib.ps1")

$cfg = Read-NotifyConfig
if (-not $cfg.bot_token) {
    Write-Host "Впиши токен бота в config.json (поле bot_token) или открой окно настроек settings.cmd." -ForegroundColor Yellow
    exit 1
}

Write-Host "Проверяю токен..."
$botName = Get-BotName $cfg.bot_token $cfg.proxy
if (-not $botName) {
    Write-Host "Telegram не принял токен или недоступен." -ForegroundColor Red
    Write-Host "Если Telegram не открывается без VPN, впиши в config.json proxy, например socks5h://127.0.0.1:10808"
    exit 1
}
Write-Host "Бот найден: @$botName" -ForegroundColor Green

if (-not $cfg.chat_id) {
    $chat = Find-BotChat $cfg.bot_token $cfg.proxy
    if (-not $chat) {
        Write-Host "Не вижу сообщений боту. Открой https://t.me/$botName, нажми Start и запусти setup ещё раз." -ForegroundColor Yellow
        exit 1
    }
    $cfg.chat_id = [string]$chat.id
    Save-NotifyConfig $cfg
    Write-Host "chat_id сохранён: $($chat.id)" -ForegroundColor Green
} else {
    Write-Host "chat_id уже задан: $($cfg.chat_id)"
}

if (Register-NotifyHooks $SettingsPath) {
    Write-Host "Хуки прописаны в $SettingsPath (старая версия сохранена как .bak)" -ForegroundColor Green
} else {
    Write-Host "Хуки уже прописаны в $SettingsPath"
}

Write-Host (Send-TestNotification)
Write-Host "Проверь Telegram. Подробности в notify.log."
