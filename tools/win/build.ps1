param(
    [switch]$Web,
    [switch]$Go,
    [switch]$Dev,
    [switch]$Binary,
    [switch]$All
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot     = Resolve-Path (Join-Path (Join-Path $PSScriptRoot "..") "..")
$SrcGoDir     = Join-Path (Join-Path $RepoRoot "src") "luma"
$SrcWebDir    = Join-Path (Join-Path $RepoRoot "src") "luma-web"
$ArtifactsDir = Join-Path $RepoRoot "artifacts"
$WebOutDir    = Join-Path $ArtifactsDir "web"

$anyExplicit = $Web -or $Go -or $Dev -or $Binary -or $All
$buildWeb    = $Web    -or $All -or (-not $anyExplicit)
$buildGo     = $Go     -or $All -or (-not $anyExplicit)
$buildDev    = $Dev    -or $All
$buildBinary = $Binary -or $All

function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "   $msg" -ForegroundColor Yellow }
function Write-Info($msg) { Write-Host "   $msg" -ForegroundColor DarkGray }

function Assert-Tool($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Write-Error "'$name' is not installed or not in PATH. Please install it first."
    }
}

if ($buildWeb) {
    Write-Step "Building Flutter web app (src/luma-web/)"
    Assert-Tool "flutter"

    Push-Location $SrcWebDir
    try {
        flutter build web --release
        if ($LASTEXITCODE -ne 0) { Write-Error "Flutter build failed." }
    }
    finally {
        Pop-Location
    }

    $flutterOut = Join-Path (Join-Path $SrcWebDir "build") "web"
    if (-not (Test-Path $flutterOut)) {
        Write-Error "Flutter build completed but output was not found at: $flutterOut"
    }

   if (Test-Path $WebOutDir) {
        Remove-Item -Recurse -Force $WebOutDir
    }
    New-Item -ItemType Directory -Path $WebOutDir | Out-Null
    Copy-Item -Recurse -Path (Join-Path $flutterOut "*") -Destination $WebOutDir

    Write-Ok "Flutter web app  ->  artifacts/web/"
    Write-Info "Run the stack with:  .\tools\win\run.ps1"
    Write-Info "Luma will serve the app automatically (LUMA_STATIC_DIR is set by run.ps1)."
}

if ($buildGo) {
    Write-Step "Building production Docker image (luma:latest)"
    Assert-Tool "docker"

    docker build -f "$SrcGoDir\Dockerfile" -t luma:latest "$SrcGoDir"
    if ($LASTEXITCODE -ne 0) { Write-Error "Production Docker build failed." }

    Write-Ok "luma:latest built."
    Write-Info "Deploy with:  .\tools\win\run.ps1 -Prod"
    Write-Info "Push with:    .\tools\win\publish.ps1 -Registry ghcr.io/yourname"
    Write-Warn "Note: The Flutter web app is NOT baked into this image."
    Write-Info "In production, serve artifacts/web/ from nginx or a CDN."
}

if ($buildDev) {
    Write-Step "Building development Docker image (luma:dev)"
    Assert-Tool "docker"

    docker build -f "$SrcGoDir\Dockerfile.dev" -t luma:dev "$SrcGoDir"
    if ($LASTEXITCODE -ne 0) { Write-Error "Development Docker build failed." }

    Write-Ok "luma:dev built."
    Write-Info "Start dev stack with:  .\tools\win\run.ps1"
}

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
        Write-Info "Compiling  ./cmd/server  ->  artifacts/luma"
        go build -trimpath -o $outPath ./cmd/server
        if ($LASTEXITCODE -ne 0) { Write-Error "Go binary compilation failed." }
    }
    finally {
        Pop-Location
        Remove-Item Env:CGO_ENABLED -ErrorAction SilentlyContinue
        Remove-Item Env:GOOS        -ErrorAction SilentlyContinue
        Remove-Item Env:GOARCH      -ErrorAction SilentlyContinue
    }

    Write-Ok "artifacts/luma  (static linux/amd64 -- no runtime dependencies)"
    Write-Info "Deploy this binary directly or copy it into a minimal container image."
}

Write-Host "`nBuild complete.`n" -ForegroundColor Green
