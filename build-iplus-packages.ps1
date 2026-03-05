<#
.SYNOPSIS
    Builds the standard project and then generates iPlus NuGet packages.
    Based on instructions in docs/iplus-packages/generate-custom-package-spec.md
#>

$ErrorActionPreference = "Stop"

# 1. Clean artifacts
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Step 1: Cleaning previous artifacts..." -ForegroundColor Cyan
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan

if (Test-Path "artifacts") {
    Write-Host "Removing 'artifacts' directory..."
    Remove-Item -Path "artifacts" -Recurse -Force
} else {
    Write-Host "'artifacts' directory not found. Skipping clean."
}

# 2. Run standard build
Write-Host "`n------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Step 2: Running standard build (build.cmd)..." -ForegroundColor Cyan
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan

if (Test-Path "build.cmd") {
    & .\build.cmd
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Standard build failed with exit code $LASTEXITCODE."
        exit $LASTEXITCODE
    }
} else {
    Write-Error "build.cmd not found in the current directory."
    exit 1
}

# 3. Generate iPlus packages
Write-Host "`n------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Step 3: Generating iPlus packages..." -ForegroundColor Cyan
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan

$solutionFile = "EFCore.sln"
Write-Host "Running dotnet pack on $solutionFile with UseIPlusPackages=true..."

# Note: The documentation mentions that packing might fail on test projects (e.g. EFCore.AspNet.Specification.Tests)
# due to type conflicts, but the main packages will likely be generated successfully.
# We reset ErrorActionPreference locally to allow continuing after pack errors.
$origErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"

& dotnet pack $solutionFile -c Release -p:UseIPlusPackages=true

$ErrorActionPreference = $origErrorAction

# 4. Verify results
Write-Host "`n------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Verification..." -ForegroundColor Cyan
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan

$packageDir = Join-Path "artifacts" "packages" "Release" "Shipping"

if (Test-Path $packageDir) {
    $packages = Get-ChildItem -Path $packageDir -Filter "iPlus.*.nupkg"
    
    if ($packages.Count -gt 0) {
        Write-Host "SUCCESS: Generated $($packages.Count) iPlus packages:" -ForegroundColor Green
        $packages | ForEach-Object { Write-Host " - $($_.Name)" -ForegroundColor Green }
        Write-Host "`nLocation: $packageDir" -ForegroundColor Gray
    } else {
        Write-Warning "WARNING: No packages starting with 'iPlus.' were found in $packageDir."
    }
} else {
    Write-Warning "WARNING: Package directory not found: $packageDir"
}

Write-Host "`nDone."
