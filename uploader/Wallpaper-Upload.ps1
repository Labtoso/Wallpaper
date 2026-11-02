param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module (Join-Path $PSScriptRoot 'Upload-Core.psm1') -Force
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:projectRoot = Split-Path -Parent $PSScriptRoot
$script:selection = New-Object 'System.Collections.Generic.List[object]'
$script:job = $null
$script:busy = $false
$background = [Drawing.Color]::FromArgb(24,24,24)
$panel = [Drawing.Color]::FromArgb(35,35,35)
$foreground = [Drawing.Color]::FromArgb(232,232,232)
$muted = [Drawing.Color]::FromArgb(155,155,155)

$form = New-Object Windows.Forms.Form
$form.Text = 'Wallpaper Upload'
$form.Size = New-Object Drawing.Size(860,790)
$form.MinimumSize = New-Object Drawing.Size(760,680)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $background
$form.ForeColor = $foreground
$form.Font = New-Object Drawing.Font('Segoe UI',10)
$form.AutoScaleMode = 'Dpi'
$iconPath = Join-Path $PSScriptRoot 'wallpaper.ico'
if (Test-Path -LiteralPath $iconPath) { $form.Icon = New-Object Drawing.Icon($iconPath) }

$layout = New-Object Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'; $layout.Padding = New-Object Windows.Forms.Padding(24)
$layout.ColumnCount = 1; $layout.RowCount = 12
foreach ($height in @(42,31,39,24,40,46,0,31,24,108,35,52)) {
    if ($height) { [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$height))) }
    else { [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100))) }
}
$form.Controls.Add($layout)

function New-Label([string]$Text, [single]$Size = 10, [Drawing.Color]$Color = $foreground) {
    $label = New-Object Windows.Forms.Label
    $label.Text=$Text; $label.ForeColor=$Color; $label.AutoSize=$false; $label.Dock='Fill'; $label.TextAlign='MiddleLeft'
    $label.Font=New-Object Drawing.Font('Segoe UI',$Size)
    return $label
}
function New-Button([string]$Text, [int]$Width = 150) {
    $button=New-Object Windows.Forms.Button
    $button.Text=$Text; $button.Width=$Width; $button.Height=34; $button.FlatStyle='Flat'
    $button.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(75,75,75)
    $button.BackColor=$panel; $button.ForeColor=$foreground; $button.Margin=New-Object Windows.Forms.Padding(0,4,10,4)
    return $button
}
$layout.Controls.Add((New-Label 'Wallpaper hochladen' 21),0,0)
$layout.Controls.Add((New-Label 'Pack auswählen, Bilder hinzufügen, hochladen.' 10 $muted),0,1)
$projectRow=New-Object Windows.Forms.TableLayoutPanel
$projectRow.Dock='Fill';$projectRow.ColumnCount=2
[void]$projectRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
[void]$projectRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',110)))
$projectText=New-Object Windows.Forms.TextBox
$projectText.ReadOnly=$true;$projectText.Dock='Fill';$projectText.BackColor=$panel;$projectText.ForeColor=$muted;$projectText.BorderStyle='FixedSingle';$projectText.Text=$script:projectRoot
$browseProject=New-Button 'Projekt …' 100;$browseProject.Dock='Fill'
$projectRow.Controls.Add($projectText,0,0);$projectRow.Controls.Add($browseProject,1,0);$layout.Controls.Add($projectRow,0,2)
$layout.Controls.Add((New-Label 'Pack / Kategorie'),0,3)
$pack=New-Object Windows.Forms.ComboBox
$pack.Dock='Fill';$pack.BackColor=$panel;$pack.ForeColor=$foreground;$pack.FlatStyle='Flat';$pack.DropDownStyle='DropDown';$pack.AccessibleName='Packname'
$layout.Controls.Add($pack,0,4)
$buttons=New-Object Windows.Forms.FlowLayoutPanel
$buttons.Dock='Fill';$buttons.WrapContents=$false
$addFiles=New-Button 'Bilder auswählen' 160
$addFolder=New-Button 'Ordner auswählen' 160
$remove=New-Button 'Aus Auswahl entfernen' 185
$buttons.Controls.AddRange(@($addFiles,$addFolder,$remove));$layout.Controls.Add($buttons,0,5)
$list=New-Object Windows.Forms.ListView
$list.Dock='Fill';$list.View='Details';$list.FullRowSelect=$true;$list.MultiSelect=$true;$list.HideSelection=$false
$list.BackColor=$panel;$list.ForeColor=$foreground;$list.BorderStyle='FixedSingle';$list.AllowDrop=$true
[void]$list.Columns.Add('Datei',230);[void]$list.Columns.Add('Größe',90);[void]$list.Columns.Add('Quelle',380)
$list.OwnerDraw=$true
$list.add_DrawColumnHeader({param($sender,$eventArgs)
    $brush=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(45,45,45));$textBrush=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(215,215,215))
    $eventArgs.Graphics.FillRectangle($brush,$eventArgs.Bounds)
    $eventArgs.Graphics.DrawString($eventArgs.Header.Text,$sender.Font,$textBrush,$eventArgs.Bounds.X+5,$eventArgs.Bounds.Y+3)
    $brush.Dispose();$textBrush.Dispose()
})
$list.add_DrawItem({param($sender,$eventArgs) $eventArgs.DrawDefault=$true})
$list.add_DrawSubItem({param($sender,$eventArgs) $eventArgs.DrawDefault=$true})
$layout.Controls.Add($list,0,6)
$count=New-Label 'Noch keine Bilder ausgewählt.' 9 $muted;$layout.Controls.Add($count,0,7)
$layout.Controls.Add((New-Label 'Per Git statt Web-Upload: bis 100 MiB pro Bild. Originale bleiben unverändert.' 9 $muted),0,8)
$log=New-Object Windows.Forms.TextBox
$log.Multiline=$true;$log.ReadOnly=$true;$log.ScrollBars='Vertical';$log.Dock='Fill';$log.BackColor=$background;$log.ForeColor=$muted;$log.BorderStyle='FixedSingle';$log.Font=New-Object Drawing.Font('Consolas',9)
$layout.Controls.Add($log,0,9)
$options=New-Object Windows.Forms.FlowLayoutPanel
$options.Dock='Fill';$options.WrapContents=$false
$localOnly=New-Object Windows.Forms.CheckBox
$localOnly.Text='Nur lokal hinzufügen';$localOnly.AutoSize=$true;$localOnly.Margin=New-Object Windows.Forms.Padding(0,8,25,0)
$website=New-Object Windows.Forms.LinkLabel
$website.Text='Website öffnen';$website.AutoSize=$true;$website.LinkColor=$foreground;$website.ActiveLinkColor=$foreground;$website.Margin=New-Object Windows.Forms.Padding(0,8,20,0)
$login=New-Object Windows.Forms.LinkLabel
$login.Text='GitHub anmelden';$login.AutoSize=$true;$login.LinkColor=$muted;$login.ActiveLinkColor=$foreground;$login.Margin=New-Object Windows.Forms.Padding(0,8,0,0)
$options.Controls.AddRange(@($localOnly,$website,$login));$layout.Controls.Add($options,0,10)
$bottom=New-Object Windows.Forms.TableLayoutPanel
$bottom.Dock='Fill';$bottom.ColumnCount=2
[void]$bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
[void]$bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',200)))
$progress=New-Object Windows.Forms.ProgressBar
$progress.Dock='Fill';$progress.Style='Marquee';$progress.MarqueeAnimationSpeed=0;$progress.Margin=New-Object Windows.Forms.Padding(0,11,18,11)
$upload=New-Button 'Hochladen' 190;$upload.Dock='Fill';$upload.BackColor=$foreground;$upload.ForeColor=$background
$bottom.Controls.Add($progress,0,0);$bottom.Controls.Add($upload,1,0);$layout.Controls.Add($bottom,0,11)

function Write-Log([string]$Text) { $log.AppendText($Text + [Environment]::NewLine);$log.SelectionStart=$log.TextLength;$log.ScrollToCaret() }
function Update-Packs {
    $current=$pack.Text;$pack.Items.Clear()
    $assets=Join-Path $script:projectRoot 'assets'
    if (Test-Path -LiteralPath $assets) { Get-ChildItem -LiteralPath $assets -Directory | Where-Object {-not $_.Name.StartsWith('.')} | Sort-Object Name | ForEach-Object {[void]$pack.Items.Add($_.Name)} }
    $pack.Text=$current
}
function Refresh-Selection {
    $list.BeginUpdate();$list.Items.Clear();$total=0
    foreach($entry in $script:selection) {
        $file=Get-Item -LiteralPath $entry.SourcePath
        $row=New-Object Windows.Forms.ListViewItem($entry.RelativePath)
        [void]$row.SubItems.Add(('{0:N1} MB' -f ($file.Length/1MB)));[void]$row.SubItems.Add($file.FullName)
        $row.Tag=$entry;[void]$list.Items.Add($row);$total+=$file.Length
    }
    $list.EndUpdate();$count.Text=('{0} Bilder · {1:N1} MB' -f $script:selection.Count,($total/1MB))
}
function Add-Image([string]$Path,[string]$Relative) {
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($file.Extension -notmatch '^\.(jpg|jpeg|png|webp|gif|avif|svg)$' -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){return}
    if(@($script:selection | Where-Object {$_.SourcePath -eq $file.FullName}).Count){return}
    $script:selection.Add([pscustomobject]@{SourcePath=$file.FullName;RelativePath=$Relative})
}
function Add-Directory([string]$Directory,[string]$Base) {
    foreach($entry in Get-ChildItem -LiteralPath $Directory) {
        if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
        if($entry.PSIsContainer){Add-Directory $entry.FullName $Base}
        else{Add-Image $entry.FullName $entry.FullName.Substring($Base.TrimEnd('\').Length+1)}
    }
}
function Set-Busy([bool]$Value) {
    $script:busy=$Value
    foreach($control in @($pack,$browseProject,$addFiles,$addFolder,$remove,$localOnly,$upload,$list,$login)){$control.Enabled=-not $Value}
    $progress.MarqueeAnimationSpeed=if($Value){25}else{0}
    $upload.Text=if($Value){'Bitte warten …'}elseif($localOnly.Checked){'Hinzufügen'}else{'Hochladen'}
}
$browseProject.add_Click({
    $dialog=New-Object Windows.Forms.FolderBrowserDialog;$dialog.Description='Wallpaper-Projektordner mit assets auswählen';$dialog.SelectedPath=$script:projectRoot
    if($dialog.ShowDialog($form) -eq 'OK'){$script:projectRoot=$dialog.SelectedPath;$projectText.Text=$script:projectRoot;Update-Packs}
    $dialog.Dispose()
})
$addFiles.add_Click({
    $dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Multiselect=$true;$dialog.Title='Wallpaper auswählen';$dialog.Filter='Bilder|*.jpg;*.jpeg;*.png;*.webp;*.gif;*.avif;*.svg'
    if($dialog.ShowDialog($form) -eq 'OK'){foreach($file in $dialog.FileNames){Add-Image $file ([IO.Path]::GetFileName($file))};Refresh-Selection}
    $dialog.Dispose()
})
$addFolder.add_Click({
    $dialog=New-Object Windows.Forms.FolderBrowserDialog;$dialog.Description='Bilderordner auswählen';$dialog.ShowNewFolderButton=$false
    if($dialog.ShowDialog($form) -eq 'OK'){if(-not $pack.Text.Trim()){$pack.Text=Split-Path -Leaf $dialog.SelectedPath};Add-Directory $dialog.SelectedPath $dialog.SelectedPath;Refresh-Selection}
    $dialog.Dispose()
})
$remove.add_Click({foreach($row in @($list.SelectedItems)){[void]$script:selection.Remove($row.Tag)};Refresh-Selection})
$list.add_DragEnter({param($sender,$eventArgs)if(-not $script:busy -and $eventArgs.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){$eventArgs.Effect='Copy'}})
$list.add_DragDrop({param($sender,$eventArgs)
    foreach($path in $eventArgs.Data.GetData([Windows.Forms.DataFormats]::FileDrop)){
        if(Test-Path -LiteralPath $path -PathType Container){if(-not $pack.Text.Trim()){$pack.Text=Split-Path -Leaf $path};Add-Directory $path $path}
        else{Add-Image $path ([IO.Path]::GetFileName($path))}
    };Refresh-Selection
})
$localOnly.add_CheckedChanged({$upload.Text=if($localOnly.Checked){'Hinzufügen'}else{'Hochladen'}})
$website.add_LinkClicked({Start-Process 'https://wallpaper.labtoso.de/'})
$login.add_LinkClicked({
    try{$tools=Get-WallpaperTools;Start-Process -FilePath $tools.Gh -ArgumentList @('auth','login','--hostname','github.com','--git-protocol','https','--web') -WindowStyle Normal}
    catch{Write-Log $_.Exception.Message}
})
$timer=New-Object Windows.Forms.Timer;$timer.Interval=250
$timer.add_Tick({
    if(-not $script:job){return}
    foreach($item in Receive-Job -Job $script:job -ErrorAction SilentlyContinue){
        if($item -is [string]){Write-Log $item}
        elseif($item.PSObject.Properties['Success']){Write-Log $(if($item.Published){'Fertig. Die Website wird automatisch aktualisiert.'}else{'Lokal hinzugefügt. Die Vorschau erkennt die Bilder automatisch.'})}
    }
    if($script:job.State -in @('Completed','Failed','Stopped')){
        foreach($errorRecord in $script:job.ChildJobs[0].Error){Write-Log ('Fehler: '+$errorRecord.ToString())}
        if($script:job.State -eq 'Failed' -and $script:job.ChildJobs[0].JobStateInfo.Reason){Write-Log ('Fehler: '+$script:job.ChildJobs[0].JobStateInfo.Reason.Message)}
        Remove-Job -Job $script:job;$script:job=$null;$timer.Stop();Set-Busy $false;Update-Packs
    }
})
$upload.add_Click({
    try{
        if(-not $script:selection.Count){throw 'Bitte zuerst Bilder oder einen Ordner auswählen.'}
        if(-not $pack.Text.Trim()){throw 'Bitte einen Packnamen eingeben oder auswählen.'}
        [void](New-WallpaperUploadPlan -ProjectRoot $script:projectRoot -PackName $pack.Text -Items $script:selection.ToArray())
        $config=@{Module=(Join-Path $PSScriptRoot 'Upload-Core.psm1');Root=$script:projectRoot;Pack=$pack.Text;Items=$script:selection.ToArray();Publish=(-not $localOnly.Checked)}
        $log.Clear();Set-Busy $true
        $script:job=Start-Job -ArgumentList $config -ScriptBlock {param($config)Import-Module $config.Module -Force;Invoke-WallpaperUpload -ProjectRoot $config.Root -PackName $config.Pack -Items $config.Items -Publish:$config.Publish}
        $timer.Start()
    }catch{Set-Busy $false;Write-Log $_.Exception.Message}
})
$form.add_FormClosing({param($sender,$eventArgs)if($script:busy){$eventArgs.Cancel=$true;Write-Log 'Der Upload läuft noch. Bitte bis zum Abschluss warten.'}})
Update-Packs
if($SelfTest){
    $errors=New-Object 'System.Collections.Generic.List[string]'
    if($form.Text -ne 'Wallpaper Upload'){$errors.Add('Wrong title')}
    if($layout.RowCount -ne 12){$errors.Add('Layout incomplete')}
    $testControls=@($pack,$list,$upload,$addFiles,$addFolder,$localOnly)
    foreach($control in $testControls){if(-not $control){$errors.Add('Missing control')}}
    $form.CreateControl();$form.Dispose()
    if($errors.Count){throw ($errors -join '; ')}
    Write-Output 'Uploader UI self-test passed.'
    exit 0
}
[void]$form.ShowDialog()
$timer.Dispose();$form.Dispose()
