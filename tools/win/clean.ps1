param(
    [switch]$Data,
    [switch]$Images,
    [switch]$Full,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot     = Resolve-Path (Join-Path (Join-Path $PSScriptRoot "..") "..")
$ArtifactsDir = Join-Path $RepoRoot "artifacts"
$AirTmpDir    = Join-Path (Join-Path (Join-Path $RepoRoot "src") "luma") "tmp"
$FlutterBuild = Join-Path (Join-Path (Join-Path $RepoRoot "src") "luma-web") "build"

$removeData   = $Data -or $Full
$removeImages = $Images -or $Full

function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "   $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "   $msg  (not found -- skipped)" -ForegroundColor DarkGray }
function Write-Warn($msg) { Write-Host "   $msg" -ForegroundColor Yellow }

function Remove-IfExists($path, $label) {
    if (Test-Path $path) {
        if ($WhatIf) {
            Write-Host "   [WhatIf] Delete $label  ($path)" -ForegroundColor Yellow
        }
        else {
            Remove-Item -Recurse -Force $path
            Write-Ok "Deleted $label"
        }
    }
    else {
        Write-Skip $label
    }
}

Write-Step "Stopping Luma containers"

Push-Location $RepoRoot
try {
    foreach ($file in @("docker-compose.dev.yml", "docker-compose.yml")) {
        if (Test-Path (Join-Path $RepoRoot $file)) {
            $downArgs = @("compose", "-f", $file, "down")
            if ($removeData) { $downArgs += "-v" }

            if ($WhatIf) {
                Write-Host "   [WhatIf] docker $($downArgs -join ' ')" -ForegroundColor Yellow
            }
            else {
                $ErrorActionPreference = "Continue"
                & docker @downArgs 2>&1 | Out-Null
                $ErrorActionPreference = "Stop"
                $suffix = if ($removeData) { " (volumes removed)" } else { "" }
                Write-Ok "Stopped containers from $file$suffix"
            }
        }
    }
}
finally {
    Pop-Location
}

Write-Step "Removing build artifacts"
Remove-IfExists $ArtifactsDir    "artifacts/          (Flutter web build + Go binary)"
Remove-IfExists $AirTmpDir       "src/luma/tmp/       (Air live-reload cache)"
Remove-IfExists $FlutterBuild    "src/luma-web/build/ (Flutter build cache)"

if ($removeImages) {
    Write-Step "Removing Luma Docker images"

    foreach ($tag in @("luma:latest", "luma:dev")) {
        $imageId = docker images -q $tag 2>$null
        if ($imageId) {
            if ($WhatIf) {
                Write-Host "   [WhatIf] docker rmi $tag" -ForegroundColor Yellow
            }
            else {
                docker rmi $tag 2>$null
                Write-Ok "Removed image $tag"
            }
        }
        else {
            Write-Skip $tag
        }
    }
}

Write-Host ""
if ($WhatIf) {
    Write-Host "Dry run complete -- nothing was deleted." -ForegroundColor Yellow
    Write-Host "Re-run without -WhatIf to apply these changes." -ForegroundColor DarkGray
}
else {
    Write-Host "Clean complete." -ForegroundColor Green
    if ($removeData) {
        Write-Warn "Database volumes were deleted."
        Write-Warn "Haven will be UNCLAIMED on next start -- run '.\tools\win\run.ps1 -Fresh' or just run.ps1."
    }
    if ($removeImages) {
        Write-Host "   Docker images removed. Run '.\tools\win\build.ps1' to rebuild." -ForegroundColor DarkGray
    }
}
Write-Host ""
