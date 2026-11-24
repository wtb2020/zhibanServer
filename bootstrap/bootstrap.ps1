param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet('server','client','demo')][string]$Mode = 'server',
    [ValidateSet('start','setup','reset')][string]$Action = 'start',
    [switch]$NoInstall,
    [switch]$CheckOnly,
    [switch]$NoBrowser,
    [switch]$WithBrowser,
    [int]$Port = 0,
    [string]$ServerUrl = '',
    [string]$PublicUrl = '',
    [string]$BindAddress = '',
    [string]$Username = '',
    [string]$Database = ''
)

$ErrorActionPreference = 'Stop'
$script:ZbDoctor = Join-Path $PSScriptRoot 'runtime_doctor.py'

function Test-ZbPython([string]$Executable, [string[]]$Prefix = @()) {
    if (!$Executable -or !(Test-Path -LiteralPath $Executable -PathType Leaf)) { return $null }
    # Avoid Windows Store aliases, which can open the store instead of running Python.
    $aliasDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
    if ([IO.Path]::GetDirectoryName($Executable).TrimEnd('\') -ieq $aliasDirectory.TrimEnd('\')) { return $null }
    try {
        $info = New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName = $Executable
        $info.Arguments = (($Prefix -join ' ') + ' "' + $script:ZbDoctor + '" --json').Trim()
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::Start($info)
        try {
            if (!$process.WaitForExit(15000)) { $process.Kill(); return $null }
            $output = $process.StandardOutput.ReadToEnd()
            if ($process.ExitCode -ne 0) { return $null }
            $report = $output | ConvertFrom-Json
            if (!$report.ok -or !(Test-Path -LiteralPath $report.executable -PathType Leaf)) { return $null }
            return $report
        } finally { $process.Dispose() }
    } catch { return $null }
}

function Find-ZbPython([string]$Root) {
    if ($env:EDU_PYTHON) {
        $report = Test-ZbPython $env:EDU_PYTHON
        if (!$report) { throw 'EDU_PYTHON is set but does not point to a working Python 3.10+ with SQLite/SSL.' }
        return $report
    }
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $projectPython = Join-Path $Root '.venv\Scripts\python.exe'
    if (Test-Path -LiteralPath (Join-Path $Root '.venv')) {
        $report = Test-ZbPython $projectPython
        if (!$report -or !$report.is_virtualenv) { throw 'The project .venv is incomplete or invalid. Rebuild it on this device; it will not be silently replaced by system Python.' }
        return $report
    }
    $cache = Join-Path $Root '.runtime\python-path.txt'
    if (Test-Path -LiteralPath $cache) { $candidates.Add((Get-Content -LiteralPath $cache -Raw).Trim()) }
    foreach ($name in @('python.exe','python3.exe')) {
        foreach ($command in @(Get-Command $name -All -ErrorAction SilentlyContinue)) { $candidates.Add($command.Source) }
    }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        $report = Test-ZbPython $candidate
        if ($report) { return $report }
    }
    $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($launcher) {
        $report = Test-ZbPython $launcher.Source @('-3')
        if ($report) { return $report }
    }
    foreach ($base in @((Join-Path $env:LOCALAPPDATA 'Programs\Python'), $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($base -and (Test-Path -LiteralPath $base)) {
            foreach ($directory in @(Get-ChildItem -LiteralPath $base -Directory -Filter 'Python*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
                $report = Test-ZbPython (Join-Path $directory.FullName 'python.exe')
                if ($report) { return $report }
            }
        }
    }
    return $null
}

function Install-ZbPackage([string]$PackageId) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (!$winget) { throw 'WinGet is unavailable. Install Microsoft App Installer or Python from https://www.python.org/downloads/windows/ and retry. No application data was changed.' }
    Write-Host "Installing missing dependency with WinGet: $PackageId (current user). Internet access is required."
    & $winget.Source install --id $PackageId --exact --source winget --scope user --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "WinGet installation failed ($LASTEXITCODE). Check the network/installer output, or install the dependency manually and retry." }
    # The current process must see paths written by the installer without reopening the terminal.
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') + ';' + $env:Path
}

function Test-ZbBrowser {
    $paths = @(
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )
    if (${env:ProgramFiles(x86)}) { $paths += Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe' }
    foreach ($path in $paths) { if (Test-Path -LiteralPath $path -PathType Leaf) { return $true } }
    foreach ($name in @('chrome.exe','msedge.exe','chromium.exe','firefox.exe')) { if (Get-Command $name -ErrorAction SilentlyContinue) { return $true } }
    return $false
}

function Invoke-ZbBootstrap {
    $root = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $report = Find-ZbPython $root
    if (!$report) {
        if ($NoInstall -or $CheckOnly) { throw 'A working Python 3.10+ with SQLite/SSL was not found. Run setup.bat to install automatically, or set EDU_PYTHON to a suitable python.exe.' }
        Install-ZbPackage 'Python.Python.3.14'
        $report = Find-ZbPython $root
        if (!$report) { throw 'Python was installed but did not pass validation. Check the installer output or set EDU_PYTHON to its full path.' }
    }
    Write-Host "Runtime OK: Python $($report.python), SQLite $($report.sqlite), $($report.ssl)"
    Write-Host "Python: $($report.executable)"
    Write-Host "Virtual environment: $($report.is_virtualenv)"
    $needsBrowser = ($Mode -in @('client','demo') -or $WithBrowser) -and !$NoBrowser -and $Action -ne 'reset'
    if ($needsBrowser -and !(Test-ZbBrowser)) {
        if ($NoInstall -or $CheckOnly) { throw 'A supported browser was not detected. Install Chrome/Edge, run setup.bat -WithBrowser, or use -NoBrowser for a headless device.' }
        Install-ZbPackage 'Google.Chrome'
        if (!(Test-ZbBrowser)) { throw 'Browser installation completed but Chrome/Edge was not detected. Check the installer output.' }
    }
    if (!$CheckOnly) {
        $runtime = Join-Path $root '.runtime'
        New-Item -ItemType Directory -Path $runtime -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $runtime 'python-path.txt'), $report.executable, (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText((Join-Path $runtime 'doctor.json'), ($report | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    }
    if ($Mode -eq 'client' -or $Mode -eq 'demo') { Write-Host 'Offline speech also needs a local English system voice; test it in the classroom. No pip packages are required.' }
    if ($Action -eq 'setup' -or $CheckOnly) { Write-Host 'Dependency check completed.'; return 0 }
    $arguments = @()
    if ($Action -eq 'reset') {
        if ($Mode -ne 'server') { throw 'Password reset is only available in the server project.' }
        $entry = Join-Path $root 'reset_admin.py'
        if ($Username) { $arguments += @('--username', $Username) }
        if ($Database) { $arguments += @('--database', $Database) }
    } elseif ($Mode -eq 'client') {
        $entry = Join-Path $root 'client.py'
        if ($ServerUrl) { $arguments += @('--server', $ServerUrl) }
    } elseif ($Mode -eq 'server') {
        $entry = Join-Path $root 'run.py'
        if ($PublicUrl) { $arguments += @('--public-url', $PublicUrl) }
        if ($BindAddress) { $arguments += @('--host', $BindAddress) }
    } else { $entry = Join-Path $root 'demo.py' }
    if ($Action -eq 'start') {
        if ($Port -gt 0) {
            if ($Mode -eq 'demo') { throw '-Port is not supported for demo mode. Start each project separately to customize ports.' }
            $arguments += @('--port', [string]$Port)
        }
        if (!$NoBrowser) { $arguments += '--open-browser' }
    }
    Push-Location -LiteralPath $root
    try {
        $OutputEncoding = [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        $env:PYTHONIOENCODING = 'utf-8'
        & $report.executable $entry @arguments | Out-Host
        return $LASTEXITCODE
    } finally { Pop-Location }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { exit (Invoke-ZbBootstrap) }
    catch { Write-Host "Startup failed: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
}
