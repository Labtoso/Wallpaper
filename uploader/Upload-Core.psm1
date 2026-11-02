Set-StrictMode -Version Latest

function Get-WallpaperTools {
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    $gh = Get-Command gh.exe -ErrorAction SilentlyContinue
    $gitPath = if ($git) { $git.Source } else { Join-Path $env:ProgramFiles 'Git\cmd\git.exe' }
    $ghPath = if ($gh) { $gh.Source } else { Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe' }
    if (-not (Test-Path -LiteralPath $gitPath)) { throw 'Git wurde nicht gefunden. Bitte Git for Windows installieren.' }
    if (-not (Test-Path -LiteralPath $ghPath)) { throw 'GitHub CLI wurde nicht gefunden. Bitte GitHub CLI installieren.' }
    return [pscustomobject]@{ Git = $gitPath; Gh = $ghPath }
}

function Invoke-WallpaperProcess {
    param([string]$Program, [string[]]$Parameters, [string]$WorkingDirectory, [AllowNull()][string]$InputText = $null)
    $quoted = foreach ($part in $Parameters) {
        '"' + ([regex]::Replace([regex]::Replace($part, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
    }
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $Program
    $start.Arguments = $quoted -join ' '
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardInput = $true
    $start.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $start.EnvironmentVariables['PATH'] = (Split-Path -Parent $Program) + ';' + (Join-Path $env:ProgramFiles 'GitHub CLI') + ';' + $env:PATH
    $start.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $start.EnvironmentVariables['GH_PROMPT_DISABLED'] = '1'
    $start.EnvironmentVariables['LC_ALL'] = 'C'
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if ($null -ne $InputText) {
            $inputBytes = [Text.Encoding]::UTF8.GetBytes($InputText)
            $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
            $process.StandardInput.BaseStream.Flush()
        }
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(900000)) { $process.Kill(); throw 'Zeitlimit erreicht. Die lokalen Dateien bleiben erhalten.' }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $outputTask.GetAwaiter().GetResult(); Error = $errorTask.GetAwaiter().GetResult() }
    } finally { $process.Dispose() }
}

function Invoke-WallpaperGit {
    param([string]$Root, [string[]]$Parameters, [AllowNull()][string]$InputText = $null, [switch]$AllowFailure)
    $tools = Get-WallpaperTools
    $result = Invoke-WallpaperProcess -Program $tools.Git -Parameters (@('-c', ('safe.directory=' + ($Root -replace '\\','/')), '-c', 'core.quotepath=false') + $Parameters) -WorkingDirectory $Root -InputText $InputText
    if ($result.ExitCode -ne 0 -and -not $AllowFailure) { throw ('Git: ' + $result.Error.Trim() + ' ' + $result.Output.Trim()).Trim() }
    return $result
}

function New-WallpaperUploadPlan {
    param([Parameter(Mandatory)][string]$ProjectRoot, [Parameter(Mandatory)][string]$PackName, [Parameter(Mandatory)][object[]]$Items)
    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    if (-not (Test-Path -LiteralPath (Join-Path $root 'index.html')) -or -not (Test-Path -LiteralPath (Join-Path $root 'assets') -PathType Container)) { throw 'Bitte den Wallpaper-Projektordner mit index.html und assets auswählen.' }
    $name = $PackName.Trim()
    if (-not $name -or $name.Length -gt 100 -or $name -match '[<>:"/\\|?*\x00-\x1f]' -or $name.StartsWith('.') -or $name.EndsWith('.') -or $name -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw 'Bitte einen gültigen Packnamen eingeben, ohne Schrägstriche oder Windows-Sonderzeichen.' }
    $packRoot = Join-Path (Join-Path $root 'assets') $name
    $planned = New-Object 'System.Collections.Generic.List[object]'
    $reserved = @{}
    foreach ($item in $Items) {
        $source = Get-Item -LiteralPath $item.SourcePath -ErrorAction Stop
        if ($source.PSIsContainer -or ($source.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('Keine normale Bilddatei: ' + $source.Name) }
        if ($source.Extension -notmatch '^\.(jpg|jpeg|png|webp|gif|avif|svg)$') { throw ('Nicht unterstütztes Bildformat: ' + $source.Name) }
        if ($source.Length -gt 100MB) { throw ($source.Name + ' ist größer als 100 MiB. GitHub nimmt diese Einzeldatei ohne Git LFS nicht an. Bitte vorher kleiner exportieren.') }
        $relative = [string]$item.RelativePath
        if (-not $relative) { $relative = $source.Name }
        $destination = [IO.Path]::GetFullPath((Join-Path $packRoot $relative))
        if (-not $destination.StartsWith($packRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Ein Zielpfad liegt außerhalb des gewählten Packs.' }
        $base = [IO.Path]::GetFileNameWithoutExtension($destination)
        $extension = [IO.Path]::GetExtension($destination)
        $parent = [IO.Path]::GetDirectoryName($destination)
        $suffix = 2
        $sourceHash = $null
        $skip = $false
        while ((Test-Path -LiteralPath $destination) -or $reserved.ContainsKey($destination)) {
            if (-not $sourceHash) { $sourceHash = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash }
            $otherHash = if ($reserved.ContainsKey($destination)) { $reserved[$destination] } elseif (Test-Path -LiteralPath $destination -PathType Leaf) { (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash } else { '' }
            if ($sourceHash -eq $otherHash) { $skip = $true; break }
            $destination = Join-Path $parent ($base + '-' + $suffix + $extension)
            $suffix++
        }
        if (-not $sourceHash) { $sourceHash = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash }
        $reserved[$destination] = $sourceHash
        $gitPath = $destination.Substring($root.Length + 1).Replace('\', '/')
        $planned.Add([pscustomobject]@{ Source = $source.FullName; Destination = $destination; GitPath = $gitPath; Skip = $skip; Bytes = $source.Length })
    }
    if (-not $planned.Count) { throw 'Bitte mindestens ein Bild auswählen.' }
    return [pscustomobject]@{ Root = $root; PackName = $name; Files = $planned.ToArray(); PackRoot = $packRoot }
}

function New-WallpaperSnapshot {
    param([string]$Root)
    $hash = (Invoke-WallpaperGit -Root $Root -Parameters @('rev-parse', '--short', 'HEAD')).Output.Trim()
    $snapshot = Join-Path $Root ('_old\upload_' + (Get-Date -Format 'yyyy-MM-dd_HHmmss_fff') + '_' + $hash)
    [void](New-Item -ItemType Directory -Path $snapshot -ErrorAction Stop)
    Get-ChildItem -LiteralPath $Root -Force | Where-Object { $_.Name -notin @('.git','_old') -and $_.Name -notmatch '^\.(test|build)-' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $snapshot -Recurse -ErrorAction Stop }
    return $snapshot
}

function Save-WallpaperPackCommit {
    param([string]$Root, [string[]]$Paths, [string]$PackName)
    $literalPaths = @($Paths | ForEach-Object { ':(literal)' + $_ })
    $pathspec = ($literalPaths -join [char]0) + [char]0
    [void](Invoke-WallpaperGit -Root $Root -Parameters @('add','--pathspec-from-file=-','--pathspec-file-nul') -InputText $pathspec)
    $staged = (Invoke-WallpaperGit -Root $Root -Parameters @('diff','--cached','--name-only','-z')).Output -split [char]0
    $selected = @($staged | Where-Object { $Paths -contains $_ })
    if ($selected.Count) {
        Write-Output 'Bilder werden als Labtoso gespeichert …'
        [void](Invoke-WallpaperGit -Root $Root -Parameters @('commit','--only','--pathspec-from-file=-','--pathspec-file-nul','-m',('Add wallpaper pack: ' + $PackName)) -InputText $pathspec)
        $attribution = (Invoke-WallpaperGit -Root $Root -Parameters @('log','-1','--format=%an <%ae>%n%cn <%ce>%n%B')).Output
        $identity = 'Labtoso <235880825+Labtoso@users.noreply.github.com>'
        $lines = $attribution -split '\r?\n'
        $body = (Invoke-WallpaperGit -Root $Root -Parameters @('log','-1','--format=%B')).Output.Trim()
        if ($lines[0] -cne $identity -or $lines[1] -cne $identity -or $body -cne ('Add wallpaper pack: ' + $PackName)) { throw 'Unerwartete Commit-Zuordnung. Upload wurde angehalten.' }
    }
}

function Invoke-WallpaperUpload {
    param([Parameter(Mandatory)][string]$ProjectRoot, [Parameter(Mandatory)][string]$PackName, [Parameter(Mandatory)][object[]]$Items, [switch]$Publish)
    $ErrorActionPreference = 'Stop'
    $plan = New-WallpaperUploadPlan -ProjectRoot $ProjectRoot -PackName $PackName -Items $Items
    $root = $plan.Root
    if ($Publish) {
        $tools = Get-WallpaperTools
        Write-Output 'GitHub-Verbindung wird geprüft …'
        $account = Invoke-WallpaperProcess -Program $tools.Gh -Parameters @('api','user','--jq','.login') -WorkingDirectory $root
        if ($account.ExitCode -ne 0 -or $account.Output.Trim() -ne 'Labtoso') { throw 'Bitte zuerst in GitHub CLI als Labtoso anmelden. Die lokale Auswahl bleibt erhalten.' }
        $remote = (Invoke-WallpaperGit -Root $root -Parameters @('remote','get-url','origin')).Output.Trim()
        if ($remote -notmatch '^(https://github\.com/|git@github\.com:)Labtoso/Wallpaper(?:\.git)?$') { throw 'Dieser Projektordner gehört nicht zu Labtoso/Wallpaper. Es wurde nichts hochgeladen.' }
        $branch = (Invoke-WallpaperGit -Root $root -Parameters @('branch','--show-current')).Output.Trim()
        if ($branch -ne 'main') { throw 'Bitte im Wallpaper-Projekt den Branch main verwenden.' }
        [void](Invoke-WallpaperGit -Root $root -Parameters @('config','user.name','Labtoso'))
        [void](Invoke-WallpaperGit -Root $root -Parameters @('config','user.email','235880825+Labtoso@users.noreply.github.com'))
        Write-Output 'Aktueller Repository-Stand wird geladen …'
        [void](Invoke-WallpaperGit -Root $root -Parameters @('fetch','origin','main'))
        $ahead = (Invoke-WallpaperGit -Root $root -Parameters @('rev-list','origin/main..HEAD')).Output.Trim()
        if ($ahead) {
            foreach ($commit in ($ahead -split '\r?\n')) {
                $message = (Invoke-WallpaperGit -Root $root -Parameters @('show','-s','--format=%s',$commit)).Output.Trim()
                $changed = (Invoke-WallpaperGit -Root $root -Parameters @('diff-tree','--no-commit-id','--name-only','-r',$commit)).Output.Trim() -split '\r?\n'
                if (-not $message.StartsWith('Add wallpaper pack: ') -or @($changed | Where-Object { $_ -and -not $_.StartsWith('assets/') }).Count) { throw 'Es gibt noch andere lokale, nicht hochgeladene Commits. Bitte diese zuerst veröffentlichen. Es wird nichts überschrieben.' }
            }
        }
        Write-Output 'Sicherung des bisherigen Projekts wird erstellt …'
        [void](New-WallpaperSnapshot -Root $root)
        [void](Invoke-WallpaperGit -Root $root -Parameters @('merge','--ff-only','origin/main'))
        # Re-check destinations after a possible fast-forward brought in new files.
        $plan = New-WallpaperUploadPlan -ProjectRoot $root -PackName $PackName -Items $Items
    }
    $copied = 0
    foreach ($file in $plan.Files) {
        if (-not $file.Skip) {
            [void](New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($file.Destination)) -Force)
            Copy-Item -LiteralPath $file.Source -Destination $file.Destination -ErrorAction Stop
            $copied++
        }
    }
    Write-Output ($copied.ToString() + ' Bilder hinzugefügt. Bestehende Dateien wurden erhalten.')
    if (-not $Publish) { return [pscustomobject]@{ Success = $true; Published = $false; Count = $copied; Pack = $plan.PackName } }
    $paths = @($plan.Files | ForEach-Object { $_.GitPath } | Select-Object -Unique)
    Save-WallpaperPackCommit -Root $root -Paths $paths -PackName $plan.PackName
    Write-Output 'Bilder werden zu GitHub hochgeladen …'
    [void](Invoke-WallpaperGit -Root $root -Parameters @('push','origin','main'))
    Write-Output 'Upload abgeschlossen. GitHub Pages baut die Kategorie und ZIP-Packs automatisch.'
    return [pscustomobject]@{ Success = $true; Published = $true; Count = $copied; Pack = $plan.PackName }
}

Export-ModuleMember -Function Get-WallpaperTools, New-WallpaperUploadPlan, Invoke-WallpaperUpload, Invoke-WallpaperProcess, Invoke-WallpaperGit, Save-WallpaperPackCommit
