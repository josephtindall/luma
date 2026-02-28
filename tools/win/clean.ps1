# clean.ps1 -- Remove Luma build artifacts, containers, and volumes.
#
# USAGE (run from the repo root):
#   .\tools\win\clean.ps1              # stop containers + delete artifacts + clear caches
#   .\tools\win\clean.ps1 -Data        # also delete database and Redis volumes
#   .\tools\win\clean.ps1 -Images      # also remove luma:latest and luma:dev Docker images
#   .\tools\win\clean.ps1 -Full        # everything above (complete reset)
#   .\tools\win\clean.ps1 -WhatIf      # preview what would be deleted -- nothing is changed
#
# WHAT THIS DOES:
#   Default (no flags):
#     - Stops and removes all Luma containers (docker compose down).
#     - Deletes artifacts/ (Flutter web build + Linux Go binary).
#     - Clears the Air live-reload temp directory (src/luma/tmp/).
#     - Clears the Flutter build cache (src/luma-web/build/).
#     Your .env file and all source code are never touched.
#
#   -Data:
#     Everything above, PLUS deletes the Docker volumes (PostgreSQL data, Redis
#     data). This destroys your local database -- Haven resets to UNCLAIMED on
#     the next start. Use this when you want a completely fresh setup wizard run.
#     Equivalent to: .\tools\win\run.ps1 -Fresh (but without immediately restarting).
#
#   -Images:
#     Everything in the default, PLUS removes the luma:latest and luma:dev
#     Docker images. The next build will download base images fresh and recompile.
#
#   -Full:
#     Combines -Data and -Images. Returns the project to a state as if it was
#     just cloned. You will need to run build.ps1 and run.ps1 again after this.
#
#   -WhatIf:
#     Prints every action that would be taken without executing any of them.
#     Safe to run at any time to understand what a clean would affect.
#
# NOTE: This script never modifies .env, source files, or git history.

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

# -- Helpers ------------------------------------------------------------------

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

# -- Stop containers -----------------------------------------------------------

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

# -- Remove build artifacts ----------------------------------------------------

Write-Step "Removing build artifacts"
Remove-IfExists $ArtifactsDir    "artifacts/          (Flutter web build + Go binary)"
Remove-IfExists $AirTmpDir       "src/luma/tmp/       (Air live-reload cache)"
Remove-IfExists $FlutterBuild    "src/luma-web/build/ (Flutter build cache)"

# -- Remove Docker images ------------------------------------------------------

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

# -- Summary -------------------------------------------------------------------

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
