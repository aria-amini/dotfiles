$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'This installer supports Windows only.'
}

function Update-ProcessPath {
    # cmd.exe can discard PATH when repeated refreshes exceed its 8191-character limit.
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $paths = @(
        $env:PATH
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
        [Environment]::GetEnvironmentVariable('Path', 'User')
    ) -join ';'
    $env:PATH = (@($paths -split ';' | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_)) {
            $entry = [Environment]::ExpandEnvironmentVariables($_.Trim().Trim('"'))
            if ($seen.Add($entry)) { $entry }
        }
    })) -join ';'
}

Update-ProcessPath
$chezmoi = Get-Command chezmoi.exe -ErrorAction SilentlyContinue
if (-not $chezmoi) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'WinGet is required. Install App Installer from the Microsoft Store.'
    }
    winget.exe install --id twpayne.chezmoi -e --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "Chezmoi installation failed with exit code $LASTEXITCODE."
    }
    Update-ProcessPath
    $chezmoi = Get-Command chezmoi.exe -ErrorAction SilentlyContinue
    if (-not $chezmoi) {
        throw 'Chezmoi is not on PATH after installation. Open a new PowerShell window and run the installer again.'
    }
}

$source = if ($env:DOTFILES_DIR) {
    [IO.Path]::GetFullPath($env:DOTFILES_DIR)
} else {
    Join-Path $env:USERPROFILE '.local/share/chezmoi'
}
if (-not (Test-Path $source -PathType Container)) {
    if (Test-Path $source) { throw "Source path is not a directory: $source" }
    # The embedded Git client works before setup installs system Git.
    & $chezmoi.Source --source $source init --use-builtin-git=true aria-amini
    if ($LASTEXITCODE -ne 0) {
        throw "Chezmoi init failed with exit code $LASTEXITCODE."
    }
}
$setup = Join-Path $source 'setup/windows.ps1'
if (-not (Test-Path $setup -PathType Leaf)) { throw "Setup script does not exist: $setup" }
& $setup -Source $source
