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

$Registry = $Registry.TrimEnd("/")
$FullTag   = "$Registry/luma:$Tag"
$LatestTag = "$Registry/luma:latest"

if (-not $SkipBuild) {
    Write-Step "Building production Docker image (luma:latest)"

    docker build -f "$SrcGoDir\Dockerfile" -t luma:latest "$SrcGoDir"
    if ($LASTEXITCODE -ne 0) { Write-Error "Docker build failed." }

    Write-Ok "luma:latest built."
}
else {
    $imageId = docker images -q luma:latest 2>$null
    if (-not $imageId) {
        Write-Error "luma:latest not found. Run '.\tools\win\build.ps1' first, or remove -SkipBuild."
    }
    Write-Info "Using existing luma:latest image."
}

Write-Step "Tagging image"

docker tag luma:latest $FullTag
if ($LASTEXITCODE -ne 0) { Write-Error "docker tag failed." }
Write-Ok "Tagged as $FullTag"

$pushLatest = $Tag -ne "latest"
if ($pushLatest) {
    docker tag luma:latest $LatestTag
    if ($LASTEXITCODE -ne 0) { Write-Error "docker tag (latest) failed." }
    Write-Ok "Tagged as $LatestTag"
}

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

if ($WithAssets) {
    Write-Step "Exporting release assets into artifacts/"

    if (-not (Test-Path $ArtifactsDir)) {
        New-Item -ItemType Directory -Path $ArtifactsDir | Out-Null
    }

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

Write-Host "`nPublish complete." -ForegroundColor Green
Write-Info "Image : $FullTag"
if ($pushLatest)  { Write-Info "Image : $LatestTag" }
if ($WithAssets)  { Write-Info "Assets: artifacts/" }
Write-Host ""
Write-Host "Next steps:" -ForegroundColor DarkGray
Write-Info "  Update the luma image reference in docker-compose.yml, then:"
Write-Info "  docker compose pull && docker compose up -d"
Write-Host ""
