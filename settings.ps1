# Окно настроек уведомлений Claude Code в Telegram.
# -Snapshot <путь.png> — сохранить картинку окна и закрыть (для README и проверки).
param([string]$Snapshot)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib.ps1")

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace ClaudeNotify -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
[void][ClaudeNotify.Dpi]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()

$cfg = Read-NotifyConfig
$font = New-Object System.Drawing.Font("Segoe UI", 10)
$muted = [System.Drawing.Color]::FromArgb(110, 110, 110)
$green = [System.Drawing.Color]::FromArgb(30, 130, 60)
$red = [System.Drawing.Color]::FromArgb(180, 40, 40)

$form = New-Object System.Windows.Forms.Form
$form.Text = "Уведомления Claude в Telegram"
$form.Font = $font
$form.AutoScaleMode = "Dpi"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.StartPosition = "CenterScreen"
$form.AutoSize = $true
$form.AutoSizeMode = "GrowAndShrink"
$form.Padding = New-Object System.Windows.Forms.Padding(14)

$grid = New-Object System.Windows.Forms.TableLayoutPanel
$grid.ColumnCount = 3
$grid.AutoSize = $true
$grid.Dock = "Fill"
[void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("AutoSize")))
[void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 300)))
[void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("AutoSize")))
$form.Controls.Add($grid)

function New-Label([string]$text, $color = $null) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.AutoSize = $true
    $l.Anchor = "Left"
    $l.Margin = New-Object System.Windows.Forms.Padding(3, 8, 10, 8)
    if ($color) { $l.ForeColor = $color }
    return $l
}
function New-Button([string]$text) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.AutoSize = $true
    $b.Padding = New-Object System.Windows.Forms.Padding(6, 2, 6, 2)
    $b.Anchor = "Left"
    return $b
}
function Add-Row($label, $control, $button = $null) {
    $grid.Controls.Add($label)
    $grid.Controls.Add($control)
    if ($button) { $grid.Controls.Add($button) } else { $grid.Controls.Add((New-Label "")) }
}
function New-Inline($control, [string]$hint) {
    $p = New-Object System.Windows.Forms.FlowLayoutPanel
    $p.AutoSize = $true
    $p.WrapContents = $false
    $p.Margin = New-Object System.Windows.Forms.Padding(0)
    $control.Margin = New-Object System.Windows.Forms.Padding(3, 5, 3, 5)
    $p.Controls.Add($control)
    $p.Controls.Add((New-Label $hint $muted))
    return $p
}
function Add-Section([string]$title) {
    $l = New-Label $title
    $l.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $l.Margin = New-Object System.Windows.Forms.Padding(3, 14, 3, 4)
    $grid.Controls.Add($l)
    $grid.SetColumnSpan($l, 3)
}

# --- бот ---
Add-Section "Бот"
$tbToken = New-Object System.Windows.Forms.TextBox
$tbToken.Dock = "Fill"
$tbToken.UseSystemPasswordChar = $true
$tbToken.Text = $cfg.bot_token
$btnCheck = New-Button "Проверить"
Add-Row (New-Label "Токен") $tbToken $btnCheck

$cbShow = New-Object System.Windows.Forms.CheckBox
$cbShow.Text = "Показать токен"
$cbShow.AutoSize = $true
$cbShow.ForeColor = $muted
$cbShow.Add_CheckedChanged({ $tbToken.UseSystemPasswordChar = -not $cbShow.Checked })
$lblBot = New-Label "" $muted
Add-Row (New-Label "") $cbShow $lblBot

$lblChat = New-Label "" $muted
$btnChat = New-Button "Найти мой чат"
Add-Row (New-Label "Чат") $lblChat $btnChat

$tbProxy = New-Object System.Windows.Forms.TextBox
$tbProxy.Dock = "Fill"
$tbProxy.Text = $cfg.proxy
Add-Row (New-Label "Прокси") $tbProxy (New-Label "если нужен VPN" $muted)

# --- когда присылать ---
Add-Section "Когда присылать"
$cbEnabled = New-Object System.Windows.Forms.CheckBox
$cbEnabled.Text = "Уведомления включены"
$cbEnabled.AutoSize = $true
$cbEnabled.Checked = [bool]$cfg.enabled
Add-Row (New-Label "") $cbEnabled

$numIdle = New-Object System.Windows.Forms.NumericUpDown
$numIdle.Minimum = 0; $numIdle.Maximum = 120; $numIdle.Width = 70
$numIdle.Value = [math]::Min(120, [math]::Max(0, [int]$cfg.idle_minutes))
Add-Row (New-Label "Отошёл через, мин") (New-Inline $numIdle "без мыши и клавиатуры")

$numChars = New-Object System.Windows.Forms.NumericUpDown
$numChars.Minimum = 50; $numChars.Maximum = 3500; $numChars.Increment = 50; $numChars.Width = 70
$numChars.Value = [math]::Min(3500, [math]::Max(50, [int]$cfg.max_chars))
Add-Row (New-Label "Длина текста") (New-Inline $numChars "символов из ответа")

# --- Claude Code ---
Add-Section "Claude Code"
$lblHooks = New-Label ""
$btnHooks = New-Button "Подключить"
Add-Row (New-Label "Хуки") $lblHooks $btnHooks

# --- кнопки снизу ---
$bottom = New-Object System.Windows.Forms.FlowLayoutPanel
$bottom.AutoSize = $true
$bottom.Margin = New-Object System.Windows.Forms.Padding(0, 16, 0, 0)
$btnTest = New-Button "Отправить тест"
$btnLog = New-Button "Открыть лог"
$btnSave = New-Button "Сохранить"
$bottom.Controls.AddRange(@($btnSave, $btnTest, $btnLog))
$grid.Controls.Add($bottom)
$grid.SetColumnSpan($bottom, 3)

$lblStatus = New-Label "" $muted
$lblStatus.MaximumSize = New-Object System.Drawing.Size(560, 0)
$grid.Controls.Add($lblStatus)
$grid.SetColumnSpan($lblStatus, 3)

# --- логика ---
function Set-Status([string]$text, $color = $muted) { $lblStatus.Text = $text; $lblStatus.ForeColor = $color }

function Update-View {
    if ($cfg.chat_id) { $lblChat.Text = "найден"; $lblChat.ForeColor = $green }
    else { $lblChat.Text = "не найден: напиши боту Start"; $lblChat.ForeColor = $red }
    if (Test-HooksRegistered) {
        $lblHooks.Text = "подключены"; $lblHooks.ForeColor = $green; $btnHooks.Enabled = $false
    } else {
        $lblHooks.Text = "не подключены"; $lblHooks.ForeColor = $red; $btnHooks.Enabled = $true
    }
}

function Save-FromForm {
    $cfg.bot_token = $tbToken.Text.Trim()
    $cfg.proxy = $tbProxy.Text.Trim()
    $cfg.enabled = $cbEnabled.Checked
    $cfg.idle_minutes = [int]$numIdle.Value
    $cfg.max_chars = [int]$numChars.Value
    Save-NotifyConfig $cfg
}

function Invoke-Busy([scriptblock]$action) {
    $form.UseWaitCursor = $true
    [System.Windows.Forms.Application]::DoEvents()
    try { & $action } catch { Set-Status "Ошибка: $_" $red }
    finally { $form.UseWaitCursor = $false }
}

$btnCheck.Add_Click({ Invoke-Busy {
    Save-FromForm
    if (-not $cfg.bot_token) { Set-Status "Вставь токен от @BotFather." $red; return }
    $name = Get-BotName $cfg.bot_token $cfg.proxy
    if ($name) { $lblBot.Text = "@$name"; $lblBot.ForeColor = $green; Set-Status "Токен рабочий, бот @$name." $green }
    else { $lblBot.Text = "не принят"; $lblBot.ForeColor = $red; Set-Status "Telegram не принял токен или недоступен. Если нужен VPN, заполни прокси." $red }
} })

$btnChat.Add_Click({ Invoke-Busy {
    Save-FromForm
    if (-not $cfg.bot_token) { Set-Status "Сначала вставь токен." $red; return }
    $chat = Find-BotChat $cfg.bot_token $cfg.proxy
    if ($chat) {
        $cfg.chat_id = [string]$chat.id
        Save-NotifyConfig $cfg
        Set-Status "Чат найден: $($chat.first_name)." $green
    } else {
        Set-Status "Боту ещё никто не писал. Открой его в Telegram, нажми Start и попробуй снова." $red
    }
    Update-View
} })

$btnHooks.Add_Click({ Invoke-Busy {
    [void](Register-NotifyHooks)
    Set-Status "Хуки прописаны в настройках Claude Code. Заработают в новых сессиях." $green
    Update-View
} })

$btnTest.Add_Click({ Invoke-Busy {
    Save-FromForm
    if (-not $cfg.bot_token -or -not $cfg.chat_id) { Set-Status "Нужны токен и найденный чат." $red; return }
    $line = Send-TestNotification
    if ($line -match "отправлено") { Set-Status "Тест отправлен, проверь Telegram." $green }
    else { Set-Status "Не отправилось: $line" $red }
} })

$btnLog.Add_Click({
    $log = Join-Path $PSScriptRoot "notify.log"
    if (Test-Path $log) { Start-Process notepad.exe $log } else { Set-Status "Лог пока пуст." }
})

$btnSave.Add_Click({ Invoke-Busy { Save-FromForm; Set-Status "Сохранено." $green } })

Update-View
$form.ActiveControl = $btnSave
$form.Add_Shown({
    $form.Activate()
    if ($Snapshot) {
        [System.Windows.Forms.Application]::DoEvents()
        $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $bmp.Save($Snapshot, [System.Drawing.Imaging.ImageFormat]::Png)
        $form.Close()
    }
})
[void]$form.ShowDialog()
