Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

# ต้องเรียกก่อนสร้างคอนโทรลตัวแรก ไม่งั้นหน้าตาจะเป็นธีมเก่าสไตล์ Windows 98
[System.Windows.Forms.Application]::EnableVisualStyles()
try { [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false) } catch { }

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

# Test-Path จะ throw ถ้าส่งค่าว่างหรือ path ที่มีอักขระต้องห้ามเข้าไป
function Test-PathSafe([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    try { return (Test-Path -LiteralPath $path) } catch { return $false }
}

# ---------- Aseprite CLI ----------
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

# ---------- กล่องเลือกโฟลเดอร์ ----------
# FolderBrowserDialog ของ .NET Framework เป็นกล่อง tree view รุ่นเก่า
# ตัวที่หน้าตาเหมือนกล่องเลือกไฟล์คือ IFileDialog ของ Vista+ เปิดโหมด FOS_PICKFOLDERS
# คอมไพล์ตอนเรียกใช้ครั้งแรกเท่านั้น จะได้ไม่ถ่วงเวลาเปิดโปรแกรม
$script:folderPickerReady = $false

function Initialize-FolderPicker {
    if ($script:folderPickerReady) { return }
    $code = @'
using System;
using System.Runtime.InteropServices;

public static class ModernFolderPicker
{
    [ComImport, Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem
    {
        void BindToHandler(IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid bhid, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, out IntPtr ppv);
        void GetParent(out IShellItem ppsi);
        void GetDisplayName(uint sigdnName, [MarshalAs(UnmanagedType.LPWStr)] out string ppszName);
        void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
        void Compare(IShellItem psi, uint hint, out int piOrder);
    }

    [ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileDialog
    {
        [PreserveSig] int Show(IntPtr parent);
        void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
        void SetFileTypeIndex(uint iFileType);
        void GetFileTypeIndex(out uint piFileType);
        void Advise(IntPtr pfde, out uint pdwCookie);
        void Unadvise(uint dwCookie);
        void SetOptions(uint fos);
        void GetOptions(out uint pfos);
        void SetDefaultFolder(IShellItem psi);
        void SetFolder(IShellItem psi);
        void GetFolder(out IShellItem ppsi);
        void GetCurrentSelection(out IShellItem ppsi);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
        void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        void GetResult(out IShellItem ppsi);
        void AddPlace(IShellItem psi, int fdap);
        void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
        void Close([MarshalAs(UnmanagedType.Error)] int hr);
        void SetClientGuid([MarshalAs(UnmanagedType.LPStruct)] Guid guid);
        void ClearClientData();
        void SetFilter(IntPtr pFilter);
    }

    [ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
    private class FileOpenDialogCoClass { }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SHCreateItemFromParsingName(
        [MarshalAs(UnmanagedType.LPWStr)] string pszPath,
        IntPtr pbc,
        [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out object ppv);

    private const uint FOS_PICKFOLDERS     = 0x00000020;
    private const uint FOS_FORCEFILESYSTEM = 0x00000040;
    private const uint FOS_PATHMUSTEXIST   = 0x00000800;
    private const uint SIGDN_FILESYSPATH   = 0x80058000;
    private static readonly Guid IID_IShellItem = new Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe");

    public static string Show(IntPtr owner, string initialPath, string title)
    {
        IFileDialog dlg = (IFileDialog)new FileOpenDialogCoClass();
        try
        {
            uint opts;
            dlg.GetOptions(out opts);
            dlg.SetOptions(opts | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
            if (!string.IsNullOrEmpty(title)) { dlg.SetTitle(title); }

            if (!string.IsNullOrEmpty(initialPath) && System.IO.Directory.Exists(initialPath))
            {
                object item;
                SHCreateItemFromParsingName(initialPath, IntPtr.Zero, IID_IShellItem, out item);
                if (item != null) { dlg.SetFolder((IShellItem)item); }
            }

            if (dlg.Show(owner) != 0) { return null; }   // ผู้ใช้กด Cancel

            IShellItem result;
            dlg.GetResult(out result);
            string path;
            result.GetDisplayName(SIGDN_FILESYSPATH, out path);
            Marshal.ReleaseComObject(result);
            return path;
        }
        finally
        {
            Marshal.ReleaseComObject(dlg);
        }
    }
}
'@
    Add-Type -TypeDefinition $code -Language CSharp
    $script:folderPickerReady = $true
}

function Select-Folder([string]$initial, [string]$title) {
    try {
        Initialize-FolderPicker
        return [ModernFolderPicker]::Show($form.Handle, $initial, $title)
    } catch {
        # เครื่องที่เรียก IFileDialog ไม่ได้ ให้ถอยไปใช้กล่องเดิม
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = $title
        if (Test-PathSafe $initial) { $fbd.SelectedPath = $initial }
        if ($fbd.ShowDialog() -eq "OK") { return $fbd.SelectedPath }
        return $null
    }
}

function Split-Lines([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    return @($text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
}

# หา Aseprite.exe เองจากที่ติดตั้งยอดฮิต รวม Steam library ทุกไดรฟ์
function Find-Aseprite {
    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add("$env:ProgramFiles\Aseprite\Aseprite.exe")
    $candidates.Add("${env:ProgramFiles(x86)}\Aseprite\Aseprite.exe")
    $candidates.Add("$env:LOCALAPPDATA\Programs\Aseprite\Aseprite.exe")
    $candidates.Add("$env:LOCALAPPDATA\itch\apps\aseprite\Aseprite.exe")

    try {
        $steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath
        if ($steam) {
            $steam = $steam -replace "/", "\"
            $candidates.Add((Join-Path $steam "steamapps\common\Aseprite\Aseprite.exe"))
            $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
            if (Test-PathSafe $vdf) {
                $raw = Get-Content -LiteralPath $vdf -Raw
                foreach ($m in [regex]::Matches($raw, '"path"\s*"([^"]+)"')) {
                    $lib = $m.Groups[1].Value -replace '\\\\', '\'
                    $candidates.Add((Join-Path $lib "steamapps\common\Aseprite\Aseprite.exe"))
                }
            }
        }
    } catch { }

    foreach ($c in $candidates) { if (Test-PathSafe $c) { return $c } }
    return $null
}

$settings = Load-Settings

# ---------- ธีม ----------
$clrAccent   = [System.Drawing.Color]::FromArgb(56, 142, 60)
$clrAccentHi = [System.Drawing.Color]::FromArgb(46, 125, 50)
$clrMuted    = [System.Drawing.Color]::FromArgb(110, 110, 110)
$fontUI      = New-Object System.Drawing.Font("Segoe UI", 9)
$fontSmall   = New-Object System.Drawing.Font("Segoe UI", 8)

$form = New-Object System.Windows.Forms.Form
$form.Text = "Aseprite Batch Sprite Sheet Exporter"
$form.ClientSize = New-Object System.Drawing.Size(704, 700)
$form.MinimumSize = New-Object System.Drawing.Size(680, 660)
$form.StartPosition = "CenterScreen"
$form.Font = $fontUI
$form.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)

$CW = 684   # ความกว้างพื้นที่ใช้งานจริงหลังหัก padding

$tip = New-Object System.Windows.Forms.ToolTip
$tip.AutoPopDelay = 8000

function New-Label($text, $x, $y, $w, $h=18) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    return $l
}

function New-Button($text, $x, $y, $w, $h=25) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = "System"
    return $b
}

function New-TextBox($x, $y, $w) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($x, $y)
    $t.Size = New-Object System.Drawing.Size($w, 23)
    return $t
}

# ---------- 1. ไฟล์ ----------
$grpFiles = New-Object System.Windows.Forms.GroupBox
$grpFiles.Text = " ไฟล์ "
$grpFiles.Dock = "Top"
# ต้องตั้งความกว้างจริงก่อนใส่คอนโทรลลูก ไม่งั้น Anchor="Right" จะคำนวณระยะขอบจากขนาด default
$grpFiles.Size = New-Object System.Drawing.Size($CW, 110)

$lblExe = New-Label "Aseprite:" 12 26 62
$grpFiles.Controls.Add($lblExe)
$txtExe = New-TextBox 76 24 380
$txtExe.Anchor = "Top,Left,Right"
if ($settings -and $settings.AsepritePath) { $txtExe.Text = $settings.AsepritePath }
$grpFiles.Controls.Add($txtExe)
$btnExeAuto = New-Button "ค้นหาให้" 464 23 104
$btnExeAuto.Anchor = "Top,Right"
$tip.SetToolTip($btnExeAuto, "ค้นหา Aseprite.exe อัตโนมัติจากที่ติดตั้งทั่วไป รวม Steam library")
$grpFiles.Controls.Add($btnExeAuto)
$btnExe = New-Button "Browse..." 576 23 96
$btnExe.Anchor = "Top,Right"
$grpFiles.Controls.Add($btnExe)

$lblFile = New-Label "ไฟล์งาน:" 12 58 62
$grpFiles.Controls.Add($lblFile)
$txtFile = New-TextBox 76 56 380
$txtFile.Anchor = "Top,Left,Right"
if ($settings -and $settings.FilePath) { $txtFile.Text = $settings.FilePath }
$grpFiles.Controls.Add($txtFile)
$btnScan = New-Button "สแกนใหม่" 464 55 104
$btnScan.Anchor = "Top,Right"
$tip.SetToolTip($btnScan, "อ่าน layer และ tag ที่มีอยู่ในไฟล์ .aseprite ขึ้นมาใหม่")
$grpFiles.Controls.Add($btnScan)
$btnFile = New-Button "Browse..." 576 55 96
$btnFile.Anchor = "Top,Right"
$grpFiles.Controls.Add($btnFile)

$lblHint = New-Label "ลากไฟล์ .aseprite มาวางบนหน้าต่างนี้ได้เลย" 76 84 520 16
$lblHint.ForeColor = $clrMuted
$lblHint.Font = $fontSmall
$grpFiles.Controls.Add($lblHint)

# ---------- 2. Layers / Tags ----------
function New-ListGroup($title) {
    $grp = New-Object System.Windows.Forms.GroupBox
    $grp.Text = " $title "
    $grp.Dock = "Fill"
    $grp.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 6)

    $lst = New-Object System.Windows.Forms.CheckedListBox
    $lst.Dock = "Fill"
    $lst.CheckOnClick = $true
    $lst.IntegralHeight = $false
    $lst.BorderStyle = "FixedSingle"

    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.Dock = "Bottom"
    $pnl.Height = 34

    $btnAll  = New-Button "ทั้งหมด" 0 6 84 26
    $btnNone = New-Button "ล้าง" 88 6 60 26
    $btnAdd  = New-Button "+ เพิ่มเอง" 152 6 96 26
    $pnl.Controls.Add($btnAll)
    $pnl.Controls.Add($btnNone)
    $pnl.Controls.Add($btnAdd)

    # ตัว Fill ต้อง Add ก่อน ไม่งั้นมันจะกินพื้นที่ทับตัวที่ชิดขอบ
    $grp.Controls.Add($lst)
    $grp.Controls.Add($pnl)

    return [PSCustomObject]@{
        Group = $grp; List = $lst; All = $btnAll; None = $btnNone; Add = $btnAdd
    }
}

$uiLayers = New-ListGroup "Layers"
$uiTags   = New-ListGroup "Tags"
$grpLayers = $uiLayers.Group; $lstLayers = $uiLayers.List
$grpTags   = $uiTags.Group;   $lstTags   = $uiTags.List

$tlpLists = New-Object System.Windows.Forms.TableLayoutPanel
$tlpLists.Dock = "Fill"
$tlpLists.ColumnCount = 2
$tlpLists.RowCount = 1
[void]$tlpLists.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
[void]$tlpLists.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$tlpLists.Controls.Add($grpLayers, 0, 0)
$tlpLists.Controls.Add($grpTags, 1, 0)

# ---------- 3. พรีวิว / Log ----------
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = "Fill"

$tabPreview = New-Object System.Windows.Forms.TabPage
$tabPreview.Text = "พรีวิวชื่อไฟล์"
$tabPreview.UseVisualStyleBackColor = $true
$tabs.TabPages.Add($tabPreview)

$lstPreview = New-Object System.Windows.Forms.ListBox
$lstPreview.Dock = "Fill"
$lstPreview.IntegralHeight = $false
$lstPreview.HorizontalScrollbar = $true
$lstPreview.BorderStyle = "None"
$tip.SetToolTip($lstPreview, "ดับเบิลคลิกเพื่อเปิดไฟล์ (ถ้ามีอยู่แล้ว)")
$tabPreview.Controls.Add($lstPreview)

$tabSheet = New-Object System.Windows.Forms.TabPage
$tabSheet.Text = "Sheet type"
$tabSheet.UseVisualStyleBackColor = $true
$tabs.TabPages.Add($tabSheet)

# ภาพจริงที่เรนเดอร์จาก Aseprite
# ไม่ใช้ Dock=Fill เพราะแท็บที่ยังไม่เคยถูกเปิดจะคำนวณความสูงตั้งแต่ตอนหน้ายังเล็ก
# แล้วค้างที่ 0 ไม่คำนวณใหม่อีก จึงกำหนดขอบเขตเองใน Update-SheetTabLayout
$picReal = New-Object System.Windows.Forms.PictureBox
$picReal.BackColor = [System.Drawing.Color]::White
$tabSheet.Controls.Add($picReal)

$pnlSheetBar = New-Object System.Windows.Forms.Panel
$pnlSheetBar.Dock = "Top"
$pnlSheetBar.Size = New-Object System.Drawing.Size($CW, 30)
$btnRenderReal = New-Button "เรนเดอร์ตัวอย่างจริง" 4 2 150 25
$tip.SetToolTip($btnRenderReal, "ให้ Aseprite export คู่แรกที่ติ๊กไว้ออกมาดูของจริง ตาม sheet type ที่เลือก")
$pnlSheetBar.Controls.Add($btnRenderReal)
$lblSheetInfo = New-Label "เลือก sheet type จากผังด้านบน แล้วกดปุ่มนี้เพื่อดูภาพจริง" 162 8 500
$lblSheetInfo.ForeColor = $clrMuted
$pnlSheetBar.Controls.Add($lblSheetInfo)
$tabSheet.Controls.Add($pnlSheetBar)

# ผังเปรียบเทียบทั้ง 5 แบบ กดเพื่อเลือกได้เลย
$pnlSheetTypes = New-Object System.Windows.Forms.Panel
$pnlSheetTypes.Dock = "Top"
$pnlSheetTypes.Size = New-Object System.Drawing.Size($CW, 96)
$sheetThumbs = @()
$tx = 4
foreach ($st in @("horizontal","vertical","rows","columns","packed")) {
    $pb = New-Object System.Windows.Forms.PictureBox
    $pb.Location = New-Object System.Drawing.Point($tx, 4)
    $pb.Size = New-Object System.Drawing.Size(120, 88)
    $pb.Tag = $st
    $pb.Cursor = [System.Windows.Forms.Cursors]::Hand
    $tip.SetToolTip($pb, "ใช้ sheet type แบบ $st")
    $pb.Add_Click({ param($sender, $e) $cmbSheet.SelectedItem = [string]$sender.Tag })
    $pnlSheetTypes.Controls.Add($pb)
    $sheetThumbs += $pb
    $tx += 126
}
$tabSheet.Controls.Add($pnlSheetTypes)

$tabLog = New-Object System.Windows.Forms.TabPage
$tabLog.Text = "Log"
$tabLog.UseVisualStyleBackColor = $true
$tabs.TabPages.Add($tabLog)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Dock = "Fill"
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.BorderStyle = "None"
$logBox.BackColor = [System.Drawing.Color]::White
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$tabLog.Controls.Add($logBox)

# ลาก splitter ปรับสัดส่วนระหว่างลิสต์กับพรีวิวได้เอง
$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = "Fill"
$split.Orientation = "Horizontal"
$split.SplitterWidth = 7
$split.Panel1MinSize = 110
$split.Panel2MinSize = 110
$split.Panel1.Controls.Add($tlpLists)
$split.Panel2.Controls.Add($tabs)

# ---------- 4. ตั้งค่า export ----------
$grpOpt = New-Object System.Windows.Forms.GroupBox
$grpOpt.Text = " ตั้งค่า Export "
$grpOpt.Dock = "Bottom"
$grpOpt.Size = New-Object System.Drawing.Size($CW, 92)

$grpOpt.Controls.Add((New-Label "Sheet type:" 12 26 72))
$cmbSheet = New-Object System.Windows.Forms.ComboBox
$cmbSheet.Location = New-Object System.Drawing.Point(86, 23)
$cmbSheet.Size = New-Object System.Drawing.Size(130, 23)
$cmbSheet.DropDownStyle = "DropDownList"
[void]$cmbSheet.Items.AddRange(@("horizontal","vertical","rows","columns","packed"))
$cmbSheet.SelectedIndex = 0
if ($settings -and $settings.SheetType) { $cmbSheet.SelectedItem = $settings.SheetType }
$grpOpt.Controls.Add($cmbSheet)

$chkIgnoreEmpty = New-Object System.Windows.Forms.CheckBox
$chkIgnoreEmpty.Text = "ข้ามเฟรมว่าง"
$chkIgnoreEmpty.Location = New-Object System.Drawing.Point(232, 24)
$chkIgnoreEmpty.Size = New-Object System.Drawing.Size(170, 22)
$chkIgnoreEmpty.Checked = $true
if ($settings -and ($settings.PSObject.Properties.Name -contains "IgnoreEmpty")) { $chkIgnoreEmpty.Checked = [bool]$settings.IgnoreEmpty }
$tip.SetToolTip($chkIgnoreEmpty, "ส่ง --ignore-empty ให้ Aseprite (ไม่เอาเฟรมที่ว่างเปล่า)")
$grpOpt.Controls.Add($chkIgnoreEmpty)

$lblPrefix = New-Label "ชื่อนำหน้า:" 416 26 74
$lblPrefix.Anchor = "Top,Right"
$grpOpt.Controls.Add($lblPrefix)
$txtPrefix = New-TextBox 492 23 180
$txtPrefix.Anchor = "Top,Right"
$tip.SetToolTip($txtPrefix, "เว้นว่างไว้ = ใช้ชื่อไฟล์ .aseprite")
if ($settings -and $settings.Prefix) { $txtPrefix.Text = $settings.Prefix }
$grpOpt.Controls.Add($txtPrefix)

$grpOpt.Controls.Add((New-Label "โฟลเดอร์ปลายทาง:" 12 58 110))
$txtOutFolder = New-TextBox 126 55 330
$txtOutFolder.Anchor = "Top,Left,Right"
if ($settings -and $settings.OutputFolder) { $txtOutFolder.Text = $settings.OutputFolder }
$grpOpt.Controls.Add($txtOutFolder)
$btnOutFolder = New-Button "Browse..." 464 54 104
$btnOutFolder.Anchor = "Top,Right"
$grpOpt.Controls.Add($btnOutFolder)
$btnOpenOut = New-Button "เปิดโฟลเดอร์" 576 54 96
$btnOpenOut.Anchor = "Top,Right"
$grpOpt.Controls.Add($btnOpenOut)

# ---------- 5. แถบปุ่มล่างสุด ----------
$pnlAction = New-Object System.Windows.Forms.Panel
$pnlAction.Dock = "Bottom"
$pnlAction.Size = New-Object System.Drawing.Size($CW, 52)

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "Export"
$btnExport.Location = New-Object System.Drawing.Point(12, 9)
$btnExport.Size = New-Object System.Drawing.Size(140, 34)
$btnExport.FlatStyle = "Flat"
$btnExport.FlatAppearance.BorderSize = 0
$btnExport.FlatAppearance.MouseOverBackColor = $clrAccentHi
$btnExport.BackColor = $clrAccent
$btnExport.ForeColor = [System.Drawing.Color]::White
$btnExport.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$pnlAction.Controls.Add($btnExport)

$btnCancel = New-Button "ยกเลิก" 160 9 90 34
$btnCancel.Enabled = $false
$pnlAction.Controls.Add($btnCancel)

$prg = New-Object System.Windows.Forms.ProgressBar
$prg.Location = New-Object System.Drawing.Point(262, 16)
$prg.Size = New-Object System.Drawing.Size(292, 20)
$prg.Anchor = "Top,Left,Right"
$pnlAction.Controls.Add($prg)

$lblStatus = New-Label "" 562 15 110 22
$lblStatus.Anchor = "Top,Right"
$lblStatus.TextAlign = "MiddleRight"
$pnlAction.Controls.Add($lblStatus)

# ตัว Fill ต้อง Add ก่อน แล้วไล่ตัวชิดขอบทีหลัง (ตัวที่ Add ท้ายสุดจะอยู่นอกสุด)
$form.Controls.Add($split)
$form.Controls.Add($grpFiles)
$form.Controls.Add($grpOpt)
$form.Controls.Add($pnlAction)

# ---------- Log ----------
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

$uiLayers.All.Add_Click({  Set-AllChecked $lstLayers $true })
$uiLayers.None.Add_Click({ Set-AllChecked $lstLayers $false })
$uiLayers.Add.Add_Click({  Add-ManualItem $lstLayers "Layer" })
$uiTags.All.Add_Click({    Set-AllChecked $lstTags $true })
$uiTags.None.Add_Click({   Set-AllChecked $lstTags $false })
$uiTags.Add.Add_Click({    Add-ManualItem $lstTags "Tag" })

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

$script:isExporting = $false

function Update-Preview {
    $outFolder = $txtOutFolder.Text.Trim().Trim('"')
    $prefix    = Get-EffectivePrefix
    $layers    = Get-CheckedItems $lstLayers
    $tags      = Get-CheckedItems $lstTags

    $grpLayers.Text = " Layers — เลือก $($layers.Count) / $($lstLayers.Items.Count) "
    $grpTags.Text   = " Tags — เลือก $($tags.Count) / $($lstTags.Items.Count) "

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

    if (-not $script:isExporting) {
        $btnExport.Enabled = ($layers.Count -gt 0 -and $tags.Count -gt 0)
        $btnExport.BackColor = if ($btnExport.Enabled) { $clrAccent } else { [System.Drawing.SystemColors]::ControlDark }
    }
}

$previewTimer = New-Object System.Windows.Forms.Timer
$previewTimer.Interval = 60
$previewTimer.Add_Tick({ $previewTimer.Stop(); Update-Preview })

# รวบหลาย ๆ event ที่เกิดติด ๆ กัน (เช่นกด "ทั้งหมด") ให้อัปเดตรอบเดียว
function Queue-Preview {
    $previewTimer.Stop()
    $previewTimer.Start()
}

$lstLayers.Add_ItemCheck({ Queue-Preview })
$lstTags.Add_ItemCheck({ Queue-Preview })
$txtPrefix.Add_TextChanged({ Queue-Preview })
$txtOutFolder.Add_TextChanged({ Queue-Preview })
$txtFile.Add_TextChanged({ Queue-Preview })

$lstPreview.Add_DoubleClick({
    if ($null -eq $lstPreview.SelectedItem) { return }
    $name = (([string]$lstPreview.SelectedItem) -split '\s+<<')[0].Trim()
    $full = Join-Path $txtOutFolder.Text.Trim().Trim('"') $name
    if (Test-PathSafe $full) { Start-Process $full }
})

# ---------- พรีวิว Sheet type ----------
# ตำแหน่ง [คอลัมน์, แถว] ของแต่ละเฟรมตามวิธีจัดเรียงของ Aseprite
function Get-FrameLayout([string]$type, [int]$n) {
    $pos = @()
    if ($type -eq "vertical") {
        for ($i = 0; $i -lt $n; $i++) { $pos += ,@(0, $i) }
        return [PSCustomObject]@{ Pos = $pos; Cols = 1; Rows = $n }
    }
    if ($type -eq "horizontal") {
        for ($i = 0; $i -lt $n; $i++) { $pos += ,@($i, 0) }
        return [PSCustomObject]@{ Pos = $pos; Cols = $n; Rows = 1 }
    }
    if ($type -eq "columns") {
        $rows = [int][Math]::Ceiling([Math]::Sqrt($n))
        $cols = [int][Math]::Ceiling($n / [double]$rows)
        for ($i = 0; $i -lt $n; $i++) { $pos += ,@([int][Math]::Floor($i / $rows), ($i % $rows)) }
        return [PSCustomObject]@{ Pos = $pos; Cols = $cols; Rows = $rows }
    }
    $cols = [int][Math]::Ceiling([Math]::Sqrt($n))
    $rows = [int][Math]::Ceiling($n / [double]$cols)
    for ($i = 0; $i -lt $n; $i++) { $pos += ,@(($i % $cols), [int][Math]::Floor($i / $cols)) }
    return [PSCustomObject]@{ Pos = $pos; Cols = $cols; Rows = $rows }
}

# packed ขึ้นกับรูปร่างเฟรมจริง วาดเป็นตัวอย่างเฟรมคนละขนาดวางชิดกัน [คอลัมน์,แถว,กว้าง,สูง]
$packedCells = @(@(0,0,2,2), @(2,0,1,1), @(2,1,1,2), @(0,2,2,1))

function New-SheetThumb([string]$type, [bool]$active) {
    $w = 120; $h = 88
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::White)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

    $edge     = if ($active) { $clrAccent } else { [System.Drawing.Color]::FromArgb(205, 205, 205) }
    $cellFill = if ($active) { [System.Drawing.Color]::FromArgb(198, 228, 199) } else { [System.Drawing.Color]::FromArgb(232, 232, 232) }
    $cellEdge = if ($active) { $clrAccent } else { [System.Drawing.Color]::FromArgb(170, 170, 170) }
    $textCol  = if ($active) { $clrAccentHi } else { [System.Drawing.Color]::FromArgb(90, 90, 90) }

    $pen = New-Object System.Drawing.Pen($edge, $(if ($active) { 2 } else { 1 }))
    $g.DrawRectangle($pen, 1, 1, ($w - 3), ($h - 3))

    $style = if ($active) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $fTitle = New-Object System.Drawing.Font("Segoe UI", 8, $style)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $brTitle = New-Object System.Drawing.SolidBrush($textCol)
    $g.DrawString($type, $fTitle, $brTitle, (New-Object System.Drawing.RectangleF(0, 4, $w, 18)), $sf)

    $ax = 10; $ay = 24; $aw = $w - 20; $ah = $h - 32
    $brCell = New-Object System.Drawing.SolidBrush($cellFill)
    $penCell = New-Object System.Drawing.Pen($cellEdge, 1)
    $fNum = New-Object System.Drawing.Font("Segoe UI", 6.5)
    $brNum = New-Object System.Drawing.SolidBrush($textCol)

    if ($type -eq "packed") {
        $cell = [int][Math]::Floor([Math]::Min($aw / 3.0, $ah / 3.0))
        $ox = $ax + [int](($aw - $cell * 3) / 2)
        $oy = $ay + [int](($ah - $cell * 3) / 2)
        $i = 1
        foreach ($c in $packedCells) {
            $x = $ox + $c[0] * $cell; $y = $oy + $c[1] * $cell
            $cw = $c[2] * $cell; $ch = $c[3] * $cell
            $g.FillRectangle($brCell, $x, $y, $cw, $ch)
            $g.DrawRectangle($penCell, $x, $y, $cw, $ch)
            $g.DrawString("$i", $fNum, $brNum, (New-Object System.Drawing.RectangleF($x, $y, $cw, $ch)), $sf)
            $i++
        }
    } else {
        $lay = Get-FrameLayout $type 4
        $cell = [int][Math]::Floor([Math]::Min($aw / [double]$lay.Cols, $ah / [double]$lay.Rows))
        if ($cell -lt 6) { $cell = 6 }
        $ox = $ax + [int](($aw - $cell * $lay.Cols) / 2)
        $oy = $ay + [int](($ah - $cell * $lay.Rows) / 2)
        $i = 1
        foreach ($p in $lay.Pos) {
            $x = $ox + $p[0] * $cell; $y = $oy + $p[1] * $cell
            $g.FillRectangle($brCell, $x, $y, ($cell - 2), ($cell - 2))
            $g.DrawRectangle($penCell, $x, $y, ($cell - 2), ($cell - 2))
            $g.DrawString("$i", $fNum, $brNum, (New-Object System.Drawing.RectangleF($x, $y, ($cell - 2), ($cell - 2))), $sf)
            $i++
        }
    }

    $g.Dispose()
    return $bmp
}

function Update-SheetThumbs {
    $sel = [string]$cmbSheet.SelectedItem
    foreach ($pb in $sheetThumbs) {
        $old = $pb.Image
        $pb.Image = New-SheetThumb ([string]$pb.Tag) ([string]$pb.Tag -eq $sel)
        if ($old) { $old.Dispose() }
    }
}

# พื้นหลังลายหมากรุกไว้ดูส่วนที่โปร่งใส
$checkTile = New-Object System.Drawing.Bitmap 16, 16
$gt = [System.Drawing.Graphics]::FromImage($checkTile)
$gt.Clear([System.Drawing.Color]::White)
$brGray = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(236, 236, 236))
$gt.FillRectangle($brGray, 0, 0, 8, 8)
$gt.FillRectangle($brGray, 8, 8, 8, 8)
$gt.Dispose()
$checkBrush = New-Object System.Drawing.TextureBrush($checkTile)

$script:realBmp = $null

function Update-SheetTabLayout {
    $top = $pnlSheetTypes.Height + $pnlSheetBar.Height
    $w = $tabSheet.ClientSize.Width
    $h = $tabSheet.ClientSize.Height - $top
    # แท็บที่ยังไม่ถูก layout จริงจะรายงานขนาด default ออกมา อย่าเอาไปย่อคอนโทรล
    if ($w -lt 100 -or $h -lt 20) { return }
    if ($picReal.Bounds.Y -ne $top -or $picReal.Width -ne $w -or $picReal.Height -ne $h) {
        $picReal.SetBounds(0, $top, $w, $h)
    }
}

$script:inShowReal = $false

function Show-RealImage {
    if ($script:inShowReal) { return }   # SetBounds ด้านล่างจะยิง Resize กลับเข้ามาอีกรอบ
    $script:inShowReal = $true
    try { Show-RealImageCore } finally { $script:inShowReal = $false }
}

function Show-RealImageCore {
    Update-SheetTabLayout
    $cw = $picReal.ClientSize.Width
    $ch = $picReal.ClientSize.Height
    if ($cw -lt 8 -or $ch -lt 8) { return }

    $canvas = New-Object System.Drawing.Bitmap $cw, $ch
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.FillRectangle($checkBrush, 0, 0, $cw, $ch)

    if ($null -ne $script:realBmp) {
        $iw = $script:realBmp.Width; $ih = $script:realBmp.Height
        $scale = [Math]::Min($cw / [double]$iw, $ch / [double]$ih)
        if ($scale -gt 1) { $scale = [Math]::Floor($scale) }   # ขยายเป็นจำนวนเต็มเพื่อให้พิกเซลคม
        $dw = [Math]::Max(1, [int]($iw * $scale))
        $dh = [Math]::Max(1, [int]($ih * $scale))
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        $g.DrawImage($script:realBmp, [int](($cw - $dw) / 2), [int](($ch - $dh) / 2), $dw, $dh)
    }

    $g.Dispose()
    $old = $picReal.Image
    $picReal.Image = $canvas
    if ($old) { $old.Dispose() }
}

function Clear-RealImage($message) {
    if ($null -ne $script:realBmp) { $script:realBmp.Dispose(); $script:realBmp = $null }
    $lblSheetInfo.Text = $message
    Show-RealImage
}

function Invoke-SheetRender {
    $exePath  = $txtExe.Text.Trim().Trim('"')
    $filePath = $txtFile.Text.Trim().Trim('"')
    if (-not (Test-PathSafe $exePath) -or -not (Test-PathSafe $filePath)) {
        [System.Windows.Forms.MessageBox]::Show("ต้องระบุ Aseprite.exe และไฟล์ .aseprite ให้ถูกต้องก่อน", "เรนเดอร์ตัวอย่าง", "OK", "Error")
        return
    }
    $layers = Get-CheckedItems $lstLayers
    $tags   = Get-CheckedItems $lstTags
    if ($layers.Count -eq 0 -or $tags.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("ติ๊กเลือก Layer และ Tag อย่างน้อยอย่างละ 1 รายการก่อน", "เรนเดอร์ตัวอย่าง", "OK", "Information")
        return
    }

    $layer = $layers[0]
    $tag   = $tags[0]
    $type  = [string]$cmbSheet.SelectedItem
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "aseprite_sheet_preview_$PID.png"
    if (Test-PathSafe $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }

    $argList = @("-b", "--layer", $layer, "--frame-tag", $tag, $filePath)
    if ($chkIgnoreEmpty.Checked) { $argList += "--ignore-empty" }
    $argList += @("--sheet-type", $type, "--sheet", $tmp)

    # ถ้าพื้นที่แสดงผลเตี้ยเกินจะดูอะไรไม่ออก เลื่อน splitter ขึ้นให้เอง
    if ($picReal.ClientSize.Height -lt 140) {
        $need = 160 - $picReal.ClientSize.Height
        $want = [Math]::Max($split.Panel1MinSize, ($split.SplitterDistance - $need))
        try { $split.SplitterDistance = $want } catch { }
        Update-SheetTabLayout
    }

    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $btnRenderReal.Enabled = $false
    try {
        $r = Invoke-Aseprite $exePath $argList
        if (Test-PathSafe $tmp) {
            # อ่านใส่หน่วยความจำก่อน ไม่งั้นไฟล์จะถูกล็อกจนลบไม่ได้
            $bytes = [System.IO.File]::ReadAllBytes($tmp)
            $ms = New-Object System.IO.MemoryStream(,$bytes)
            if ($null -ne $script:realBmp) { $script:realBmp.Dispose() }
            $script:realBmp = [System.Drawing.Image]::FromStream($ms)
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            $lblSheetInfo.Text = "$layer / $tag  —  $type  —  $($script:realBmp.Width) x $($script:realBmp.Height) px"
            Show-RealImage
        } else {
            Clear-RealImage "เรนเดอร์ไม่สำเร็จ (exit code $($r.ExitCode)) ดูรายละเอียดในแท็บ Log"
            Add-Log "--- Sheet preview: $layer / $tag ---"
            if (-not [string]::IsNullOrWhiteSpace($r.Out)) { Add-Log $r.Out.TrimEnd() }
            if (-not [string]::IsNullOrWhiteSpace($r.Err)) { Add-Log $r.Err.TrimEnd() }
        }
    } catch {
        Clear-RealImage "เรนเดอร์ไม่สำเร็จ: $($_.Exception.Message)"
    } finally {
        $btnRenderReal.Enabled = $true
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

$btnRenderReal.Add_Click({ Invoke-SheetRender })
$picReal.Add_Resize({ Show-RealImage })
$tabSheet.Add_Resize({ Update-SheetTabLayout })
$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabSheet) { Update-SheetTabLayout; Show-RealImage }
})
$split.Add_SplitterMoved({
    if ($tabs.SelectedTab -eq $tabSheet) { Update-SheetTabLayout }
})
$cmbSheet.Add_SelectedIndexChanged({
    Update-SheetThumbs
    if ($null -ne $script:realBmp) {
        Clear-RealImage "เปลี่ยน sheet type แล้ว กด 'เรนเดอร์ตัวอย่างจริง' เพื่อดูของจริงอีกครั้ง"
    }
})

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

# ---------- เลือกไฟล์ / ลากมาวาง ----------
function Set-SourceFile($path) {
    $txtFile.Text = $path
    if ([string]::IsNullOrWhiteSpace($txtPrefix.Text)) {
        $txtPrefix.Text = [System.IO.Path]::GetFileNameWithoutExtension($path)
    }
    if ([string]::IsNullOrWhiteSpace($txtOutFolder.Text)) {
        $txtOutFolder.Text = [System.IO.Path]::GetDirectoryName($path)
    }
    Invoke-Scan
}

$onDragEnter = {
    param($sender, $e)
    if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
    }
}
$onDragDrop = {
    param($sender, $e)
    foreach ($f in $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)) {
        if ($f -match '\.exe$')            { $txtExe.Text = $f; continue }
        if ($f -match '\.(aseprite|ase)$') { Set-SourceFile $f; break }
    }
}
function Enable-Drop($ctrl) {
    $ctrl.AllowDrop = $true
    $ctrl.Add_DragEnter($onDragEnter)
    $ctrl.Add_DragDrop($onDragDrop)
}
Enable-Drop $form
Enable-Drop $grpFiles
Enable-Drop $lstLayers
Enable-Drop $lstTags
Enable-Drop $lstPreview

# ---------- ปุ่มต่าง ๆ ----------
$btnExe.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "Aseprite|Aseprite.exe;aseprite.exe|Executable|*.exe"
    $ofd.Title = "เลือก Aseprite.exe"
    if ($ofd.ShowDialog() -eq "OK") { $txtExe.Text = $ofd.FileName }
})

$btnExeAuto.Add_Click({
    $found = Find-Aseprite
    if ($found) {
        $txtExe.Text = $found
        Add-Log "พบ Aseprite: $found"
        if (Test-PathSafe $txtFile.Text.Trim().Trim('"')) { Invoke-Scan }
    } else {
        [System.Windows.Forms.MessageBox]::Show("หา Aseprite.exe ไม่เจอตามที่ติดตั้งทั่วไป`r`nกรุณากด Browse... เลือกเอง", "ค้นหา Aseprite", "OK", "Information")
    }
})

$btnFile.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "Aseprite Files|*.aseprite;*.ase|All Files|*.*"
    $ofd.Title = "เลือกไฟล์ .aseprite"
    if ($ofd.ShowDialog() -eq "OK") { Set-SourceFile $ofd.FileName }
})

$btnScan.Add_Click({ Invoke-Scan })

$btnOutFolder.Add_Click({
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $picked = Select-Folder ($txtOutFolder.Text.Trim().Trim('"')) "เลือกโฟลเดอร์ปลายทาง"
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
    if ($picked) { $txtOutFolder.Text = $picked }
})

$btnOpenOut.Add_Click({
    $p = $txtOutFolder.Text.Trim().Trim('"')
    if (Test-PathSafe $p) { Start-Process explorer.exe $p }
    else { [System.Windows.Forms.MessageBox]::Show("ยังไม่มีโฟลเดอร์นี้", "เปิดโฟลเดอร์", "OK", "Information") }
})

$btnCancel.Add_Click({
    $script:cancelRequested = $true
    $btnCancel.Enabled = $false
    Add-Log "-- กำลังยกเลิก รอไฟล์ที่กำลังทำอยู่ให้จบก่อน --"
})

# ---------- ตอนเปิดโปรแกรม ----------
$form.Add_Shown({
    try { $split.SplitterDistance = [int]($split.Height * 0.44) } catch { }
    Update-SheetThumbs
    Update-SheetTabLayout
    Show-RealImage

    if ([string]::IsNullOrWhiteSpace($txtExe.Text)) {
        $found = Find-Aseprite
        if ($found) { $txtExe.Text = $found; Add-Log "พบ Aseprite: $found" }
    }

    if ((Test-PathSafe $txtExe.Text.Trim().Trim('"')) -and (Test-PathSafe $txtFile.Text.Trim().Trim('"'))) {
        Invoke-Scan
    } else {
        Update-Preview
    }
})

# ---------- Export ----------
$btnExport.Add_Click({
    $exePath   = $txtExe.Text.Trim().Trim('"')
    $filePath  = $txtFile.Text.Trim().Trim('"')
    $outFolder = $txtOutFolder.Text.Trim().Trim('"')
    $prefix    = Get-EffectivePrefix
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
        [System.Windows.Forms.MessageBox]::Show("กรุณาระบุโฟลเดอร์ปลายทาง", "Error", "OK", "Error")
        return
    }
    if (-not (Test-PathSafe $outFolder)) { New-Item -ItemType Directory -Path $outFolder -Force | Out-Null }

    $layers = Get-CheckedItems $lstLayers
    $tags   = Get-CheckedItems $lstTags
    if ($layers.Count -eq 0 -or $tags.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("กรุณาติ๊กเลือก Layers และ Tags อย่างน้อยอย่างละ 1 รายการ", "Error", "OK", "Error")
        return
    }

    Save-Settings ([PSCustomObject]@{
        AsepritePath = $exePath
        FilePath     = $filePath
        Layers       = ($layers -join ", ")
        Tags         = ($tags -join ", ")
        SheetType    = $sheetType
        OutputFolder = $outFolder
        Prefix       = $prefix
        IgnoreEmpty  = $chkIgnoreEmpty.Checked
    })

    $logBox.Clear()
    $tabs.SelectedTab = $tabLog
    $script:isExporting = $true
    $script:cancelRequested = $false
    $btnExport.Enabled = $false
    $btnExport.BackColor = [System.Drawing.SystemColors]::ControlDark
    $btnCancel.Enabled = $true

    $total = $layers.Count * $tags.Count
    $done = 0
    $errors = 0
    $prg.Maximum = $total
    $prg.Value = 0
    $lblStatus.Text = "0 / $total"

    Add-Log "--- Exporting Sprites ---"

    :exportLoop foreach ($layer in $layers) {
        foreach ($tag in $tags) {
            $outFile = Join-Path $outFolder (Get-OutFileName $prefix $tag)
            $argList = @("-b", "--frame-tag", $tag, $filePath)
            if ($chkIgnoreEmpty.Checked) { $argList += "--ignore-empty" }
            $argList += @("--sheet-type", $sheetType, "--sheet", $outFile)

            Add-Log "Exporting: $layer - $tag"
            # ลบไฟล์เดิมก่อน เพื่อให้เช็คผลลัพธ์ได้จริงว่ารอบนี้สร้างสำเร็จไหม
            if (Test-PathSafe $outFile) { Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue }
            try {
                $r = Invoke-Aseprite $exePath $argList
                if (-not [string]::IsNullOrWhiteSpace($r.Out)) { Add-Log $r.Out.TrimEnd() }
                if (-not [string]::IsNullOrWhiteSpace($r.Err)) { Add-Log $r.Err.TrimEnd() }
                if (Test-PathSafe $outFile) {
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
            $prg.Value = $done
            $lblStatus.Text = "$done / $total"
            [System.Windows.Forms.Application]::DoEvents()

            if ($script:cancelRequested) { break exportLoop }
        }
    }

    $script:isExporting = $false
    $btnCancel.Enabled = $false

    if ($script:cancelRequested) {
        Add-Log "--- ยกเลิกแล้ว ($done/$total, errors: $errors) ---"
        $lblStatus.Text = "ยกเลิก"
    } else {
        Add-Log "--- Export Complete! ($done/$total, errors: $errors) ---"
        $lblStatus.Text = "เสร็จ $done / $total"
    }

    Update-Preview
    $tabs.SelectedTab = $tabPreview

    $icon = if ($errors -gt 0) { "Warning" } else { "Information" }
    [System.Windows.Forms.MessageBox]::Show("Export $done/$total ไฟล์ (errors: $errors)", "Done", "OK", $icon)
})

[void]$form.ShowDialog()

} catch {
    [System.Windows.Forms.MessageBox]::Show("เกิดข้อผิดพลาด:`r`n$($_.Exception.Message)`r`n`r`n$($_.InvocationInfo.PositionMessage)", "Aseprite Export - Error", "OK", "Error") | Out-Null
}
