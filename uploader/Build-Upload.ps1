$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$output=Join-Path $root 'Wallpaper Upload.exe'
if(Test-Path -LiteralPath $output){
    $backup=Join-Path $root ('_old\Uploader_'+(Get-Date -Format 'yyyy-MM-dd_HHmmss_fff'))
    [void](New-Item -ItemType Directory -Path $backup)
    Copy-Item -LiteralPath $output -Destination $backup
    Remove-Item -LiteralPath $output
}
$bitmap=New-Object Drawing.Bitmap(64,64)
$graphics=[Drawing.Graphics]::FromImage($bitmap)
$graphics.Clear([Drawing.Color]::FromArgb(20,20,20))
$brush=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(230,230,230))
$graphics.FillRectangle($brush,13,13,14,38);$graphics.FillRectangle($brush,36,13,15,15);$graphics.FillRectangle($brush,36,36,15,15)
$icon=[Drawing.Icon]::FromHandle($bitmap.GetHicon())
$iconPath=Join-Path $PSScriptRoot 'wallpaper.ico'
$stream=[IO.File]::Create($iconPath);$icon.Save($stream);$stream.Dispose()
$options=New-Object System.CodeDom.Compiler.CompilerParameters
$options.CompilerOptions='/target:winexe /win32icon:"'+$iconPath+'"'
$options.ReferencedAssemblies.Add('System.dll')|Out-Null
$options.ReferencedAssemblies.Add('System.Windows.Forms.dll')|Out-Null
$options.GenerateExecutable=$true;$options.OutputAssembly=$output
$provider=New-Object Microsoft.CSharp.CSharpCodeProvider
try {
    $result=$provider.CompileAssemblyFromFile($options,[string[]]@((Join-Path $PSScriptRoot 'Launcher.cs')))
    if($result.Errors.HasErrors){throw (($result.Errors | ForEach-Object {$_.ErrorText}) -join [Environment]::NewLine)}
} finally {$provider.Dispose()}
$brush.Dispose();$graphics.Dispose();$bitmap.Dispose();$icon.Dispose()
Write-Output ('Built '+$output)
