# Уведомления Claude Code в Telegram, когда тебя нет за компьютером.
# Запускается хуками Stop и Notification из ~/.claude/settings.json.
# Данные события приходят JSON-ом на stdin.
param(
    [string]$Event = "Stop",
    [switch]$Test
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $here "notify.log"

function Write-Log([string]$text) {
    try {
        $line = "{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f (Get-Date), $Event, $text
        Add-Content -Path $logFile -Value $line -Encoding UTF8
    } catch {}
}

try {
    # --- настройки ---
    $cfgPath = Join-Path $here "config.json"
    if (-not (Test-Path $cfgPath)) { Write-Log "нет config.json"; exit 0 }
    $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $cfg.enabled -and -not $Test) { exit 0 }
    if (-not $cfg.bot_token -or $cfg.bot_token -like "*ВСТАВЬ*") { Write-Log "не задан bot_token"; exit 0 }
    if (-not $cfg.chat_id) { Write-Log "не задан chat_id — запусти setup.cmd"; exit 0 }

    # --- данные хука ---
    $hook = $null
    if (-not $Test) {
        try {
            $stdin = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [Text.Encoding]::UTF8)
            $raw = $stdin.ReadToEnd()
            if ($raw) { $hook = $raw | ConvertFrom-Json }
        } catch { Write-Log "не разобрал stdin: $_" }
    }

    # Уведомление «ждёт ввода больше минуты» дублирует Stop — пропускаем.
    if ($Event -eq "Notification" -and $hook -and $hook.notification_type -eq "idle_prompt") { exit 0 }

    # --- ты за компьютером? ---
    Add-Type -Namespace ClaudeNotify -Name Idle -MemberDefinition @"
[StructLayout(LayoutKind.Sequential)]
public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
[DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
public static uint IdleMs() {
    LASTINPUTINFO i = new LASTINPUTINFO();
    i.cbSize = (uint)Marshal.SizeOf(i);
    GetLastInputInfo(ref i);
    return (uint)Environment.TickCount - i.dwTime;
}
"@
    $idleSec = [math]::Round([ClaudeNotify.Idle]::IdleMs() / 1000)
    $threshold = [int]$cfg.idle_minutes * 60
    if (-not $Test -and $idleSec -lt $threshold) {
        Write-Log "ты за компьютером (бездействие $idleSec c) — не отправляю"
        exit 0
    }

    # --- текст ---
    $folder = ""
    if ($hook -and $hook.cwd) { $folder = Split-Path -Leaf $hook.cwd }

    $body = ""
    if ($Test) {
        $title = "🔔 Тест: уведомления Claude работают"
    } elseif ($Event -eq "Notification") {
        $title = "⚠️ Нужен твой ответ"
        if ($hook.message) { $body = [string]$hook.message }
    } else {
        $title = "✅ Готово"
        # последний ответ Claude: сначала из поля хука, иначе из файла переписки
        if ($hook.last_assistant_message) {
            $body = [string]$hook.last_assistant_message
        } elseif ($hook.transcript_path -and (Test-Path $hook.transcript_path)) {
            $lines = Get-Content $hook.transcript_path -Tail 200 -Encoding UTF8
            for ($k = $lines.Count - 1; $k -ge 0 -and -not $body; $k--) {
                try { $o = $lines[$k] | ConvertFrom-Json } catch { continue }
                if ($o.type -ne "assistant") { continue }
                foreach ($c in @($o.message.content)) {
                    if ($c.type -eq "text" -and $c.text.Trim()) { $body = $c.text; break }
                }
            }
        }
    }
    if ($folder) { $title = "$title · $folder" }

    $max = [int]$cfg.max_chars
    if ($max -le 0) { $max = 600 }
    $body = $body.Trim()
    if ($body.Length -gt $max) { $body = $body.Substring(0, $max) + "…" }
    $text = if ($body) { "$title`n`n$body" } else { $title }

    # --- отправка (через curl.exe: умеет прокси, в т.ч. socks5h) ---
    $payload = @{ chat_id = "$($cfg.chat_id)"; text = $text; disable_web_page_preview = $true } | ConvertTo-Json -Compress
    $tmp = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllText($tmp, $payload, (New-Object Text.UTF8Encoding($false)))
    $curlArgs = @("-s", "-m", "15", "-H", "Content-Type: application/json", "--data-binary", "@$tmp")
    if ($cfg.proxy) { $curlArgs += @("-x", [string]$cfg.proxy) }
    $curlArgs += "https://api.telegram.org/bot$($cfg.bot_token)/sendMessage"
    $resp = & "$env:SystemRoot\System32\curl.exe" @curlArgs
    Remove-Item $tmp -ErrorAction SilentlyContinue

    if ($resp -match '"ok":true') { Write-Log "отправлено (бездействие $idleSec c)" }
    else { Write-Log "Telegram не принял: $resp" }
} catch {
    Write-Log "ошибка: $_"
}
exit 0
