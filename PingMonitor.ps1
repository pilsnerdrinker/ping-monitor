<#
================================================================
  PingMonitor.ps1  -  Ping quality checker (FF14 DC preset)
  - Save/reorder/monitor multiple IPs
  - -n (count) or -t (continuous) mode
  - Stop by button (no Ctrl+C)
  - Reorder with Up/Down; overlay follows the same order
  - Per-IP sparkline color (double-click a row to pick color)
  - Flicker-free overlay, auto-height for many rows
================================================================
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---- Preset (order matters; overlay follows this order) ----
$script:defaultColors = @(
    [System.Drawing.Color]::FromArgb(90,180,255),
    [System.Drawing.Color]::FromArgb(120,210,150),
    [System.Drawing.Color]::FromArgb(235,190,90),
    [System.Drawing.Color]::FromArgb(120,200,235),
    [System.Drawing.Color]::FromArgb(200,160,240),
    [System.Drawing.Color]::FromArgb(240,200,120)
)
$script:targets = [System.Collections.ArrayList]@(
    [pscustomobject]@{ Name='elemental'; Ip='119.252.36.6'; Color=$script:defaultColors[0]; Checked=$true }
    [pscustomobject]@{ Name='mana';      Ip='119.252.36.8'; Color=$script:defaultColors[1]; Checked=$true }
    [pscustomobject]@{ Name='gaia';      Ip='119.252.36.7'; Color=$script:defaultColors[2]; Checked=$true }
    [pscustomobject]@{ Name='meteor';    Ip='119.252.36.9'; Color=$script:defaultColors[3]; Checked=$true }
)

$script:monitors = @{}   # Ip -> @{ Name; Ip; Job; Samples; Times; Mode; Count }
$script:maxSamples = 30000   # ring buffer cap per IP

# ---- settings persistence (AppData) ----
$script:settingsDir  = Join-Path $env:APPDATA 'PingMonitor'
$script:settingsPath = Join-Path $script:settingsDir 'settings.json'
$script:loading = $false
$script:savedMode = $null
$script:savedCount = $null
$script:rbNRef = $null
$script:numNRef = $null
$script:rbTRef = $null

function Save-Settings {
    if ($script:loading) { return }
    try {
        if (-not (Test-Path $script:settingsDir)) { New-Item -ItemType Directory -Path $script:settingsDir -Force | Out-Null }
        $arr = @()
        foreach ($t in $script:targets) {
            $chk = if ($null -ne $t.PSObject.Properties['Checked']) { [bool]$t.Checked } else { $true }
            $arr += [pscustomobject]@{ Name=$t.Name; Ip=$t.Ip; Color=$t.Color.ToArgb(); Checked=$chk }
        }
        $mode = 't'; $count = 300
        if ($script:rbNRef -and $script:rbNRef.Checked) { $mode = 'n' }
        if ($script:numNRef) { $count = [int]$script:numNRef.Value }
        $obj = [pscustomobject]@{ targets=$arr; mode=$mode; count=$count }
        ($obj | ConvertTo-Json -Compress -Depth 5) | Set-Content -Path $script:settingsPath -Encoding UTF8
    } catch { }
}

function Load-Settings {
    try {
        if (-not (Test-Path $script:settingsPath)) { return $false }
        $json = Get-Content -Path $script:settingsPath -Raw -Encoding UTF8
        if (-not $json) { return $false }
        $data = $json | ConvertFrom-Json
        if (-not $data) { return $false }
        # new format: { targets:[...], mode, count } ; old format: [...] (array only)
        $items = $null
        if ($null -ne $data.PSObject.Properties['targets']) {
            $items = $data.targets
            if ($null -ne $data.PSObject.Properties['mode'])  { $script:savedMode  = [string]$data.mode }
            if ($null -ne $data.PSObject.Properties['count']) { $script:savedCount = [int]$data.count }
        } else {
            $items = $data
        }
        $script:targets.Clear()
        foreach ($d in @($items)) {
            $col = [System.Drawing.Color]::FromArgb([int]$d.Color)
            $chk = $true
            if ($null -ne $d.PSObject.Properties['Checked']) { $chk = [bool]$d.Checked }
            [void]$script:targets.Add([pscustomobject]@{ Name=$d.Name; Ip=$d.Ip; Color=$col; Checked=$chk })
        }
        return ($script:targets.Count -gt 0)
    } catch { return $false }
}
$script:chkAllReady = $false
$script:suppressAll = $false
$script:bulkCheck = $false

function Get-Verdict($loss, $max) {
    if ($loss -gt 0 -or $max -gt 200) { return @('BAD',      [System.Drawing.Color]::FromArgb(220,70,70)) }
    if ($max -ge 100)                 { return @('OK-ish',   [System.Drawing.Color]::FromArgb(220,170,40)) }
    if ($max -ge 20)                  { return @('GOOD',     [System.Drawing.Color]::FromArgb(70,180,90)) }
    return @('EXCELLENT', [System.Drawing.Color]::FromArgb(60,200,210))
}

function Get-RecentVerdict($samples, $win) {
    if ($samples.Count -eq 0) { return @('-', [System.Drawing.Color]::Gray) }
    $recent = @($samples | Select-Object -Last $win)
    $valid = @($recent | Where-Object { $_ -ge 0 })
    $lossN = @($recent | Where-Object { $_ -lt 0 }).Count
    $loss = if ($recent.Count) { [math]::Round(100*$lossN/$recent.Count) } else { 0 }
    $mx = if ($valid.Count) { ($valid | Measure-Object -Maximum).Maximum } else { 0 }
    return (Get-Verdict $loss $mx)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Ping Monitor - FF14 DC'
$form.Size = New-Object System.Drawing.Size(600, 470)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$list = New-Object System.Windows.Forms.ListView
$list.Location = New-Object System.Drawing.Point(12,12)
$list.Size = New-Object System.Drawing.Size(500,170)
$list.View = 'Details'
$list.FullRowSelect = $true
$list.CheckBoxes = $true
$list.OwnerDraw = $false
[void]$list.Columns.Add('Name',85)
[void]$list.Columns.Add('IP',120)
[void]$list.Columns.Add('State',60)
[void]$list.Columns.Add('Min',48)
[void]$list.Columns.Add('Max',48)
[void]$list.Columns.Add('Avg',48)
[void]$list.Columns.Add('Loss',44)
[void]$list.Columns.Add('Color',44)
$form.Controls.Add($list)
$list.Add_ItemChecked({
    param($src,$e)
    if (-not $script:chkAllReady) { return }
    # sync this item checked state back to its target
    $ip = $e.Item.SubItems[1].Text
    $t = $script:targets | Where-Object { $_.Ip -eq $ip } | Select-Object -First 1
    if ($t) {
        if ($null -ne $t.PSObject.Properties['Checked']) { $t.Checked = $e.Item.Checked }
        else { $t | Add-Member -NotePropertyName Checked -NotePropertyValue $e.Item.Checked -Force }
    }
    if ($script:bulkCheck) { return }
    $all = ($list.Items.Count -gt 0)
    foreach ($i in $list.Items) { if (-not $i.Checked) { $all = $false; break } }
    $script:suppressAll = $true
    $chkAll.Checked = $all
    $script:suppressAll = $false
    if (-not $script:loading) { Save-Settings }
})

# Up / Down reorder buttons
$btnUp = New-Object System.Windows.Forms.Button
$btnUp.Text = [char]0x2191  # up arrow
$btnUp.Location=New-Object System.Drawing.Point(520,12); $btnUp.Size=New-Object System.Drawing.Size(56,28)
$form.Controls.Add($btnUp)
$btnDown = New-Object System.Windows.Forms.Button
$btnDown.Text = [char]0x2193  # down arrow
$btnDown.Location=New-Object System.Drawing.Point(520,44); $btnDown.Size=New-Object System.Drawing.Size(56,28)
$form.Controls.Add($btnDown)

$script:firstFill = $true
function Refresh-List {
    $list.BeginUpdate()
    $checkedIps = @{}
    if ($script:firstFill) {
        foreach ($t in $script:targets) {
            $c = if ($null -ne $t.PSObject.Properties['Checked']) { [bool]$t.Checked } else { $true }
            if ($c) { $checkedIps[$t.Ip] = $true }
        }
        $script:firstFill = $false
    } else {
        foreach ($i in $list.CheckedItems) { $checkedIps[$i.SubItems[1].Text] = $true }
    }
    $selIp = $null
    if ($list.SelectedItems.Count) { $selIp = $list.SelectedItems[0].SubItems[1].Text }
    $list.Items.Clear()
    foreach ($t in $script:targets) {
        $it = New-Object System.Windows.Forms.ListViewItem($t.Name)
        [void]$it.SubItems.Add($t.Ip)
        $m = $script:monitors[$t.Ip]
        if ($m) {
            $valid = @($m.Samples | Where-Object { $_ -ge 0 })
            $lossN = @($m.Samples | Where-Object { $_ -lt 0 }).Count
            $total = $m.Samples.Count
            $loss = if ($total -gt 0) { [math]::Round(100*$lossN/$total) } else { 0 }
            $mn = if ($valid.Count) { ($valid | Measure-Object -Minimum).Minimum } else { '-' }
            $mx = if ($valid.Count) { ($valid | Measure-Object -Maximum).Maximum } else { '-' }
            $av = if ($valid.Count) { [math]::Round(($valid | Measure-Object -Average).Average) } else { '-' }
            $state = if ($m.Job -and $m.Job.State -eq 'Running') { 'run' } else { 'done' }
            [void]$it.SubItems.Add($state)
            [void]$it.SubItems.Add("$mn"); [void]$it.SubItems.Add("$mx"); [void]$it.SubItems.Add("$av")
            $lsub = $it.SubItems.Add("$loss%")
            if ($loss -gt 0) { $lsub.ForeColor = [System.Drawing.Color]::FromArgb(220,70,70) }
            $it.UseItemStyleForSubItems = $false
        } else {
            [void]$it.SubItems.Add('-'); [void]$it.SubItems.Add('-')
            [void]$it.SubItems.Add('-'); [void]$it.SubItems.Add('-'); [void]$it.SubItems.Add('-')
        }
        $csub = $it.SubItems.Add('    ')
        $csub.BackColor = $t.Color
        if ($checkedIps[$t.Ip]) { $it.Checked = $true }
        if ($selIp -eq $t.Ip) { $it.Selected = $true }
        [void]$list.Items.Add($it)
    }
    $list.EndUpdate()
}

function Move-Selected($delta) {
    if ($list.SelectedItems.Count -eq 0) { return }
    $ip = $list.SelectedItems[0].SubItems[1].Text
    $idx = -1
    for ($k=0; $k -lt $script:targets.Count; $k++){ if($script:targets[$k].Ip -eq $ip){$idx=$k;break} }
    if ($idx -lt 0) { return }
    $new = $idx + $delta
    if ($new -lt 0 -or $new -ge $script:targets.Count) { return }
    $item = $script:targets[$idx]
    $script:targets.RemoveAt($idx)
    $script:targets.Insert($new, $item)
    Refresh-List; Save-Settings
}
$btnUp.Add_Click({ Move-Selected -1 })
$btnDown.Add_Click({ Move-Selected 1 })

function Pick-Color {
    if ($list.SelectedItems.Count -eq 0) { Write-Log 'Select a row first, then Color.'; return }
    $ip = $list.SelectedItems[0].SubItems[1].Text
    $t = $script:targets | Where-Object { $_.Ip -eq $ip } | Select-Object -First 1
    if (-not $t) { return }
    $dlg = New-Object System.Windows.Forms.ColorDialog
    $dlg.Color = $t.Color
    if ($dlg.ShowDialog() -eq 'OK') {
        $t.Color = $dlg.Color
        Refresh-List; Save-Settings
        if ($script:overlay -and -not $script:overlay.IsDisposed) { $script:overlayPanel.Invalidate() }
    }
}
# inline editor textbox (hidden until used)
$editBox = New-Object System.Windows.Forms.TextBox
$editBox.Visible = $false
$editBox.BorderStyle = 'FixedSingle'
$list.Controls.Add($editBox)
$script:editItem = $null
$script:editCol = -1

function Commit-Edit {
    if ($null -eq $script:editItem) { return }
    $txt = $editBox.Text.Trim()
    $ip = $script:editItem.SubItems[1].Text
    $t = $script:targets | Where-Object { $_.Ip -eq $ip } | Select-Object -First 1
    if ($t -and $txt) {
        if ($script:editCol -eq 0) { $t.Name = $txt }
        elseif ($script:editCol -eq 1) {
            # if a measurement exists under old ip key, move it
            if ($script:monitors.ContainsKey($t.Ip) -and $t.Ip -ne $txt) {
                $script:monitors[$txt] = $script:monitors[$t.Ip]
                $script:monitors.Remove($t.Ip)
            }
            $t.Ip = $txt
        }
    }
    $editBox.Visible = $false
    $script:editItem = $null
    $script:editCol = -1
    Refresh-List
    Save-Settings
}
$editBox.Add_Leave({ Commit-Edit })
$editBox.Add_KeyDown({
    if ($_.KeyCode -eq 'Enter') { Commit-Edit }
    elseif ($_.KeyCode -eq 'Escape') { $editBox.Visible=$false; $script:editItem=$null; $script:editCol=-1 }
})

$list.Add_MouseDoubleClick({
    param($src,$e)
    $hit = $list.HitTest($e.Location)
    $item = $hit.Item
    if ($null -eq $item) { return }
    # figure out which column
    $col = -1; $x = 0
    for ($c=0; $c -lt $list.Columns.Count; $c++) {
        $x2 = $x + $list.Columns[$c].Width
        if ($e.X -ge $x -and $e.X -lt $x2) { $col = $c; break }
        $x = $x2
    }
    if ($col -eq 7) {   # Color column -> color picker
        $item.Selected = $true
        Pick-Color
        return
    }
    if ($col -eq 0 -or $col -eq 1) {   # Name or IP -> inline edit
        $script:editItem = $item
        $script:editCol = $col
        $script:editWasChecked = $item.Checked
        # compute cell rectangle
        $cx = 0
        for ($c=0; $c -lt $col; $c++) { $cx += $list.Columns[$c].Width }
        $r = $item.Bounds
        $editBox.SetBounds($cx+2, $r.Top, $list.Columns[$col].Width-2, $r.Height)
        $editBox.Text = $item.SubItems[$col].Text
        $editBox.Visible = $true
        $editBox.BringToFront()
        $editBox.Focus(); $editBox.SelectAll()
        # restore check state that the double-click may have toggled
        $script:suppressAll = $true
        $item.Checked = $script:editWasChecked
        $script:suppressAll = $false
    }
})

# ---- Add / Delete ----
$lblName = New-Object System.Windows.Forms.Label
$lblName.Text='Name:'; $lblName.Location=New-Object System.Drawing.Point(12,192); $lblName.AutoSize=$true
$form.Controls.Add($lblName)
$txtName = New-Object System.Windows.Forms.TextBox
$txtName.Location=New-Object System.Drawing.Point(55,189); $txtName.Size=New-Object System.Drawing.Size(90,23)
$form.Controls.Add($txtName)
$lblIp = New-Object System.Windows.Forms.Label
$lblIp.Text='IP:'; $lblIp.Location=New-Object System.Drawing.Point(155,192); $lblIp.AutoSize=$true
$form.Controls.Add($lblIp)
$txtIp = New-Object System.Windows.Forms.TextBox
$txtIp.Location=New-Object System.Drawing.Point(180,189); $txtIp.Size=New-Object System.Drawing.Size(130,23)
$form.Controls.Add($txtIp)
$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text='Add'; $btnAdd.Location=New-Object System.Drawing.Point(318,188); $btnAdd.Size=New-Object System.Drawing.Size(60,25)
$btnAdd.Add_Click({
    if ($txtIp.Text.Trim()) {
        $nm = if($txtName.Text.Trim()){$txtName.Text.Trim()}else{$txtIp.Text.Trim()}
        $ci = $script:targets.Count % $script:defaultColors.Count
        [void]$script:targets.Add([pscustomobject]@{Name=$nm; Ip=$txtIp.Text.Trim(); Color=$script:defaultColors[$ci]; Checked=$true})
        $txtName.Clear(); $txtIp.Clear(); Refresh-List; Save-Settings
    }
})
$form.Controls.Add($btnAdd)
$btnDel = New-Object System.Windows.Forms.Button
$btnDel.Text='Delete'; $btnDel.Location=New-Object System.Drawing.Point(384,188); $btnDel.Size=New-Object System.Drawing.Size(60,25)
$btnDel.Add_Click({
    foreach ($i in @($list.CheckedItems)) {
        $ip = $i.SubItems[1].Text
        if ($script:monitors[$ip]) { Stop-One $ip }
        $rm = $script:targets | Where-Object { $_.Ip -eq $ip }
        foreach($r in $rm){ $script:targets.Remove($r) }
    }
    Refresh-List; Save-Settings
})
$form.Controls.Add($btnDel)

$chkAll = New-Object System.Windows.Forms.CheckBox
$chkAll.Text='All'; $chkAll.Location=New-Object System.Drawing.Point(452,190); $chkAll.AutoSize=$true; $chkAll.Checked=$true
$chkAll.Add_CheckedChanged({
    if ($script:suppressAll) { return }
    $script:bulkCheck = $true
    $val = $chkAll.Checked
    foreach ($i in $list.Items) { $i.Checked = $val }
    foreach ($t in $script:targets) {
        if ($null -ne $t.PSObject.Properties['Checked']) { $t.Checked = $val }
        else { $t | Add-Member -NotePropertyName Checked -NotePropertyValue $val -Force }
    }
    $script:bulkCheck = $false
    if (-not $script:loading) { Save-Settings }
})
$form.Controls.Add($chkAll)
$script:chkAllReady = $true

# ---- Mode ----
$grp = New-Object System.Windows.Forms.GroupBox
$grp.Text='Mode'; $grp.Location=New-Object System.Drawing.Point(12,222); $grp.Size=New-Object System.Drawing.Size(300,58)
$rbT = New-Object System.Windows.Forms.RadioButton
$rbT.Text='-t continuous'; $rbT.Location=New-Object System.Drawing.Point(12,22); $rbT.AutoSize=$true; $rbT.Checked=$true
$grp.Controls.Add($rbT)
$rbN = New-Object System.Windows.Forms.RadioButton
$rbN.Text='-n count'; $rbN.Location=New-Object System.Drawing.Point(120,22); $rbN.AutoSize=$true
$grp.Controls.Add($rbN)
$numN = New-Object System.Windows.Forms.NumericUpDown
$numN.Location=New-Object System.Drawing.Point(200,20); $numN.Size=New-Object System.Drawing.Size(70,23)
$numN.Minimum=1; $numN.Maximum=100000; $numN.Value=300
$grp.Controls.Add($numN)
$form.Controls.Add($grp)
# link refs for settings (restore happens after Load-Settings below)
$script:rbNRef = $rbN
$script:numNRef = $numN
$script:rbTRef = $rbT
$rbN.Add_CheckedChanged({ if (-not $script:loading) { Save-Settings } })
$numN.Add_ValueChanged({ if (-not $script:loading) { Save-Settings } })

# ---- Buttons ----
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text='Start selected'; $btnStart.Location=New-Object System.Drawing.Point(324,224); $btnStart.Size=New-Object System.Drawing.Size(120,26)
$btnStart.BackColor=[System.Drawing.Color]::FromArgb(90,170,110); $btnStart.ForeColor='White'
$form.Controls.Add($btnStart)
$btnStopAll = New-Object System.Windows.Forms.Button
$btnStopAll.Text='STOP ALL'; $btnStopAll.Location=New-Object System.Drawing.Point(324,254); $btnStopAll.Size=New-Object System.Drawing.Size(120,26)
$btnStopAll.BackColor=[System.Drawing.Color]::FromArgb(230,120,120); $btnStopAll.ForeColor='White'
$form.Controls.Add($btnStopAll)
$btnOverlay = New-Object System.Windows.Forms.Button
$btnOverlay.Text='Overlay'; $btnOverlay.Location=New-Object System.Drawing.Point(452,224); $btnOverlay.Size=New-Object System.Drawing.Size(120,26)
$form.Controls.Add($btnOverlay)
$btnCsv = New-Object System.Windows.Forms.Button
$btnCsv.Text='Export CSV'; $btnCsv.Location=New-Object System.Drawing.Point(452,254); $btnCsv.Size=New-Object System.Drawing.Size(120,26)
$form.Controls.Add($btnCsv)

$lblJudge = New-Object System.Windows.Forms.Label
$lblJudge.Text='Judge window (pings):'; $lblJudge.Location=New-Object System.Drawing.Point(324,285); $lblJudge.AutoSize=$true
$lblJudge.Visible=$false
$form.Controls.Add($lblJudge)
$numJudge = New-Object System.Windows.Forms.NumericUpDown
$numJudge.Location=New-Object System.Drawing.Point(452,283); $numJudge.Size=New-Object System.Drawing.Size(70,23)
$numJudge.Minimum=5; $numJudge.Maximum=1000; $numJudge.Value=30
$numJudge.Visible=$false
$form.Controls.Add($numJudge)

$log = New-Object System.Windows.Forms.TextBox
$log.Location=New-Object System.Drawing.Point(12,286); $log.Size=New-Object System.Drawing.Size(560,120)
$log.Multiline=$true; $log.ScrollBars='Vertical'; $log.ReadOnly=$true
$log.Font = New-Object System.Drawing.Font('Consolas',8)
$form.Controls.Add($log)
function Write-Log($msg){ $log.AppendText((Get-Date -Format 'HH:mm:ss') + "  $msg`r`n") }

function Start-One($t, $mode, $count) {
    if ($script:monitors[$t.Ip] -and $script:monitors[$t.Ip].Job.State -eq 'Running') { return }
    $sb = {
        param($ip,$mode,$count)
        if ($mode -eq 't') { $n = 2147483647 } else { $n = $count }
        for ($i=0; $i -lt $n; $i++) {
            $r = Test-Connection -ComputerName $ip -Count 1 -ErrorAction SilentlyContinue
            if ($r) {
                $ms = $r.ResponseTime; if ($null -eq $ms) { $ms = $r.Latency }
                if ($null -eq $ms) { $ms = 0 }
                Write-Output ([int]$ms)
            } else {
                Write-Output (-1)
            }
            Start-Sleep -Milliseconds 800
        }
    }
    $job = Start-Job -ScriptBlock $sb -ArgumentList $t.Ip,$mode,$count
    $script:monitors[$t.Ip] = @{
        Name=$t.Name; Ip=$t.Ip; Job=$job
        Samples=[System.Collections.ArrayList]@(); Times=[System.Collections.ArrayList]@(); Mode=$mode; Count=$count
    }
    Write-Log "start: $($t.Name) [$($t.Ip)] mode=$mode"
}

function Stop-One($ip) {
    $m = $script:monitors[$ip]
    if ($m -and $m.Job) {
        Stop-Job $m.Job -ErrorAction SilentlyContinue
        Remove-Job $m.Job -Force -ErrorAction SilentlyContinue
        Write-Log "stop: $($m.Name) [$ip]"
    }
}

$btnStart.Add_Click({
    $mode = if ($rbT.Checked) {'t'} else {'n'}
    $cnt = [int]$numN.Value
    $sel = @($list.CheckedItems)
    if ($sel.Count -eq 0){ Write-Log 'No item checked.'; return }
    foreach ($i in $sel) {
        $t = $script:targets | Where-Object { $_.Ip -eq $i.SubItems[1].Text } | Select-Object -First 1
        if ($t) { Start-One $t $mode $cnt }
    }
})
$btnStopAll.Add_Click({ foreach ($ip in @($script:monitors.Keys)) { Stop-One $ip }; Write-Log 'stopped all' })

# ---- Timer: only redraw overlay when new data arrived (fix flicker) ----
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    $changed = $false
    foreach ($ip in @($script:monitors.Keys)) {
        $m = $script:monitors[$ip]
        if ($m.Job) {
            $data = Receive-Job $m.Job -ErrorAction SilentlyContinue
            foreach ($d in $data) {
                [void]$m.Samples.Add([int]$d)
                [void]$m.Times.Add((Get-Date))
                $changed = $true
            }
            # ring buffer: drop oldest beyond cap
            while ($m.Samples.Count -gt $script:maxSamples) {
                $m.Samples.RemoveAt(0); $m.Times.RemoveAt(0)
            }
        }
    }
    if ($changed) {
        Refresh-List
        if ($script:overlay -and -not $script:overlay.IsDisposed) { Update-OverlayHeight; $script:overlayPanel.Invalidate() }
    }

})
$timer.Start()

function Export-Csv-All {
    $any = $false
    foreach ($ip in $script:monitors.Keys) { if ($script:monitors[$ip].Samples.Count -gt 0) { $any=$true; break } }
    if (-not $any) { Write-Log 'No data to export.'; return }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = 'CSV file (*.csv)|*.csv'
    $dlg.FileName = ('ping_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.csv')
    if ($dlg.ShowDialog() -ne 'OK') { return }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('timestamp,name,ip,rtt_ms,status')
    foreach ($t in $script:targets) {
        $m = $script:monitors[$t.Ip]
        if (-not $m) { continue }
        for ($k=0; $k -lt $m.Samples.Count; $k++) {
            $ts = if ($k -lt $m.Times.Count) { $m.Times[$k].ToString('yyyy-MM-dd HH:mm:ss.fff') } else { '' }
            $val = [int]$m.Samples[$k]
            if ($val -lt 0) { $rtt=''; $status='loss' } else { $rtt=$val; $status='ok' }
            [void]$sb.AppendLine("$ts,$($m.Name),$($m.Ip),$rtt,$status")
        }
    }
    [System.IO.File]::WriteAllText($dlg.FileName, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
    Write-Log ("exported: " + $dlg.FileName)
}
$btnCsv.Add_Click({ Export-Csv-All })


# ---------- Overlay (double-buffered, auto-height, ordered) ----------
# shared fonts (created once, reused every paint -> no leak)
$script:ovFontN   = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
$script:ovFontS   = New-Object System.Drawing.Font('Consolas',8)
$script:ovFontAvg = New-Object System.Drawing.Font('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
$script:overlay = $null
$script:overlayPanel = $null
$script:ovOpacity = 0.88
function Update-OverlayHeight {
    if (-not ($script:overlay -and -not $script:overlay.IsDisposed)) { return }
    $rowH = 44
    $cnt = 0
    foreach ($t in $script:targets) {
        $m = $script:monitors[$t.Ip]
        if ($m -and $m.Samples.Count -gt 0) { $cnt++ }
    }
    $needH = [math]::Max(1,$cnt) * $rowH + 30
    if ($script:overlay.Height -ne $needH) { $script:overlay.Height = $needH }
}

function Show-Overlay {
    if ($script:overlay -and -not $script:overlay.IsDisposed) { $script:overlay.Activate(); return }
    $ov = New-Object System.Windows.Forms.Form
    $ov.FormBorderStyle='None'; $ov.TopMost=$true; $ov.BackColor=[System.Drawing.Color]::FromArgb(20,20,25)
    $ov.Opacity=$script:ovOpacity; $ov.StartPosition='Manual'
    $ov.Location=New-Object System.Drawing.Point(40,40); $ov.ShowInTaskbar=$false
    $ov.Size=New-Object System.Drawing.Size(250,200)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock='Fill'
    $pt = $panel.GetType()
    $prop = $pt.GetProperty('DoubleBuffered',[System.Reflection.BindingFlags]'Instance,NonPublic')
    $prop.SetValue($panel,$true,$null)
    $ov.Controls.Add($panel)
    # make overlay/panel referenceable NOW (handlers below rely on these)
    $script:overlay = $ov
    $script:overlayPanel = $panel

    # opacity is drawn as a custom slider at the bottom of the overlay.
    $wheelH = {
        param($src,$ev)
        $delta = if ($ev.Delta -gt 0) { 0.05 } else { -0.05 }
        $v = $script:ovOpacity + $delta
        if ($v -lt 0.2) { $v = 0.2 }; if ($v -gt 1.0) { $v = 1.0 }
        $script:ovOpacity = [math]::Round($v,2)
        $script:overlay.Opacity = $script:ovOpacity
        $script:overlayPanel.Invalidate()
    }
    $panel.Add_MouseWheel($wheelH)
    $ov.Add_MouseWheel($wheelH)

    # ---- Drag + slider handling (inline, no external function calls) ----
    $script:drag=$false; $script:dsx=0; $script:dsy=0
    $downH = {
        param($src,$e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $script:drag=$true
            $p = [System.Windows.Forms.Cursor]::Position
            $script:dsx = $p.X - $script:overlay.Location.X
            $script:dsy = $p.Y - $script:overlay.Location.Y
        } elseif ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
            $script:overlay.Close()
        }
    }
    $moveH = {
        if ($script:drag) {
            $p = [System.Windows.Forms.Cursor]::Position
            $script:overlay.Location = New-Object System.Drawing.Point(($p.X-$script:dsx),($p.Y-$script:dsy))
        }
    }
    $upH = { $script:drag=$false }
    $panel.Add_MouseDown($downH); $panel.Add_MouseMove($moveH); $panel.Add_MouseUp($upH)
    $ov.Add_MouseDown($downH);    $ov.Add_MouseMove($moveH);    $ov.Add_MouseUp($upH)

    $panel.Add_Paint({
        param($s,$e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $fontN = $script:ovFontN
        $fontS = $script:ovFontS
        $rowH = 44
        $rows = @()
        foreach ($t in $script:targets) {
            $m = $script:monitors[$t.Ip]
            if ($m -and $m.Samples.Count -gt 0) { $rows += ,@($t,$m) }
        }
        if ($rows.Count -eq 0) {
            $g.DrawString('Start a measurement', $fontS, [System.Drawing.Brushes]::Gray, 8, 8)
            return
        }
        $y = 6
        foreach ($row in $rows) {
            $t = $row[0]; $m = $row[1]
            $valid = @($m.Samples | Where-Object { $_ -ge 0 })
            $lossN = @($m.Samples | Where-Object { $_ -lt 0 }).Count
            $total = $m.Samples.Count
            $loss = if($total){[math]::Round(100*$lossN/$total)}else{0}
            $mn = if($valid.Count){($valid|Measure-Object -Minimum).Minimum}else{0}
            $mx = if($valid.Count){($valid|Measure-Object -Maximum).Maximum}else{0}
            $av = if($valid.Count){[math]::Round(($valid|Measure-Object -Average).Average)}else{0}
            # latest valid sample (skip trailing loss for the big number)
            $latest = 0
            for ($li=$m.Samples.Count-1; $li -ge 0; $li--) { if ($m.Samples[$li] -ge 0) { $latest=$m.Samples[$li]; break } }
            $vr = Get-RecentVerdict $m.Samples ([int]$numJudge.Value)
            $vbrush = New-Object System.Drawing.SolidBrush $vr[1]
            $g.FillEllipse($vbrush, 8, $y+3, 9, 9)
            $vbrush.Dispose()
            # name (truncated with ellipsis if it would reach the avg column)
            $avgX = 100
            $nameMaxW = $avgX - 22 - 6
            $nm2 = $t.Name
            if ($g.MeasureString($nm2, $fontN).Width -gt $nameMaxW) {
                while ($nm2.Length -gt 1 -and $g.MeasureString(($nm2 + [char]0x2026), $fontN).Width -gt $nameMaxW) {
                    $nm2 = $nm2.Substring(0, $nm2.Length-1)
                }
                $nm2 = $nm2 + [char]0x2026
            }
            $g.DrawString($nm2, $fontN, [System.Drawing.Brushes]::White, 22, $y)
            # latest ms emphasized: bigger, bright, at a FIXED x so values line up vertically
            $bigBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(230,240,255))
            $g.DrawString("${latest}ms", $script:ovFontAvg, $bigBrush, $avgX, ($y-2))
            $bigBrush.Dispose()
            # secondary line: min / max / avg / loss
            $statTxt = "min$mn max$mx avg$av "
            $g.DrawString($statTxt, $fontS, [System.Drawing.Brushes]::Gray, 22, ($y+18))
            $statW = $g.MeasureString($statTxt, $fontS).Width
            $lossTxt = "loss$loss%"
            if ($loss -gt 0) {
                $lossBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(230,80,80))
                $g.DrawString($lossTxt, $fontS, $lossBrush, (22+$statW), ($y+18))
                $lossBrush.Dispose()
            } else {
                $g.DrawString($lossTxt, $fontS, [System.Drawing.Brushes]::Gray, (22+$statW), ($y+18))
            }
            $recent = @($m.Samples | Select-Object -Last 40)
            if ($recent.Count -ge 2) {
                $x0=22; $w=210; $h=14; $baseY=$y+30
                $pos = @($recent | Where-Object {$_ -ge 0})
                $peak = if($pos.Count){($pos|Measure-Object -Maximum).Maximum}else{1}
                if($peak -lt 1){$peak=1}
                $pen = New-Object System.Drawing.Pen $t.Color, 1.5
                $step = $w / [math]::Max(1,($recent.Count-1))
                for ($k=1; $k -lt $recent.Count; $k++) {
                    $a=$recent[$k-1]; $b=$recent[$k]
                    if ($a -lt 0 -or $b -lt 0) { continue }
                    $x1=$x0+$step*($k-1); $y1=$baseY+$h-($a/$peak*$h)
                    $x2=$x0+$step*$k;     $y2=$baseY+$h-($b/$peak*$h)
                    $g.DrawLine($pen,$x1,$y1,$x2,$y2)
                }
                $pen.Dispose()
            }
            $y += $rowH
        }
    })
    $ov.Show()
    Update-OverlayHeight
    $panel.Invalidate()
}

$btnOverlay.Add_Click({
    if ($script:overlay -and -not $script:overlay.IsDisposed) { $script:overlay.Close() }
    else { Show-Overlay }
})

$form.Add_FormClosing({
    foreach ($ip in @($script:monitors.Keys)) { Stop-One $ip }
    $timer.Stop()
    if ($script:overlay -and -not $script:overlay.IsDisposed) { $script:overlay.Close() }
})

$script:loading = $true
[void](Load-Settings)
# restore saved mode/count now that they are loaded
if ($script:savedCount -and $script:numNRef) {
    $script:numNRef.Value = [math]::Min([math]::Max($script:savedCount,$script:numNRef.Minimum),$script:numNRef.Maximum)
}
if ($script:savedMode -eq 'n' -and $script:rbNRef) { $script:rbNRef.Checked = $true }
elseif ($script:savedMode -eq 't' -and $script:rbTRef) { $script:rbTRef.Checked = $true }
$script:loading = $false
Refresh-List
Write-Log 'Ready. Double-click Name/IP to edit, Color cell to set color. Up/Down to reorder.'
[void]$form.ShowDialog()
