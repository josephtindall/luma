# build.ps1 — Build Luma artifacts: Flutter web app and/or Go backend.
#
# USAGE (run from the repo root):
#   .\tools\win\build.ps1              # build Flutter web app + production Docker image (default)
#   .\tools\win\build.ps1 -Web         # Flutter web only  → artifacts/web/
#   .\tools\win\build.ps1 -Go          # production Docker image only (luma:latest)
#   .\tools\win\build.ps1 -Dev         # development Docker image (luma:dev)
#   .\tools\win\build.ps1 -Binary      # static linux/amd64 Go binary → artifacts/luma
#   .\tools\win\build.ps1 -All         # all four targets
#
# WHAT THIS DOES:
#   Default / no flags:
#     Runs both -Web and -Go. Everything you need to run the full stack.
#
#   -Web (Flutter web app):
#     Runs 'flutter build web --release' inside src/luma-web/, then copies the
#     output into artifacts/web/. The Go server reads this directory when
#     LUMA_STATIC_DIR is set — the run script sets it automatically if the
#     folder exists. Rebuild whenever you change Flutter code.
#
#   -Go (production Docker image):
#     Builds the multi-stage production Docker image (luma:latest). The image
#     contains a single static Go binary and runs as an unprivileged user.
#     The Flutter web app is NOT baked into this image — serve it separately
#     via nginx, a CDN, or a bind-mounted volume (see run.ps1 / publish.ps1).
#
#   -Dev (development Docker image):
#     Builds luma:dev, which includes the full Go toolchain and Air (live-reload).
#     Source code is bind-mounted at /src — edit .go files and the server
#     restarts automatically. This image is only for local development.
#
#   -Binary (static Linux binary):
#     Cross-compiles a CGO-free linux/amd64 binary into artifacts/luma.
#     Useful for deploying without Docker or for attaching to a release.
#
# ARTIFACTS PRODUCED:
#   artifacts/web/   Flutter web build (served by Go via LUMA_STATIC_DIR)
#   artifacts/luma   Static linux/amd64 Go binary (Binary target only)
#
# PREREQUISITES:
#   -Web    requires: flutter (flutter.dev)
#   -Go     requires: docker
#   -Dev    requires: docker
#   -Binary requires: go 1.23+

param(
    [switch]$Web,
    [switch]$Go,
    [switch]$Dev,
    [switch]$Binary,
    [switch]$All
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot     = Resolve-Path (Join-Path $PSScriptRoot ".." "..")
$SrcGoDir     = Join-Path $RepoRoot "src" "luma"
$SrcWebDir    = Join-Path $RepoRoot "src" "luma-web"
$ArtifactsDir = Join-Path $RepoRoot "artifacts"
$WebOutDir    = Join-Path $ArtifactsDir "web"

# ── Decide what to build ─────────────────────────────────────────────────────
# Default (no flags): build the Flutter web app AND the production Docker image.

$anyExplicit = $Web -or $Go -or $Dev -or $Binary -or $All
$buildWeb    = $Web    -or $All -or (-not $anyExplicit)
$buildGo     = $Go     -or $All -or (-not $anyExplicit)
$buildDev    = $Dev    -or $All
$buildBinary = $Binary -or $All

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

# ── Flutter web app ───────────────────────────────────────────────────────────

if ($buildWeb) {
    Write-Step "Building Flutter web app (src/luma-web/)"
    Assert-Tool "flutter"

    Push-Location $SrcWebDir
    try {
        # flutter build web produces output at src/luma-web/build/web/
        flutter build web --release
        if ($LASTEXITCODE -ne 0) { Write-Error "Flutter build failed." }
    }
    finally {
        Pop-Location
    }

    $flutterOut = Join-Path $SrcWebDir "build" "web"
    if (-not (Test-Path $flutterOut)) {
        Write-Error "Flutter build completed but output was not found at: $flutterOut"
    }

    # Sync output into artifacts/web/ — wipe first so stale files don't linger.
    if (Test-Path $WebOutDir) {
        Remove-Item -Recurse -Force $WebOutDir
    }
    New-Item -ItemType Directory -Path $WebOutDir | Out-Null
    Copy-Item -Recurse -Path (Join-Path $flutterOut "*") -Destination $WebOutDir

    Write-Ok "Flutter web app  →  artifacts/web/"
    Write-Info "Run the stack with:  .\tools\win\run.ps1"
    Write-Info "Luma will serve the app automatically (LUMA_STATIC_DIR is set by run.ps1)."
}

# ── Production Docker image ──────────────────────────────────────────────────

if ($buildGo) {
    Write-Step "Building production Docker image (luma:latest)"
    Assert-Tool "docker"

    # Build context is src/luma/ — contains Dockerfile, Go source, migrations.
    docker build -f "$SrcGoDir\Dockerfile" -t luma:latest "$SrcGoDir"
    if ($LASTEXITCODE -ne 0) { Write-Error "Production Docker build failed." }

    Write-Ok "luma:latest built."
    Write-Info "Deploy with:  .\tools\win\run.ps1 -Prod"
    Write-Info "Push with:    .\tools\win\publish.ps1 -Registry ghcr.io/yourname"
    Write-Warn "Note: The Flutter web app is NOT baked into this image."
    Write-Info "In production, serve artifacts/web/ from nginx or a CDN."
}

# ── Development Docker image ─────────────────────────────────────────────────

if ($buildDev) {
    Write-Step "Building development Docker image (luma:dev)"
    Assert-Tool "docker"

    docker build -f "$SrcGoDir\Dockerfile.dev" -t luma:dev "$SrcGoDir"
    if ($LASTEXITCODE -ne 0) { Write-Error "Development Docker build failed." }

    Write-Ok "luma:dev built."
    Write-Info "Start dev stack with:  .\tools\win\run.ps1"
}

# ── Static Linux binary ───────────────────────────────────────────────────────

if ($buildBinary) {
    Write-Step "Cross-compiling static linux/amd64 binary"
    Assert-Tool "go"

    if (-not (Test-Path $ArtifactsDir)) {
        New-Item -ItemType Directory -Path $ArtifactsDir | Out-Null
    }

    $outPath = Join-Path $ArtifactsDir "luma"

    $env:CGO_ENABLED = "0"
    $env:GOOS        = "linux"
    $env:GOARCH      = "amd64"

    Push-Location $SrcGoDir
    try {
        Write-Info "Compiling  ./cmd/server  →  artifacts/luma"
        go build -trimpath -o $outPath ./cmd/server
        if ($LASTEXITCODE -ne 0) { Write-Error "Go binary compilation failed." }
    }
    finally {
        Pop-Location
        Remove-Item Env:CGO_ENABLED -ErrorAction SilentlyContinue
        Remove-Item Env:GOOS        -ErrorAction SilentlyContinue
        Remove-Item Env:GOARCH      -ErrorAction SilentlyContinue
    }

    Write-Ok "artifacts/luma  (static linux/amd64 — no runtime dependencies)"
    Write-Info "Deploy this binary directly or copy it into a minimal container image."
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host "`nBuild complete.`n" -ForegroundColor Green
