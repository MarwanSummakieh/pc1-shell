param([switch]$Capture, [string]$GodotBin = $env:GODOT_BIN)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path $repo ('out/profiles-check/run-' + [guid]::NewGuid().ToString('N'))
$godot = if ($GodotBin) { $GodotBin } else { Join-Path $repo 'out/floating-keyboard-check/editor/Godot_v4.7.1-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $godot)) { throw 'Set GODOT_BIN to the pinned Godot 4.7.1 editor.' }
New-Item -ItemType Directory -Force -Path $work | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'shell') -Destination $work -Recurse -Force
$project = Join-Path $work 'shell'
$extension = Join-Path $project 'bin/mowser.gdextension'
if (Test-Path -LiteralPath $extension) { Remove-Item -LiteralPath $extension }
$extensionList = Join-Path $project '.godot/extension_list.cfg'
if (Test-Path -LiteralPath $extensionList) { Set-Content -LiteralPath $extensionList -Value '' }
$env:XDG_DATA_HOME = Join-Path $work 'data'
$env:XDG_CONFIG_HOME = Join-Path $work 'config'
$env:XDG_CACHE_HOME = Join-Path $work 'cache'
$env:MARWANOS_SHELL_WINDOWED = '1'
$env:MARWANOS_SHELL_STATUS_DIR = Join-Path $work 'status'
$env:MARWANOS_WINDOWS_HOME = Join-Path $work 'windows'
$env:MARWANOS_METADATA_HOME = Join-Path $work 'metadata'
$env:MARWANOS_PROFILES_HOME = Join-Path $work 'profiles'
$env:MARWANOS_HISTORY_HOME = Join-Path $work 'history'
$env:MARWANOS_ACHIEVEMENTS_HOME = Join-Path $work 'achievements'
$env:TEMP = Join-Path $work 'temp'
New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
& $godot --headless --path $project --editor --import --quit *> (Join-Path $work 'import.log')
foreach ($suite in @('profiles_shell', 'design_shell', 'play_history_shell', 'achievements_shell', 'console_refinement_shell', 'browser_shell')) {
    $log = Join-Path $work ($suite + '.log')
    & $godot --headless --path $project --script (Join-Path $repo ('tests/' + $suite + '.gd')) --audio-driver Dummy *> $log
    Get-Content -LiteralPath $log | Select-Object -Last 3
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|FAIL:')) { throw ($suite + ' failed. See ' + $log) }
}
if (Select-String -LiteralPath (Join-Path $work 'import.log') -Pattern 'SCRIPT ERROR|Parse Error|Failed to load script') { throw 'Project import failed.' }
if ($Capture) {
    $env:MARWANOS_PROFILES_CAPTURE = Join-Path $work 'users.png'
    $env:MARWANOS_PROFILES_HOME = Join-Path $work 'capture-profiles'
    $env:MARWANOS_HISTORY_HOME = Join-Path $work 'capture-history'
    $arguments = @('--path', ('"' + $project + '"'), '--script', ('"' + (Join-Path $repo 'tests/profiles_shell.gd') + '"'), '--audio-driver', 'Dummy', '--rendering-method', 'gl_compatibility')
    $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $work 'render.log') -RedirectStandardError (Join-Path $work 'render-errors.log')
    if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'Profile render check timed out.' }
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $env:MARWANOS_PROFILES_CAPTURE)) { throw 'Profile render check failed.' }
    Write-Output ('Profile screenshot: ' + $env:MARWANOS_PROFILES_CAPTURE)
}
Write-Output ('Profile checks saved in ' + $work)
