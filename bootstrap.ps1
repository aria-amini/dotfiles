$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'This installer supports Windows only.'
}

function Update-ProcessPath {
    $env:PATH = ((@(
        $env:PATH
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
        [Environment]::GetEnvironmentVariable('Path', 'User')
    ) -join ';') -split ';' | ForEach-Object {
        [Environment]::ExpandEnvironmentVariables($_.Trim().Trim('"'))
    } | Where-Object { $_ } | Select-Object -Unique) -join ';'
}

Update-ProcessPath
$packages = [ordered]@{ 'git.exe' = 'Git.Git'; 'mise.exe' = 'jdx.mise' }
foreach ($package in $packages.GetEnumerator()) {
    if (-not (Get-Command $package.Key -ErrorAction SilentlyContinue)) {
        winget.exe install --id $package.Value -e --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            throw "$($package.Value) installation failed with exit code $LASTEXITCODE."
        }
        Update-ProcessPath
    }
    Get-Command $package.Key -ErrorAction Stop | Out-Null
}

mise.exe -C $HOME use --global opencode@latest chezmoi@latest
if ($LASTEXITCODE -ne 0) {
    throw "Mise tool installation failed with exit code $LASTEXITCODE."
}

$data = if ($env:MISE_DATA_DIR) { $env:MISE_DATA_DIR } else { Join-Path $env:LOCALAPPDATA 'mise' }
$shims = Join-Path $data 'shims'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $shims) {
    [Environment]::SetEnvironmentVariable('Path', (@($shims, $userPath) -join ';').TrimEnd(';'), 'User')
}
Update-ProcessPath

mise.exe -C $HOME exec -- chezmoi.exe init --apply aria-amini
if ($LASTEXITCODE -ne 0) {
    throw "Chezmoi init/apply failed with exit code $LASTEXITCODE."
}
