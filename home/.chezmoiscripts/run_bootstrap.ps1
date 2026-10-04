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

# The embedded Git client works before the apply hook installs system Git.
$initArgs = @('init', '--apply', '--use-builtin-git=true')
if ($env:DOTFILES_DIR) {
    $initArgs += @('--source', $env:DOTFILES_DIR)
}
$initArgs += 'aria-amini'
& $chezmoi.Source @initArgs
if ($LASTEXITCODE -ne 0) {
    throw "Chezmoi init/apply failed with exit code $LASTEXITCODE."
}
Update-ProcessPath
