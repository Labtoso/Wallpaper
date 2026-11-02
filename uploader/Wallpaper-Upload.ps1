param([switch]$SelfTest, [string]$PreviewPath, [switch]$PreviewSelection)
& (Join-Path $PSScriptRoot 'Upload-App.ps1') @PSBoundParameters
