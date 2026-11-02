param([switch]$SelfTest, [string]$PreviewPath, [switch]$PreviewSelection)
$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Bitte über Wallpaper Upload.bat starten.'}
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
Import-Module (Join-Path $PSScriptRoot 'Upload-Core.psm1') -Force
[Windows.Forms.Application]::EnableVisualStyles()
$script:projectRoot=Split-Path -Parent $PSScriptRoot
$script:selection=New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
$script:job=$null
$script:busy=$false
$window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Upload-Window.xaml')))
$ui=@{}
foreach($name in @('PackName','TargetPath','ExistingPacks','NoPacks','ProjectPath','BrowseProject','OpenWebsite','Login','SelectionCount','AddFiles','AddFolder','ClearSelection','DropArea','EmptySelection','FileList','SizeHint','ToggleDetails','Log','Status','LocalOnly','Upload','Progress')){
    $ui[$name]=$window.FindName($name)
    if(-not $ui[$name]){throw ('Fensterelement fehlt: '+$name)}
}
$ui.FileList.ItemsSource=$script:selection
$iconPath=Join-Path $PSScriptRoot 'wallpaper.ico'
if(Test-Path -LiteralPath $iconPath){
    $iconStream=[IO.File]::Open($iconPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try{
        $iconImage=New-Object Windows.Media.Imaging.BitmapImage
        $iconImage.BeginInit();$iconImage.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $iconImage.StreamSource=$iconStream;$iconImage.EndInit();$iconImage.Freeze();$window.Icon=$iconImage
    }finally{$iconStream.Dispose()}
}
if(-not ('WallpaperWindowAppearance' -as [type])){
    Add-Type -ReferencedAssemblies @('System.dll',[Windows.Media.ImageSource].Assembly.Location,[Windows.DependencyObject].Assembly.Location) -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WallpaperWindowAppearance {
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
public sealed class WallpaperUploadItem {
    public string SourcePath { get; set; }
    public string RelativePath { get; set; }
    public string Name { get; set; }
    public long Bytes { get; set; }
    public string DisplaySize { get; set; }
    public string FileType { get; set; }
    public System.Windows.Media.ImageSource Thumbnail { get; set; }
}
'@
}
$window.add_SourceInitialized({
    try{
        $handle=(New-Object Windows.Interop.WindowInteropHelper($window)).Handle
        $dark=1
        $result=[WallpaperWindowAppearance]::DwmSetWindowAttribute($handle,20,[ref]$dark,4)
        if($result -ne 0){[void][WallpaperWindowAppearance]::DwmSetWindowAttribute($handle,19,[ref]$dark,4)}
    }catch{}
})
function Set-Status([string]$Text,[switch]$Failed){
    $ui.Status.Text=$Text
    $color=if($Failed){'#D69A93'}else{'#BCC2CC'}
    $ui.Status.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString($color)
}
function Write-Log([string]$Text){$ui.Log.AppendText($Text+[Environment]::NewLine);$ui.Log.ScrollToEnd();Set-Status $Text}
function Update-Actions{
    $ui.Upload.IsEnabled=-not $script:busy -and $script:selection.Count -gt 0 -and $ui.PackName.Text.Trim().Length -gt 0
    $ui.ClearSelection.IsEnabled=-not $script:busy -and $script:selection.Count -gt 0
    $ui.Upload.Content=if($script:busy){'Bitte warten …'}elseif($ui.LocalOnly.IsChecked){'Hinzufügen'}else{'Hochladen'}
    $ui.TargetPath.Text='assets / '+$(if($ui.PackName.Text.Trim()){$ui.PackName.Text.Trim()}else{'…'})
}
function Update-Packs{
    $ui.ProjectPath.Text=$script:projectRoot;$ui.ExistingPacks.Items.Clear()
    $assets=Join-Path $script:projectRoot 'assets'
    if(Test-Path -LiteralPath $assets){Get-ChildItem -LiteralPath $assets -Directory | Where-Object {-not $_.Name.StartsWith('.')} | Sort-Object Name | ForEach-Object {[void]$ui.ExistingPacks.Items.Add($_.Name)}}
    $ui.NoPacks.Visibility=if($ui.ExistingPacks.Items.Count){'Collapsed'}else{'Visible'}
}
function Refresh-Selection{
    $total=0;foreach($item in $script:selection){$total+=$item.Bytes}
    $ui.SelectionCount.Text=$script:selection.Count.ToString()+$(if($script:selection.Count -eq 1){' Bild'}else{' Bilder'})
    $ui.SizeHint.Text=if($script:selection.Count){'{0:N1} MB insgesamt · Originale bleiben unverändert' -f ($total/1MB)}else{'Originale bleiben unverändert · bis 100 MiB pro Bild'}
    $ui.EmptySelection.Visibility=if($script:selection.Count){'Collapsed'}else{'Visible'}
    $ui.FileList.Visibility=if($script:selection.Count){'Visible'}else{'Collapsed'}
    if(-not $script:busy){Set-Status $(if(-not $script:selection.Count){'Bereit'}elseif(-not $ui.PackName.Text.Trim()){'Packnamen eingeben'}else{'Bereit zum Hochladen'})}
    Update-Actions
}
function Get-Thumbnail([string]$Path){
    $stream=$null
    try{
        $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        $image=New-Object Windows.Media.Imaging.BitmapImage
        $image.BeginInit();$image.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $image.DecodePixelWidth=180;$image.StreamSource=$stream;$image.EndInit();$image.Freeze()
        return $image
    }catch{return $null}finally{if($stream){$stream.Dispose()}}
}
function Add-Image([string]$Path,[string]$Relative){
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($file.Extension -notmatch '^\.(jpg|jpeg|png|webp|gif|avif|svg)$' -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){return}
    if(@($script:selection | Where-Object {$_.SourcePath -eq $file.FullName}).Count){return}
    $entry=New-Object WallpaperUploadItem
    $entry.SourcePath=$file.FullName;$entry.RelativePath=$Relative;$entry.Name=$file.Name;$entry.Bytes=$file.Length
    $entry.DisplaySize='{0:N1} MB' -f ($file.Length/1MB);$entry.FileType=$file.Extension.TrimStart('.').ToUpperInvariant()
    $entry.Thumbnail=Get-Thumbnail $file.FullName
    $script:selection.Add($entry)
}
function Add-Directory([string]$Directory,[string]$Base){
    foreach($entry in Get-ChildItem -LiteralPath $Directory){
        if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
        if($entry.PSIsContainer){Add-Directory $entry.FullName $Base}else{Add-Image $entry.FullName $entry.FullName.Substring($Base.TrimEnd('\').Length+1)}
    }
}
function Set-Busy([bool]$Value){
    $script:busy=$Value
    foreach($name in @('PackName','ExistingPacks','BrowseProject','AddFiles','AddFolder','LocalOnly','FileList','Login')){$ui[$name].IsEnabled=-not $Value}
    $ui.Progress.Visibility=if($Value){'Visible'}else{'Collapsed'}
    Update-Actions
}
function Show-Failure([string]$Text){Write-Log ('Fehler: '+$Text);Set-Status $Text -Failed;$ui.Log.Visibility='Visible';$ui.ToggleDetails.Content='Details schließen'}
$ui.PackName.add_TextChanged({Update-Actions})
$ui.ExistingPacks.add_SelectionChanged({if($ui.ExistingPacks.SelectedItem){$ui.PackName.Text=[string]$ui.ExistingPacks.SelectedItem}})
$ui.BrowseProject.add_Click({
    $dialog=New-Object Windows.Forms.FolderBrowserDialog;$dialog.Description='Wallpaper-Projektordner mit assets auswählen';$dialog.SelectedPath=$script:projectRoot
    try{if($dialog.ShowDialog() -eq 'OK'){$script:projectRoot=$dialog.SelectedPath;Update-Packs}}finally{$dialog.Dispose()}
})
$ui.AddFiles.add_Click({
    $dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Multiselect=$true;$dialog.Title='Wallpaper auswählen';$dialog.Filter='Bilder|*.jpg;*.jpeg;*.png;*.webp;*.gif;*.avif;*.svg'
    try{if($dialog.ShowDialog() -eq 'OK'){foreach($file in $dialog.FileNames){Add-Image $file ([IO.Path]::GetFileName($file))};Refresh-Selection}}catch{Show-Failure $_.Exception.Message}finally{$dialog.Dispose()}
})
$ui.AddFolder.add_Click({
    $dialog=New-Object Windows.Forms.FolderBrowserDialog;$dialog.Description='Bilderordner auswählen';$dialog.ShowNewFolderButton=$false
    try{if($dialog.ShowDialog() -eq 'OK'){if(-not $ui.PackName.Text.Trim()){$ui.PackName.Text=Split-Path -Leaf $dialog.SelectedPath};Add-Directory $dialog.SelectedPath $dialog.SelectedPath;Refresh-Selection}}catch{Show-Failure $_.Exception.Message}finally{$dialog.Dispose()}
})
$ui.ClearSelection.add_Click({$script:selection.Clear();Refresh-Selection})
$ui.FileList.AddHandler([Windows.Controls.Button]::ClickEvent,[Windows.RoutedEventHandler]{
    param($sender,$eventArgs)
    if($eventArgs.OriginalSource -is [Windows.Controls.Button] -and $eventArgs.OriginalSource.Tag){
        $path=[string]$eventArgs.OriginalSource.Tag;$entry=$script:selection | Where-Object {$_.SourcePath -eq $path} | Select-Object -First 1
        if($entry){[void]$script:selection.Remove($entry);Refresh-Selection};$eventArgs.Handled=$true
    }
})
$ui.DropArea.add_PreviewDragOver({param($sender,$eventArgs)
    $eventArgs.Effects=if(-not $script:busy -and $eventArgs.Data.GetDataPresent([Windows.DataFormats]::FileDrop)){[Windows.DragDropEffects]::Copy}else{[Windows.DragDropEffects]::None};$eventArgs.Handled=$true
})
$ui.DropArea.add_Drop({param($sender,$eventArgs)
    if($script:busy -or -not $eventArgs.Data.GetDataPresent([Windows.DataFormats]::FileDrop)){return}
    try{foreach($path in $eventArgs.Data.GetData([Windows.DataFormats]::FileDrop)){
        if(Test-Path -LiteralPath $path -PathType Container){if(-not $ui.PackName.Text.Trim()){$ui.PackName.Text=Split-Path -Leaf $path};Add-Directory $path $path}else{Add-Image $path ([IO.Path]::GetFileName($path))}
    };Refresh-Selection}catch{Show-Failure $_.Exception.Message};$eventArgs.Handled=$true
})
$ui.LocalOnly.add_Checked({Update-Actions});$ui.LocalOnly.add_Unchecked({Update-Actions})
$ui.OpenWebsite.add_Click({Start-Process 'https://wallpaper.labtoso.de/'})
$ui.Login.add_Click({try{$tools=Get-WallpaperTools;Start-Process -FilePath $tools.Gh -ArgumentList @('auth','login','--hostname','github.com','--git-protocol','https','--web') -WindowStyle Normal}catch{Show-Failure $_.Exception.Message}})
$ui.ToggleDetails.add_Click({$show=$ui.Log.Visibility -ne 'Visible';$ui.Log.Visibility=if($show){'Visible'}else{'Collapsed'};$ui.ToggleDetails.Content=if($show){'Details schließen'}else{'Details'}})
$timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromMilliseconds(250)
$timer.add_Tick({
    if(-not $script:job){return}
    foreach($item in Receive-Job -Job $script:job -ErrorAction SilentlyContinue){if($item -is [string]){Write-Log $item}elseif($item.PSObject.Properties['Success']){Write-Log $(if($item.Published){'Hochgeladen. Die Website wird aktualisiert.'}else{'Bilder lokal hinzugefügt.'})}}
    if($script:job.State -in @('Completed','Failed','Stopped')){
        foreach($errorRecord in $script:job.ChildJobs[0].Error){Show-Failure $errorRecord.ToString()}
        if($script:job.State -eq 'Failed' -and $script:job.ChildJobs[0].JobStateInfo.Reason){Show-Failure $script:job.ChildJobs[0].JobStateInfo.Reason.Message}
        Remove-Job -Job $script:job;$script:job=$null;$timer.Stop();Set-Busy $false;Update-Packs
    }
})
$ui.Upload.add_Click({
    try{
        if(-not $script:selection.Count){throw 'Bitte zuerst Bilder oder einen Ordner auswählen.'}
        if(-not $ui.PackName.Text.Trim()){throw 'Bitte einen Packnamen eingeben oder auswählen.'}
        $items=@($script:selection | ForEach-Object {[pscustomobject]@{SourcePath=$_.SourcePath;RelativePath=$_.RelativePath}})
        [void](New-WallpaperUploadPlan -ProjectRoot $script:projectRoot -PackName $ui.PackName.Text -Items $items)
        $config=@{Module=(Join-Path $PSScriptRoot 'Upload-Core.psm1');Root=$script:projectRoot;Pack=$ui.PackName.Text;Items=$items;Publish=(-not $ui.LocalOnly.IsChecked)}
        $ui.Log.Clear();Set-Busy $true;Write-Log 'Bilder werden vorbereitet …'
        $script:job=Start-Job -ArgumentList $config -ScriptBlock {param($config)Import-Module $config.Module -Force;Invoke-WallpaperUpload -ProjectRoot $config.Root -PackName $config.Pack -Items $config.Items -Publish:$config.Publish};$timer.Start()
    }catch{Set-Busy $false;Show-Failure $_.Exception.Message}
})
$window.add_Closing({param($sender,$eventArgs)if($script:busy){$eventArgs.Cancel=$true;Set-Status 'Upload läuft noch. Bitte bis zum Abschluss warten.'}})
Update-Packs;Refresh-Selection
if($PreviewSelection){
    $ui.PackName.Text='Meine Wallpaper'
    Get-ChildItem -LiteralPath (Join-Path $script:projectRoot 'assets') -Filter '*-full.jpg' -File | Select-Object -First 4 | ForEach-Object {Add-Image $_.FullName $_.Name}
    Refresh-Selection
}
if($SelfTest -or $PreviewPath){
    if($ui.Upload.IsEnabled -and -not $PreviewSelection){throw 'Upload must stay disabled for an empty selection.'}
    if($ui.Log.Visibility -ne 'Collapsed'){throw 'Details must be collapsed initially.'}
    if($ui.EmptySelection.Visibility -ne 'Visible' -and -not $PreviewSelection){throw 'Missing empty selection state.'}
    $root=$window.Content;$width=1060;$height=720
    $root.Measure([Windows.Size]::new($width,$height));$root.Arrange([Windows.Rect]::new(0,0,$width,$height));$root.UpdateLayout()
    [void]$root.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
    if($PreviewSelection){
        function Inspect-Images($node){
            if($node -is [Windows.Controls.Image]){
                $binding=[Windows.Data.BindingOperations]::GetBindingExpression($node,[Windows.Controls.Image]::SourceProperty)
                if(-not $node.Source -or $binding.Status -ne 'Active'){throw 'Image thumbnail binding failed.'}
            }
            for($index=0;$index -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($node);$index++){Inspect-Images ([Windows.Media.VisualTreeHelper]::GetChild($node,$index))}
        }
        Inspect-Images $root
    }
    if($root.ActualWidth -ne $width -or $ui.DropArea.ActualHeight -lt 150){throw 'Window layout is clipped.'}
    if($PreviewPath){
        $fullPath=[IO.Path]::GetFullPath($PreviewPath);[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($fullPath))
        $render=New-Object Windows.Media.Imaging.RenderTargetBitmap($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32);$render.Render($root)
        $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($render))
        $stream=[IO.File]::Create($fullPath);try{$encoder.Save($stream)}finally{$stream.Dispose()}
        Write-Output ('Rendered preview: '+$fullPath)
    }
    # Check the compact window with the details panel expanded as well.
    $ui.Log.Visibility='Visible'
    $root.Measure([Windows.Size]::new(880,640));$root.Arrange([Windows.Rect]::new(0,0,880,640));$root.UpdateLayout()
    $buttonPosition=$ui.Upload.TranslatePoint([Windows.Point]::new(0,0),$root)
    if($buttonPosition.Y+$ui.Upload.ActualHeight -gt 640 -or $ui.DropArea.ActualHeight -lt 150){throw 'Compact layout clips the upload controls.'}
    $window.Close();Write-Output 'Uploader dark UI self-test passed.';exit 0
}
[void]$window.ShowDialog()
$timer.Stop()
