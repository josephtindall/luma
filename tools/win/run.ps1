param(
    [switch]$Fresh,
    [switch]$Prod,
    [switch]$Detach,
    [switch]$DbOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot  = Resolve-Path (Join-Path (Join-Path $PSScriptRoot "..") "..")
$WebOutDir = Join-Path (Join-Path $RepoRoot "artifacts") "web"

function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "   $msg" -ForegroundColor Yellow }
function Write-Info($msg) { Write-Host "   $msg" -ForegroundColor DarkGray }

function Assert-Tool($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Write-Error "'$name' is not installed or not in PATH. Please install it first."
    }
}

Assert-Tool "docker"

$composeFile = if ($Prod) { "docker-compose.yml" } else { "docker-compose.dev.yml" }
$mode        = if ($Prod) { "production" } else { "development" }

if ($Prod -and -not (Test-Path (Join-Path $RepoRoot ".env"))) {
    Write-Host ""
    Write-Host "!! No .env file found -- production mode requires real secrets." -ForegroundColor Red
    Write-Host "   Copy .env.example to .env, then fill in:" -ForegroundColor Yellow
    Write-Host "     LUMA_DB_PASS, HAVEN_JWT_SIGNING_KEY, LUMA_PUBLIC_URL" -ForegroundColor Yellow
    Write-Host ""
}

Push-Location $RepoRoot
try {
   if ($Fresh) {
        $cleanScript = Join-Path $PSScriptRoot "clean.ps1"
        Write-Step "Cleaning stale artifacts and caches"
        & PowerShell -ExecutionPolicy Bypass -File $cleanScript -Data
        if ($LASTEXITCODE -ne 0) { Write-Error "Clean failed." }

        $buildScript = Join-Path $PSScriptRoot "build.ps1"
        Write-Step "Rebuilding Flutter web app"
        & PowerShell -ExecutionPolicy Bypass -File $buildScript -Web
        if ($LASTEXITCODE -ne 0) { Write-Error "Flutter web build failed." }

        Write-Warn "Haven will generate a new setup token on startup."
        Write-Warn "Watch for it in the logs -- it looks like:"
        Write-Warn "  ========================================"
        Write-Warn "    Setup token: <base64url string>"
        Write-Warn "  ========================================"
        Write-Info "After starting, open http://localhost:8002 and paste the token."
    }

    if (-not $Prod) {
        $webIndex = Join-Path $WebOutDir "index.html"
        if (Test-Path $webIndex) {
            $env:LUMA_STATIC_DIR = "/artifacts/web"
            Write-Host ""
            Write-Ok "Flutter web app found at artifacts/web/"
            Write-Info "Luma will serve it at http://localhost:8002"
        }
        else {
            $env:LUMA_STATIC_DIR = ""
            Write-Host ""
            Write-Warn "artifacts/web/ not found -- Luma will not serve the Flutter app."
            Write-Warn "Run '.\tools\win\build.ps1 -Web' first, then restart."
        }
    }

    $composeArgs = @("compose", "-f", $composeFile, "up")
    if ($Detach)  { $composeArgs += "-d" }
    if ($DbOnly)  { $composeArgs += @("postgres", "redis", "haven") }

    $label = $mode
    if ($DbOnly)  { $label += " (infrastructure only -- Luma not started)" }
    if ($Fresh)   { $label += " [FRESH -- Haven is UNCLAIMED]" }

    Write-Step "Starting Luma -- $label"
    Write-Info "Compose file : $composeFile"
    Write-Info "Command      : docker $($composeArgs -join ' ')"

    if (-not $Prod) {
        Write-Host ""
        Write-Info "Endpoints:"
        Write-Info "  http://localhost:8002   Luma (app + web UI)"
        Write-Info "  http://localhost:8080   Haven API (internal only)"
        Write-Info "  localhost:5432          PostgreSQL"
        Write-Info "  localhost:6379          Redis"
    }

    if ($DbOnly) {
        Write-Host ""
        Write-Warn "Luma is not started. Run it locally in another terminal:"
        Write-Info "  cd src\luma"
        Write-Info '  $env:LUMA_DB_URL      = "postgres://luma_user:devpass@localhost:5432/luma?sslmode=disable&search_path=luma"'
        Write-Info '  $env:LUMA_REDIS_URL   = "redis://localhost:6379"'
        Write-Info '  $env:LUMA_HAVEN_URL   = "http://localhost:8080"'
        Write-Info '  $env:LUMA_PUBLIC_URL  = "http://localhost:8002"'
        if (Test-Path (Join-Path $WebOutDir "index.html")) {
            $absWeb = (Resolve-Path $WebOutDir).Path
            Write-Info "  `$env:LUMA_STATIC_DIR = '$absWeb'"
        }
        Write-Info "  go run ./cmd/server"
    }

    if ($Fresh -and $Detach) {
        Write-Host ""
        Write-Warn "Stack started in background. To find your setup token:"
        Write-Info "  docker compose -f $composeFile logs haven"
    }

    Write-Host ""

    & docker @composeArgs
    if ($LASTEXITCODE -ne 0) { Write-Error "docker compose failed with exit code $LASTEXITCODE." }
}
finally {
    Pop-Location
    Remove-Item Env:LUMA_STATIC_DIR -ErrorAction SilentlyContinue
}
