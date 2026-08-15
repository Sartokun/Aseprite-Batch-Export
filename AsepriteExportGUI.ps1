Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

try {

$settingsPath = Join-Path $PSScriptRoot "aseprite_export_settings.json"

function Load-Settings {
    if (Test-Path $settingsPath) {
        try { return Get-Content $settingsPath -Raw | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

function Save-Settings($s) {
    $s | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8
}

# ---------- Aseprite CLI helper ----------
# ประกอบ argument ให้ถูกกฎ command line ของ Windows (ชื่อ layer/tag มีเว้นวรรคได้)
function ConvertTo-CmdArg([string]$a) {
    if ($a -eq "") { return '""' }
    if ($a -notmatch '[\s"]') { return $a }
    $s = $a -replace '(\\*)"', '$1$1\"'
    $s = $s -replace '(\\+)$', '$1$1'
    return '"' + $s + '"'
}

function Invoke-Aseprite($exePath, [string[]]$argList) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $exePath
    $psi.Arguments              = (($argList | ForEach-Object { ConvertTo-CmdArg $_ }) -join " ")
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()

    return [PSCustomObject]@{
        ExitCode = $p.ExitCode
        Out      = $outTask.Result
        Err      = $errTask.Result
    }
}

# Test-Path จะ throw ถ้าส่งค่าว่างเข้าไป (ช่องกรอกที่ยังไม่ได้ใส่)
function Test-PathSafe([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    try { return (Test-Path -LiteralPath $path) } catch { return $false }
}

function Split-Lines([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    return @($text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
}

$settings = Load-Settings

# ---------- Form ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Aseprite Batch Sprite Sheet Exporter"
$form.Size = New-Object System.Drawing.Size(660, 790)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(620, 720)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

function New-Label($text, $x, $y, $w=560) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, 18)
    return $l
}

function New-MiniButton($text, $x, $y, $w) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, 24)
    $b.Anchor = "Top,Right"
    return $b
}

$y = 12

$lbl1 = New-Label "aseprite.exe:" 12 $y
$form.Controls.Add($lbl1)
$y += 20
$txtExe = New-Object System.Windows.Forms.TextBox
$txtExe.Location = New-Object System.Drawing.Point(12, $y)
$txtExe.Size = New-Object System.Drawing.Size(510, 22)
$txtExe.Anchor = "Top,Left,Right"
if ($settings -and $settings.AsepritePath) { $txtExe.Text = $settings.AsepritePath }
$form.Controls.Add($txtExe)
$btnExe = New-Object System.Windows.Forms.Button
$btnExe.Text = "Browse..."
$btnExe.Location = New-Object System.Drawing.Point(530, ($y-1))
$btnExe.Size = New-Object System.Drawing.Size(96, 24)
$btnExe.Anchor = "Top,Right"
$btnExe.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "Executable|*.exe"
    $ofd.Title = "Select aseprite.exe"
    if ($ofd.ShowDialog() -eq "OK") { $txtExe.Text = $ofd.FileName }
})
$form.Controls.Add($btnExe)
$y += 34

$lbl2 = New-Label ".aseprite file:" 12 $y
$form.Controls.Add($lbl2)
$y += 20
$txtFile = New-Object System.Windows.Forms.TextBox
$txtFile.Location = New-Object System.Drawing.Point(12, $y)
$txtFile.Size = New-Object System.Drawing.Size(414, 22)
$txtFile.Anchor = "Top,Left,Right"
if ($settings -and $settings.FilePath) { $txtFile.Text = $settings.FilePath }
$form.Controls.Add($txtFile)
$btnFile = New-Object System.Windows.Forms.Button
$btnFile.Text = "Browse..."
$btnFile.Location = New-Object System.Drawing.Point(434, ($y-1))
$btnFile.Size = New-Object System.Drawing.Size(90, 24)
$btnFile.Anchor = "Top,Right"
$btnFile.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "Aseprite Files|*.aseprite;*.ase|All Files|*.*"
    $ofd.Title = "Select .aseprite file"
    if ($ofd.ShowDialog() -eq "OK") {
        $txtFile.Text = $ofd.FileName
        if ([string]::IsNullOrWhiteSpace($txtPrefix.Text)) {
            $txtPrefix.Text = [System.IO.Path]::GetFileNameWithoutExtension($ofd.FileName)
        }
        if ([string]::IsNullOrWhiteSpace($txtOutFolder.Text)) {
            $txtOutFolder.Text = [System.IO.Path]::GetDirectoryName($ofd.FileName)
        }
        Invoke-Scan
    }
})
$form.Controls.Add($btnFile)
$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "Scan ไฟล์"
$btnScan.Location = New-Object System.Drawing.Point(530, ($y-1))
$btnScan.Size = New-Object System.Drawing.Size(96, 24)
$btnScan.Anchor = "Top,Right"
$btnScan.Add_Click({ Invoke-Scan })
$form.Controls.Add($btnScan)
$y += 34

# ---------- Layers ----------
$lbl3 = New-Label "Layers:" 12 ($y+3) 360
$form.Controls.Add($lbl3)
$btnLayersAll  = New-MiniButton "เลือกทั้งหมด" 388 $y 90
$btnLayersNone = New-MiniButton "ล้าง" 482 $y 60
$btnLayersAdd  = New-MiniButton "+ เพิ่มเอง" 546 $y 80
$form.Controls.Add($btnLayersAll)
$form.Controls.Add($btnLayersNone)
$form.Controls.Add($btnLayersAdd)
$y += 28
$lstLayers = New-Object System.Windows.Forms.CheckedListBox
$lstLayers.Location = New-Object System.Drawing.Point(12, $y)
$lstLayers.Size = New-Object System.Drawing.Size(614, 100)
$lstLayers.Anchor = "Top,Left,Right"
$lstLayers.CheckOnClick = $true
$lstLayers.IntegralHeight = $false
$form.Controls.Add($lstLayers)
$y += 110

# ---------- Tags ----------
$lbl4 = New-Label "Tags:" 12 ($y+3) 360
$form.Controls.Add($lbl4)
$btnTagsAll  = New-MiniButton "เลือกทั้งหมด" 388 $y 90
$btnTagsNone = New-MiniButton "ล้าง" 482 $y 60
$btnTagsAdd  = New-MiniButton "+ เพิ่มเอง" 546 $y 80
$form.Controls.Add($btnTagsAll)
$form.Controls.Add($btnTagsNone)
$form.Controls.Add($btnTagsAdd)
$y += 28
$lstTags = New-Object System.Windows.Forms.CheckedListBox
$lstTags.Location = New-Object System.Drawing.Point(12, $y)
$lstTags.Size = New-Object System.Drawing.Size(614, 100)
$lstTags.Anchor = "Top,Left,Right"
$lstTags.CheckOnClick = $true
$lstTags.IntegralHeight = $false
$form.Controls.Add($lstTags)
$y += 112

$lbl5 = New-Label "Sheet type:" 12 ($y+2) 100
$form.Controls.Add($lbl5)
$cmbSheet = New-Object System.Windows.Forms.ComboBox
$cmbSheet.Location = New-Object System.Drawing.Point(100, $y)
$cmbSheet.Size = New-Object System.Drawing.Size(140, 22)
$cmbSheet.DropDownStyle = "DropDownList"
[void]$cmbSheet.Items.AddRange(@("horizontal","vertical","rows","columns","packed"))
$cmbSheet.SelectedIndex = 0
if ($settings -and $settings.SheetType) { $cmbSheet.SelectedItem = $settings.SheetType }
$form.Controls.Add($cmbSheet)

$chkIgnoreEmpty = New-Object System.Windows.Forms.CheckBox
$chkIgnoreEmpty.Text = "Ignore empty frames"
$chkIgnoreEmpty.Location = New-Object System.Drawing.Point(270, $y)
$chkIgnoreEmpty.Size = New-Object System.Drawing.Size(180, 22)
$chkIgnoreEmpty.Checked = $true
if ($settings -and ($settings.PSObject.Properties.Name -contains "IgnoreEmpty")) { $chkIgnoreEmpty.Checked = [bool]$settings.IgnoreEmpty }
$form.Controls.Add($chkIgnoreEmpty)
$y += 34

$lbl6 = New-Label "Output prefix:" 12 ($y+2) 120
$form.Controls.Add($lbl6)
$txtPrefix = New-Object System.Windows.Forms.TextBox
$txtPrefix.Location = New-Object System.Drawing.Point(130, $y)
$txtPrefix.Size = New-Object System.Drawing.Size(220, 22)
if ($settings -and $settings.Prefix) { $txtPrefix.Text = $settings.Prefix }
$form.Controls.Add($txtPrefix)
$y += 32

$lbl7 = New-Label "Output folder:" 12 $y
$form.Controls.Add($lbl7)
$y += 20
$txtOutFolder = New-Object System.Windows.Forms.TextBox
$txtOutFolder.Location = New-Object System.Drawing.Point(12, $y)
$txtOutFolder.Size = New-Object System.Drawing.Size(510, 22)
$txtOutFolder.Anchor = "Top,Left,Right"
if ($settings -and $settings.OutputFolder) { $txtOutFolder.Text = $settings.OutputFolder }
$form.Controls.Add($txtOutFolder)
$btnOutFolder = New-Object System.Windows.Forms.Button
$btnOutFolder.Text = "Browse..."
$btnOutFolder.Location = New-Object System.Drawing.Point(530, ($y-1))
$btnOutFolder.Size = New-Object System.Drawing.Size(96, 24)
$btnOutFolder.Anchor = "Top,Right"
$btnOutFolder.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($fbd.ShowDialog() -eq "OK") { $txtOutFolder.Text = $fbd.SelectedPath }
})
$form.Controls.Add($btnOutFolder)
$y += 36

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "Export"
$btnExport.Location = New-Object System.Drawing.Point(12, $y)
$btnExport.Size = New-Object System.Drawing.Size(120, 32)
$btnExport.BackColor = [System.Drawing.Color]::FromArgb(76,175,80)
$btnExport.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($btnExport)

$btnOpenOut = New-Object System.Windows.Forms.Button
$btnOpenOut.Text = "Open Output Folder"
$btnOpenOut.Location = New-Object System.Drawing.Point(140, $y)
$btnOpenOut.Size = New-Object System.Drawing.Size(150, 32)
$btnOpenOut.Add_Click({
    if (Test-PathSafe $txtOutFolder.Text.Trim().Trim('"')) { Start-Process explorer.exe $txtOutFolder.Text.Trim().Trim('"') }
})
$form.Controls.Add($btnOpenOut)

$progressLabel = New-Object System.Windows.Forms.Label
$progressLabel.Location = New-Object System.Drawing.Point(310, ($y+6))
$progressLabel.Size = New-Object System.Drawing.Size(316, 22)
$progressLabel.Anchor = "Top,Right"
$progressLabel.TextAlign = "MiddleRight"
$form.Controls.Add($progressLabel)
$y += 44

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(12, $y)
$tabs.Size = New-Object System.Drawing.Size(614, 180)
$tabs.Anchor = "Top,Bottom,Left,Right"
$form.Controls.Add($tabs)

$tabPreview = New-Object System.Windows.Forms.TabPage
$tabPreview.Text = "พรีวิวชื่อไฟล์"
$tabPreview.UseVisualStyleBackColor = $true
$tabs.TabPages.Add($tabPreview)

$lstPreview = New-Object System.Windows.Forms.ListBox
$lstPreview.Dock = "Fill"
$lstPreview.IntegralHeight = $false
$lstPreview.HorizontalScrollbar = $true
$tabPreview.Controls.Add($lstPreview)

$tabLog = New-Object System.Windows.Forms.TabPage
$tabLog.Text = "Log"
$tabLog.UseVisualStyleBackColor = $true
$tabs.TabPages.Add($tabLog)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Dock = "Fill"
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$tabLog.Controls.Add($logBox)

function Add-Log($text) {
    $logBox.AppendText("$text`r`n")
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

# ---------- Checklist helpers ----------
function Get-CheckedItems($list) {
    return @($list.CheckedItems | ForEach-Object { [string]$_ })
}

function Set-AllChecked($list, [bool]$state) {
    for ($i = 0; $i -lt $list.Items.Count; $i++) { $list.SetItemChecked($i, $state) }
}

function Add-ManualItem($list, $title) {
    $name = [Microsoft.VisualBasic.Interaction]::InputBox("พิมพ์ชื่อ$title ที่ต้องการเพิ่มเอง:", "เพิ่ม$title", "")
    $name = $name.Trim()
    if ($name -eq "") { return }
    $idx = $list.Items.IndexOf($name)
    if ($idx -lt 0) { $idx = $list.Items.Add($name) }
    $list.SetItemChecked($idx, $true)
}

# เติมรายการลง CheckedListBox แล้วติ๊กคืนตัวที่เคยเลือกไว้
function Fill-List($list, $items, $keep) {
    $list.BeginUpdate()
    $list.Items.Clear()
    foreach ($it in $items) { [void]$list.Items.Add($it) }
    for ($i = 0; $i -lt $list.Items.Count; $i++) {
        if ($keep -contains [string]$list.Items[$i]) { $list.SetItemChecked($i, $true) }
    }
    $list.EndUpdate()
}

$btnLayersAll.Add_Click({  Set-AllChecked $lstLayers $true })
$btnLayersNone.Add_Click({ Set-AllChecked $lstLayers $false })
$btnLayersAdd.Add_Click({  Add-ManualItem $lstLayers "Layer" })
$btnTagsAll.Add_Click({    Set-AllChecked $lstTags $true })
$btnTagsNone.Add_Click({   Set-AllChecked $lstTags $false })
$btnTagsAdd.Add_Click({    Add-ManualItem $lstTags "Tag" })

# ---------- พรีวิวชื่อไฟล์ ----------
# ใช้ร่วมกับตอน export เพื่อให้ชื่อที่พรีวิวตรงกับไฟล์จริงเสมอ
function Get-EffectivePrefix {
    $prefix = $txtPrefix.Text.Trim()
    if ($prefix -eq "") {
        $fp = $txtFile.Text.Trim().Trim('"')
        if ($fp -ne "") { $prefix = [System.IO.Path]::GetFileNameWithoutExtension($fp) }
    }
    return $prefix
}

function Get-OutFileName($prefix, $layer, $tag) {
    $tagSafe = ($tag -replace '\s+', '_')
    return "$($prefix)_$($layer)_$($tagSafe).png"
}

function Update-Preview {
    $outFolder = $txtOutFolder.Text.Trim().Trim('"')
    $prefix    = Get-EffectivePrefix
    $layers    = Get-CheckedItems $lstLayers
    $tags      = Get-CheckedItems $lstTags

    $lstPreview.BeginUpdate()
    $lstPreview.Items.Clear()

    if ($layers.Count -eq 0 -or $tags.Count -eq 0) {
        [void]$lstPreview.Items.Add("(ยังไม่ได้ติ๊กเลือก Layers / Tags)")
        $tabPreview.Text = "พรีวิวชื่อไฟล์"
    } else {
        $seen = @{}
        $count = 0
        foreach ($layer in $layers) {
            foreach ($tag in $tags) {
                $name = Get-OutFileName $prefix $layer $tag
                $note = ""
                if ($seen.ContainsKey($name)) {
                    $note = "   << ชื่อซ้ำ! จะทับกันเอง"
                } else {
                    $seen[$name] = $true
                    if (Test-PathSafe (Join-Path $outFolder $name)) { $note = "   << มีไฟล์เดิม จะถูกเขียนทับ" }
                }
                [void]$lstPreview.Items.Add("$name$note")
                $count++
            }
        }
        $tabPreview.Text = "พรีวิวชื่อไฟล์ ($count)"
    }

    $lstPreview.EndUpdate()
}

$previewTimer = New-Object System.Windows.Forms.Timer
$previewTimer.Interval = 60
$previewTimer.Add_Tick({ $previewTimer.Stop(); Update-Preview })

# รวบหลาย ๆ event ที่เกิดติด ๆ กัน (เช่นกด "เลือกทั้งหมด") ให้อัปเดตรอบเดียว
function Queue-Preview {
    $previewTimer.Stop()
    $previewTimer.Start()
}

$lstLayers.Add_ItemCheck({ Queue-Preview })
$lstTags.Add_ItemCheck({ Queue-Preview })
$txtPrefix.Add_TextChanged({ Queue-Preview })
$txtOutFolder.Add_TextChanged({ Queue-Preview })
$txtFile.Add_TextChanged({ Queue-Preview })

# ---------- Scan ----------
function Invoke-Scan {
    $exePath  = $txtExe.Text.Trim().Trim('"')
    $filePath = $txtFile.Text.Trim().Trim('"')

    if (-not (Test-PathSafe $exePath)) {
        [System.Windows.Forms.MessageBox]::Show("ไม่พบไฟล์ aseprite.exe ตามที่ระบุ", "Scan", "OK", "Error")
        return
    }
    if (-not (Test-PathSafe $filePath)) {
        [System.Windows.Forms.MessageBox]::Show("ไม่พบไฟล์ .aseprite ตามที่ระบุ", "Scan", "OK", "Error")
        return
    }

    # ตัวที่เคยติ๊กไว้ (หรือค่าที่บันทึกไว้ครั้งก่อน) จะถูกติ๊กคืนให้อัตโนมัติ
    $keepLayers = Get-CheckedItems $lstLayers
    $keepTags   = Get-CheckedItems $lstTags
    if ($keepLayers.Count -eq 0 -and $settings -and $settings.Layers) {
        $keepLayers = @($settings.Layers -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    }
    if ($keepTags.Count -eq 0 -and $settings -and $settings.Tags) {
        $keepTags = @($settings.Tags -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    }

    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $btnScan.Enabled = $false
    try {
        Add-Log "--- Scanning: $(Split-Path $filePath -Leaf) ---"

        $rLayers = Invoke-Aseprite $exePath @("-b", "--list-layers", $filePath)
        $rTags   = Invoke-Aseprite $exePath @("-b", "--list-tags",   $filePath)

        foreach ($r in @($rLayers, $rTags)) {
            if ($r.ExitCode -ne 0 -and -not [string]::IsNullOrWhiteSpace($r.Err)) {
                Add-Log "  aseprite: $($r.Err.Trim())"
            }
        }

        $layers = Split-Lines $rLayers.Out
        $tags   = Split-Lines $rTags.Out

        Fill-List $lstLayers $layers $keepLayers
        Fill-List $lstTags   $tags   $keepTags

        $lbl3.Text = "Layers: พบ $($layers.Count) รายการ (ติ๊กเลือกที่ต้องการ)"
        $lbl4.Text = "Tags: พบ $($tags.Count) รายการ (ติ๊กเลือกที่ต้องการ)"
        Add-Log "  -> layers: $($layers.Count), tags: $($tags.Count)"

        if ($layers.Count -eq 0 -and $tags.Count -eq 0) {
            Add-Log "  -> WARNING: อ่านรายการไม่ได้ ลองใช้ปุ่ม '+ เพิ่มเอง' พิมพ์ชื่อเอง"
        }
    } catch {
        Add-Log "  -> ERROR: $($_.Exception.Message)"
    } finally {
        $btnScan.Enabled = $true
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        Update-Preview
    }
}

# สแกนอัตโนมัติตอนเปิดโปรแกรม ถ้า path ที่บันทึกไว้ยังใช้ได้
$form.Add_Shown({
    if ((Test-PathSafe $txtExe.Text.Trim().Trim('"')) -and (Test-PathSafe $txtFile.Text.Trim().Trim('"'))) {
        Invoke-Scan
    } else {
        Update-Preview
    }
})

# ---------- Export ----------
$btnExport.Add_Click({
    $exePath = $txtExe.Text.Trim().Trim('"')
    $filePath = $txtFile.Text.Trim().Trim('"')
    $outFolder = $txtOutFolder.Text.Trim().Trim('"')
    $prefix = Get-EffectivePrefix
    $sheetType = $cmbSheet.SelectedItem

    if (-not (Test-PathSafe $exePath)) {
        [System.Windows.Forms.MessageBox]::Show("ไม่พบไฟล์ aseprite.exe ตามที่ระบุ", "Error", "OK", "Error")
        return
    }
    if (-not (Test-PathSafe $filePath)) {
        [System.Windows.Forms.MessageBox]::Show("ไม่พบไฟล์ .aseprite ตามที่ระบุ", "Error", "OK", "Error")
        return
    }
    if ([string]::IsNullOrWhiteSpace($outFolder)) {
        [System.Windows.Forms.MessageBox]::Show("กรุณาระบุ Output folder", "Error", "OK", "Error")
        return
    }
    if (-not (Test-PathSafe $outFolder)) { New-Item -ItemType Directory -Path $outFolder -Force | Out-Null }

    $layers = Get-CheckedItems $lstLayers
    $tags   = Get-CheckedItems $lstTags

    if ($layers.Count -eq 0 -or $tags.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("กรุณาติ๊กเลือก Layers และ Tags อย่างน้อยอย่างละ 1 รายการ`r`n(กด 'Scan ไฟล์' เพื่อดึงรายการจากไฟล์ .aseprite)", "Error", "OK", "Error")
        return
    }

    # Save settings for next time
    $s = [PSCustomObject]@{
        AsepritePath = $exePath
        FilePath     = $filePath
        Layers       = ($layers -join ", ")
        Tags         = ($tags -join ", ")
        SheetType    = $sheetType
        OutputFolder = $outFolder
        Prefix       = $prefix
        IgnoreEmpty  = $chkIgnoreEmpty.Checked
    }
    Save-Settings $s

    $logBox.Clear()
    $tabs.SelectedTab = $tabLog
    $btnExport.Enabled = $false
    $total = $layers.Count * $tags.Count
    $done = 0
    $errors = 0

    Add-Log "--- Exporting Sprites ---"

    foreach ($layer in $layers) {
        foreach ($tag in $tags) {
            $outFile = Join-Path $outFolder (Get-OutFileName $prefix $layer $tag)
            $argList = @("-b", "--layer", $layer, "--frame-tag", $tag, $filePath)
            if ($chkIgnoreEmpty.Checked) { $argList += "--ignore-empty" }
            $argList += @("--sheet-type", $sheetType, "--sheet", $outFile)

            Add-Log "Exporting: $layer - $tag"
            # ลบไฟล์เดิมก่อน เพื่อให้เช็คผลลัพธ์ได้จริงว่ารอบนี้สร้างสำเร็จไหม
            if (Test-Path $outFile) { Remove-Item $outFile -Force -ErrorAction SilentlyContinue }
            try {
                $r = Invoke-Aseprite $exePath $argList
                if (-not [string]::IsNullOrWhiteSpace($r.Out)) { Add-Log $r.Out.TrimEnd() }
                if (-not [string]::IsNullOrWhiteSpace($r.Err)) { Add-Log $r.Err.TrimEnd() }
                if (Test-Path $outFile) {
                    Add-Log "  -> OK: $(Split-Path $outFile -Leaf)"
                } else {
                    $errors++
                    Add-Log "  -> WARNING: ไม่พบไฟล์ผลลัพธ์ (exit code $($r.ExitCode) - อาจไม่มีเฟรมสำหรับ tag/layer นี้)"
                }
            } catch {
                $errors++
                Add-Log "  -> ERROR: $($_.Exception.Message)"
            }
            $done++
            $progressLabel.Text = "Exported $done / $total"
        }
    }

    Add-Log "--- Export Complete! ($done/$total, errors: $errors) ---"
    $btnExport.Enabled = $true
    Update-Preview
    [System.Windows.Forms.MessageBox]::Show("Export เสร็จสิ้น: $done/$total (errors: $errors)", "Done", "OK", "Information")
})

[void]$form.ShowDialog()

} catch {
    [System.Windows.Forms.MessageBox]::Show("เกิดข้อผิดพลาด:`r`n$($_.Exception.Message)`r`n`r`n$($_.InvocationInfo.PositionMessage)", "Aseprite Export - Error", "OK", "Error") | Out-Null
}
