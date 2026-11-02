$ErrorActionPreference='Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'uploader\Upload-Core.psm1') -Force
$project=Split-Path -Parent $PSScriptRoot
$testRoot=Join-Path $project ('.test-upload-'+[guid]::NewGuid().ToString('N'))
$repo=Join-Path $testRoot 'Repo mit Leerzeichen Ä'
$source=Join-Path $testRoot 'Quellen'
$passed=0
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('FAIL: '+$Message)};$script:passed++;Write-Output ('PASS: '+$Message)}
function Must-Fail([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed $Message}
try{
    [void](New-Item -ItemType Directory -Path (Join-Path $repo 'assets') -Force)
    [void](New-Item -ItemType Directory -Path $source)
    [IO.File]::WriteAllText((Join-Path $repo 'index.html'),'<!doctype html>')
    $one=Join-Path $source 'Grün [1].png'
    $two=Join-Path $source 'Andere.png'
    $bytes=[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0P8AAAAASUVORK5CYII=')
    [IO.File]::WriteAllBytes($one,$bytes)
    [IO.File]::WriteAllBytes($two,[byte[]](1,2,3,4))
    $items=@([pscustomobject]@{SourcePath=$one;RelativePath='Unterordner\Grün [1].png'})
    $plan=New-WallpaperUploadPlan -ProjectRoot $repo -PackName 'Test Ä & Raum' -Items $items
    Assert ($plan.Files.Count -eq 1) 'Valid image and Unicode pack accepted'
    Assert ($plan.Files[0].GitPath -eq 'assets/Test Ä & Raum/Unterordner/Grün [1].png') 'Nested target path preserved'
    Must-Fail {New-WallpaperUploadPlan -ProjectRoot $repo -PackName '..' -Items $items} 'Invalid category rejected'
    Must-Fail {New-WallpaperUploadPlan -ProjectRoot $repo -PackName 'CON' -Items $items} 'Windows reserved category rejected'
    Must-Fail {New-WallpaperUploadPlan -ProjectRoot $repo -PackName 'Test' -Items @([pscustomobject]@{SourcePath=$one;RelativePath='..\outside.png'})} 'Path traversal rejected'
    $local=@(Invoke-WallpaperUpload -ProjectRoot $repo -PackName 'Test Ä & Raum' -Items $items)
    Assert ($local[-1].Success -and -not $local[-1].Published) 'Local-only import succeeds without network'
    Assert ((Get-FileHash -LiteralPath $one).Hash -eq (Get-FileHash -LiteralPath $plan.Files[0].Destination).Hash) 'Original bytes are unchanged'
    $again=New-WallpaperUploadPlan -ProjectRoot $repo -PackName 'Test Ä & Raum' -Items $items
    Assert $again.Files[0].Skip 'Identical duplicate detected'
    $different=New-WallpaperUploadPlan -ProjectRoot $repo -PackName 'Test Ä & Raum' -Items @([pscustomobject]@{SourcePath=$two;RelativePath='Unterordner\Grün [1].png'})
    Assert ($different.Files[0].Destination.EndsWith('Grün [1]-2.png')) 'Different file gets a suffix instead of overwriting'
    $large=Join-Path $source 'Zu gross.png'
    $stream=[IO.File]::Create($large);$stream.SetLength(100MB+1);$stream.Dispose()
    Must-Fail {New-WallpaperUploadPlan -ProjectRoot $repo -PackName 'Test' -Items @([pscustomobject]@{SourcePath=$large;RelativePath='Gross.png'})} 'Files exceeding 100 MiB rejected before copying'
    $medium=Join-Path $source 'Ueber Weblimit.png'
    $stream=[IO.File]::Create($medium);$stream.Write($bytes,0,$bytes.Length);$stream.SetLength(26MB);$stream.Dispose()
    $mediumPlan=New-WallpaperUploadPlan -ProjectRoot $repo -PackName 'Test' -Items @([pscustomobject]@{SourcePath=$medium;RelativePath='Gross.png'})
    Assert ($mediumPlan.Files[0].Bytes -eq 26MB) 'Images above the 25 MiB web limit are accepted for Git upload'
    $config=@{Module=(Join-Path $project 'uploader\Upload-Core.psm1');Root=$repo;Pack='Job-Test';Items=$items}
    $job=Start-Job -ArgumentList $config -ScriptBlock {param($config)Import-Module $config.Module -Force;Invoke-WallpaperUpload -ProjectRoot $config.Root -PackName $config.Pack -Items $config.Items}
    try {
        [void](Wait-Job -Job $job -Timeout 30)
        $jobResults=@(Receive-Job -Job $job -ErrorAction Stop)
        Assert ($job.State -eq 'Completed' -and $jobResults[-1].Success) 'Background upload worker imports images after argument serialization'
    } finally {if($job.State -eq 'Running'){Stop-Job $job};Remove-Job $job}
    [void](Invoke-WallpaperGit -Root $repo -Parameters @('init','-b','main'))
    [void](Invoke-WallpaperGit -Root $repo -Parameters @('config','user.name','Labtoso'))
    [void](Invoke-WallpaperGit -Root $repo -Parameters @('config','user.email','235880825+Labtoso@users.noreply.github.com'))
    [void](Invoke-WallpaperGit -Root $repo -Parameters @('add','index.html'))
    [void](Invoke-WallpaperGit -Root $repo -Parameters @('commit','-m','Initialize test fixture'))
    [IO.File]::WriteAllText((Join-Path $repo 'unrelated.txt'),'Leave staged')
    [void](Invoke-WallpaperGit -Root $repo -Parameters @('add','unrelated.txt'))
    Save-WallpaperPackCommit -Root $repo -Paths @($plan.Files[0].GitPath) -PackName 'Test Ä & Raum' | Out-Null
    $changed=(Invoke-WallpaperGit -Root $repo -Parameters @('diff-tree','--no-commit-id','--name-only','-r','HEAD')).Output.Trim()
    Assert ($changed -eq $plan.Files[0].GitPath) 'Commit includes only selected asset paths, including brackets and umlauts'
    $staged=(Invoke-WallpaperGit -Root $repo -Parameters @('diff','--cached','--name-only')).Output.Trim()
    Assert ($staged -eq 'unrelated.txt') 'Unrelated staged change remains untouched'
    $identity=(Invoke-WallpaperGit -Root $repo -Parameters @('log','-1','--format=%an <%ae>')).Output.Trim()
    Assert ($identity -eq 'Labtoso <235880825+Labtoso@users.noreply.github.com>') 'Commit identity is exactly Labtoso'
    Write-Output ($passed.ToString()+' uploader checks passed.')
}finally{
    $full=[IO.Path]::GetFullPath($testRoot)
    if([IO.Path]::GetDirectoryName($full) -ne $project -or -not [IO.Path]::GetFileName($full).StartsWith('.test-upload-')){throw 'Unexpected cleanup path'}
    if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
