param([switch]$Capture, [string]$GodotBin = $env:GODOT_BIN)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path $repo 'out/native-downloads-check'
$godot = if ($GodotBin) { $GodotBin } else { Join-Path $repo 'out/floating-keyboard-check/editor/Godot_v4.7.1-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $godot)) { throw 'Set up the pinned Godot 4.7.1 Windows editor first.' }
New-Item -ItemType Directory -Force -Path $work | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'shell') -Destination $work -Recurse -Force
$extension = Join-Path $work 'shell/bin/mowser.gdextension'
if (Test-Path -LiteralPath $extension) { Remove-Item -LiteralPath $extension }
$extensionList = Join-Path $work 'shell/.godot/extension_list.cfg'
if (Test-Path -LiteralPath $extensionList) { Set-Content -LiteralPath $extensionList -Value '' }
$env:XDG_DATA_HOME = Join-Path $work 'data'
$env:XDG_CONFIG_HOME = Join-Path $work 'config'
$env:XDG_CACHE_HOME = Join-Path $work 'cache'
$env:XDG_RUNTIME_DIR = Join-Path $work 'runtime'
$env:MARWANOS_SHELL_STATUS_DIR = Join-Path $work 'status'
$env:MARWANOS_WINDOWS_HOME = Join-Path $work 'windows'
$env:MARWANOS_METADATA_HOME = Join-Path $work 'metadata'
$env:MARWANOS_HISTORY_HOME = Join-Path $work 'history'
$env:MARWANOS_SHELL_WINDOWED = '1'
$project = Join-Path $work 'shell'
$test = Join-Path $repo 'tests/downloads_shell.gd'
& $godot --headless --path $project --editor --import --quit *> (Join-Path $work 'import.log')
$headlessLog = Join-Path $work 'shell.log'
& $godot --headless --path $project --script $test --audio-driver Dummy *> $headlessLog
Get-Content -LiteralPath $headlessLog
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $headlessLog -Pattern 'SCRIPT ERROR|Parse Error|FAIL:') -or -not (Select-String -LiteralPath $headlessLog -Pattern 'Downloads shell checks: 0 failure')) {
    throw 'Downloads controller checks failed.'
}
$designLog = Join-Path $work 'design.log'
& $godot --headless --path $project --script (Join-Path $repo 'tests/design_shell.gd') --audio-driver Dummy *> $designLog
Get-Content -LiteralPath $designLog | Select-Object -Last 4
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $designLog -Pattern 'SCRIPT ERROR|Parse Error|FAIL:') -or -not (Select-String -LiteralPath $designLog -Pattern 'Design shell checks: 0 failure')) { throw 'System navigation regression checks failed.' }
$directoryLog = Join-Path $work 'browser-directory.log'
& $godot --headless --path $project --script (Join-Path $repo 'tests/browser_download_directory.gd') --audio-driver Dummy *> $directoryLog
Get-Content -LiteralPath $directoryLog | Select-Object -Last 6
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $directoryLog -Pattern 'SCRIPT ERROR|Parse Error|FAIL:') -or -not (Select-String -LiteralPath $directoryLog -Pattern 'Browser download directory checks: 0 failure')) { throw 'Browser destination regression checks failed.' }
if ($Capture) {
    $env:MARWANOS_DOWNLOADS_CAPTURE = Join-Path $work 'downloads.png'
    $arguments = @('--path', ('"' + $project + '"'), '--script', ('"' + $test + '"'), '--audio-driver', 'Dummy', '--rendering-method', 'gl_compatibility')
    $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $work 'render.log') -RedirectStandardError (Join-Path $work 'render-errors.log')
    if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'Downloads render check timed out.' }
    Get-Content -LiteralPath (Join-Path $work 'render-errors.log')
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $env:MARWANOS_DOWNLOADS_CAPTURE)) { throw 'Downloads render check failed.' }
}
