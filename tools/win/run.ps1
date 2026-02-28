# run.ps1 — Start the Luma stack (database, cache, Haven, and Luma server).
#
# USAGE (run from the repo root):
#   .\tools\win\run.ps1              # dev mode — live-reload Go, serve Flutter from artifacts/web/
#   .\tools\win\run.ps1 -Fresh       # dev mode — wipe DB first (resets Haven to UNCLAIMED for setup wizard)
#   .\tools\win\run.ps1 -Prod        # production mode (requires .env)
#   .\tools\win\run.ps1 -Detach      # start in background (combine with -Fresh or -Prod)
#   .\tools\win\run.ps1 -DbOnly      # postgres + redis + Haven only (run Go server locally)
#
# WHAT THIS DOES:
#   Development mode (default):
#     - Starts PostgreSQL 16, Redis 7, Haven, and Luma with live-reload (Air).
#     - Go source (src/luma/) is bind-mounted at /src — edit .go files and the
#       server restarts automatically. No rebuild needed.
#     - If artifacts/web/ exists, Luma serves the Flutter app at http://localhost:8002.
#       Build it first with: .\tools\win\build.ps1 -Web
#     - Safe dev defaults apply when .env is missing (devpass, zero JWT key).
#     - Exposed ports:
#         http://localhost:8002  Luma (Go server + Flutter web app)
#         http://localhost:8080  Haven API  (internal — browser never calls it directly)
#         localhost:5432         PostgreSQL
#         localhost:6379         Redis
#
#   -Fresh (Reset to UNCLAIMED — use this to test the setup wizard):
#     - Tears down the running stack and deletes the database + Redis volumes.
#     - On restart, Haven initialises from scratch in UNCLAIMED state.
#     - A new one-time setup token is printed to Haven's startup logs.
#     - After the stack is running, open http://localhost:8002 — it will redirect
#       to /setup. Paste the token from Haven's logs to begin the wizard.
#     - To retrieve the token after starting detached:
#         docker compose -f docker-compose.dev.yml logs haven
#
#   -Prod (production mode):
#     - Uses docker-compose.yml (production image, no bind mounts, no dev defaults).
#     - Requires a .env file with real secrets. The server refuses to start without
#       LUMA_DB_PASS, HAVEN_JWT_SIGNING_KEY, LUMA_PUBLIC_URL.
#     - Copy .env.example to .env and fill in values before using this flag.
#
#   -DbOnly (infrastructure only):
#     - Starts postgres, redis, and Haven — but not Luma itself.
#     - In a separate terminal, run Go directly on the host:
#         cd src/luma && go run ./cmd/server
#       Set LUMA_STATIC_DIR to artifacts/web/ if you want to serve the web app.
#     - Useful for fast iteration without rebuilding/restarting the Go container.
#
# PREREQUISITES:
#   - Docker Desktop must be running.
#   - Build artifacts first: .\tools\win\build.ps1
#   - Production only: copy .env.example to .env and fill in secrets.

param(
    [switch]$Fresh,
    [switch]$Prod,
    [switch]$Detach,
    [switch]$DbOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot  = Resolve-Path (Join-Path $PSScriptRoot ".." "..")
$WebOutDir = Join-Path $RepoRoot "artifacts" "web"

# ── Helpers ──────────────────────────────────────────────────────────────────

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

# ── Compose file ─────────────────────────────────────────────────────────────

$composeFile = if ($Prod) { "docker-compose.yml" } else { "docker-compose.dev.yml" }
$mode        = if ($Prod) { "production" } else { "development" }

# ── Production: require .env ──────────────────────────────────────────────────

if ($Prod -and -not (Test-Path (Join-Path $RepoRoot ".env"))) {
    Write-Host ""
    Write-Host "!! No .env file found — production mode requires real secrets." -ForegroundColor Red
    Write-Host "   Copy .env.example to .env, then fill in:" -ForegroundColor Yellow
    Write-Host "     LUMA_DB_PASS, HAVEN_JWT_SIGNING_KEY, LUMA_PUBLIC_URL" -ForegroundColor Yellow
    Write-Host ""
}

Push-Location $RepoRoot
try {
    # ── -Fresh: wipe volumes (reset Haven to UNCLAIMED) ──────────────────────

    if ($Fresh) {
        Write-Step "Wiping database volumes — Haven will reset to UNCLAIMED"
        & docker compose -f $composeFile down -v 2>$null
        if ($LASTEXITCODE -ne 0) {
            # No containers were running — that's fine.
            Write-Info "No running containers to stop (volumes may already be clean)."
        }
        else {
            Write-Ok "Stack stopped and volumes deleted."
        }
        Write-Warn "Haven will generate a new setup token on startup."
        Write-Warn "Watch for it in the logs — it looks like:"
        Write-Warn "  ========================================"
        Write-Warn "    Setup token: <base64url string>"
        Write-Warn "    Expires in:  2 hours"
        Write-Warn "  ========================================"
        Write-Info "After starting, open http://localhost:8002 and paste the token."
    }

    # ── LUMA_STATIC_DIR: point the container at the Flutter build ────────────
    # The dev compose mounts ./artifacts/web into the container at /artifacts/web.
    # Setting LUMA_STATIC_DIR=/artifacts/web tells the Go server to serve it.

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
            Write-Warn "artifacts/web/ not found — Luma will not serve the Flutter app."
            Write-Warn "Run '.\tools\win\build.ps1 -Web' first, then restart."
        }
    }

    # ── Build compose command ─────────────────────────────────────────────────

    $composeArgs = [System.Collections.Generic.List[string]]::new()
    $composeArgs.AddRange([string[]]@("compose", "-f", $composeFile, "up"))
    if ($Detach)  { $composeArgs.Add("-d") }
    if ($DbOnly)  { $composeArgs.AddRange([string[]]@("postgres", "redis", "haven")) }

    $label = $mode
    if ($DbOnly)  { $label += " (infrastructure only — Luma not started)" }
    if ($Fresh)   { $label += " [FRESH — Haven is UNCLAIMED]" }

    Write-Step "Starting Luma — $label"
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
    # Clean up env var so it doesn't leak into the parent shell session.
    Remove-Item Env:LUMA_STATIC_DIR -ErrorAction SilentlyContinue
}
