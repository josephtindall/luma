# publish.ps1 -- Tag and push the Luma Docker image to a container registry.
#
# USAGE (run from the repo root):
#   .\tools\win\publish.ps1 -Registry ghcr.io/yourname                  # push as latest
#   .\tools\win\publish.ps1 -Registry ghcr.io/yourname -Tag v1.0.0      # push as v1.0.0 + latest
#   .\tools\win\publish.ps1 -Registry ghcr.io/yourname -SkipBuild        # push existing luma:latest
#   .\tools\win\publish.ps1 -Registry ghcr.io/yourname -WithAssets       # also export web + binary
#
# WHAT THIS DOES:
#   1. Builds the production Docker image (luma:latest) unless -SkipBuild is set.
#   2. Tags it as <registry>/luma:<tag>  (default tag: "latest").
#   3. If a specific -Tag is given (e.g. v1.0.0), also tags and pushes as "latest".
#   4. Pushes the tagged image to the registry.
#   5. With -WithAssets: also writes the static Go binary and Flutter web build
#      into artifacts/ so they can be attached to a GitHub release or deployed
#      separately (e.g. web app to S3/CDN, binary to a VM).
#
# IMPORTANT -- WEB APP IN PRODUCTION:
#   The production Docker image contains only the Go binary and database migrations.
#   The Flutter web app (artifacts/web/) is deployed separately. Options:
#     a) Serve from nginx/Caddy reverse proxy alongside the Go container.
#     b) Upload artifacts/web/ to an S3 bucket or CDN (Cloudflare, Vercel, etc.).
#     c) For simple self-hosted setups, bind-mount artifacts/web/ into the container
#        and set LUMA_STATIC_DIR in your docker-compose.yml override.
#
# PREREQUISITES:
#   - Docker Desktop must be running.
#   - Log in to your registry first:
#       docker login ghcr.io          (GitHub Container Registry)
#       docker login                   (Docker Hub)
#   - Build the Flutter web app before -WithAssets:
#       .\tools\win\build.ps1 -Web
#
# EXAMPLES:
#   # Push to GitHub Container Registry with a version tag
#   .\tools\win\publish.ps1 -Registry ghcr.io/josephtindall -Tag v1.0.0
#
#   # Push to Docker Hub
#   .\tools\win\publish.ps1 -Registry docker.io/josephtindall -Tag v1.0.0
#
#   # Full release: build everything, push image, export assets for GitHub release
#   .\tools\win\build.ps1 -All
#   .\tools\win\publish.ps1 -Registry ghcr.io/josephtindall -Tag v1.0.0 -WithAssets

param(
    [Parameter(Mandatory = $true)]
    [string]$Registry,

    [string]$Tag = "latest",

    [switch]$SkipBuild,
    [switch]$WithAssets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot     = Resolve-Path (Join-Path (Join-Path $PSScriptRoot "..") "..")
$SrcGoDir     = Join-Path (Join-Path $RepoRoot "src") "luma"
$SrcWebDir    = Join-Path (Join-Path $RepoRoot "src") "luma-web"
$ArtifactsDir = Join-Path $RepoRoot "artifacts"
$WebOutDir    = Join-Path $ArtifactsDir "web"

# -- Helpers ------------------------------------------------------------------

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

# Normalise registry -- strip trailing slash.
$Registry = $Registry.TrimEnd("/")
$FullTag   = "$Registry/luma:$Tag"
$LatestTag = "$Registry/luma:latest"

# -- Build ---------------------------------------------------------------------

if (-not $SkipBuild) {
    Write-Step "Building production Docker image (luma:latest)"

    docker build -f "$SrcGoDir\Dockerfile" -t luma:latest "$SrcGoDir"
    if ($LASTEXITCODE -ne 0) { Write-Error "Docker build failed." }

    Write-Ok "luma:latest built."
}
else {
    # Verify the image actually exists before trying to tag/push.
    $imageId = docker images -q luma:latest 2>$null
    if (-not $imageId) {
        Write-Error "luma:latest not found. Run '.\tools\win\build.ps1' first, or remove -SkipBuild."
    }
    Write-Info "Using existing luma:latest image."
}

# -- Tag -----------------------------------------------------------------------

Write-Step "Tagging image"

docker tag luma:latest $FullTag
if ($LASTEXITCODE -ne 0) { Write-Error "docker tag failed." }
Write-Ok "Tagged as $FullTag"

# When a specific version is given, also push as "latest" for convenience.
$pushLatest = $Tag -ne "latest"
if ($pushLatest) {
    docker tag luma:latest $LatestTag
    if ($LASTEXITCODE -ne 0) { Write-Error "docker tag (latest) failed." }
    Write-Ok "Tagged as $LatestTag"
}

# -- Push ----------------------------------------------------------------------

Write-Step "Pushing to $Registry"

docker push $FullTag
if ($LASTEXITCODE -ne 0) {
    $host_ = $Registry.Split("/")[0]
    Write-Error "Push failed. Are you logged in? Try: docker login $host_"
}
Write-Ok "Pushed $FullTag"

if ($pushLatest) {
    docker push $LatestTag
    if ($LASTEXITCODE -ne 0) { Write-Error "Push of latest tag failed." }
    Write-Ok "Pushed $LatestTag"
}

# -- Export assets into artifacts/ (optional) ----------------------------------

if ($WithAssets) {
    Write-Step "Exporting release assets into artifacts/"

    if (-not (Test-Path $ArtifactsDir)) {
        New-Item -ItemType Directory -Path $ArtifactsDir | Out-Null
    }

    # -- Static Linux binary -- extracted from the published image.
    # This avoids requiring Go to be installed on the release machine.
    Write-Info "Extracting Go binary from image..."
    $container = & docker create luma:latest
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create temporary container." }

    try {
        docker cp "${container}:/usr/local/bin/luma" (Join-Path $ArtifactsDir "luma")
        if ($LASTEXITCODE -ne 0) { Write-Error "Failed to extract binary from container." }
        Write-Ok "artifacts/luma  (static linux/amd64 Go binary)"
    }
    finally {
        docker rm $container | Out-Null
    }

    # -- Flutter web build -- copy from src/luma-web/build/web/ if present,
    # otherwise check if artifacts/web/ already exists from a prior build run.
    $flutterSrc  = Join-Path (Join-Path $SrcWebDir "build") "web"
    $webReady    = Test-Path (Join-Path $WebOutDir "index.html")
    $flutterDone = Test-Path (Join-Path $flutterSrc "index.html")

    if ($webReady) {
        Write-Ok "artifacts/web/  (Flutter web app -- already present)"
    }
    elseif ($flutterDone) {
        if (Test-Path $WebOutDir) { Remove-Item -Recurse -Force $WebOutDir }
        New-Item -ItemType Directory -Path $WebOutDir | Out-Null
        Copy-Item -Recurse -Path (Join-Path $flutterSrc "*") -Destination $WebOutDir
        Write-Ok "artifacts/web/  (Flutter web app -- copied from src/luma-web/build/web/)"
    }
    else {
        Write-Warn "Flutter web app not found in artifacts/web/ or src/luma-web/build/web/."
        Write-Warn "Run '.\tools\win\build.ps1 -Web' and re-run publish with -WithAssets."
    }

    Write-Host ""
    Write-Info "Release assets:"
    Write-Info "  artifacts/luma     -- attach to GitHub release as a Linux binary"
    Write-Info "  artifacts/web/     -- upload to S3, CDN, or serve from nginx"
}

# -- Summary -------------------------------------------------------------------

Write-Host "`nPublish complete." -ForegroundColor Green
Write-Info "Image : $FullTag"
if ($pushLatest)  { Write-Info "Image : $LatestTag" }
if ($WithAssets)  { Write-Info "Assets: artifacts/" }
Write-Host ""
Write-Host "Next steps:" -ForegroundColor DarkGray
Write-Info "  Update the luma image reference in docker-compose.yml, then:"
Write-Info "  docker compose pull && docker compose up -d"
Write-Host ""
