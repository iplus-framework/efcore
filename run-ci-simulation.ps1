#Requires -Version 5.1
$ErrorActionPreference = "Stop"

Write-Host "=== MergeOption GitHub CI Simulation ===" -ForegroundColor Cyan
Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host ""

# Ensure output directory exists
New-Item -ItemType Directory -Force -Path "artifacts\TestResults" | Out-Null

try {
    # Phase 1: Setup and Build
    Write-Host "=== PHASE 1: Setup and Build ===" -ForegroundColor Magenta
    
    & .\restore.cmd *>&1 | Out-File "artifacts\TestResults\restore-output.log"
    if ($LASTEXITCODE -ne 0) { throw "Restore failed" }
    
    . .\activate.ps1
    
    & .\build.cmd -c Release *>&1 | Tee-Object -FilePath "artifacts\TestResults\build-output.log"
    if ($LASTEXITCODE -ne 0) { throw "Build failed" }
    
    Write-Host ""
    
    # Phase 2: MergeOption Tests
    Write-Host "=== PHASE 2: MergeOption Tests ===" -ForegroundColor Magenta
    
    # SQL Server
    dotnet test `
        .\test\EFCore.SqlServer.FunctionalTests\EFCore.SqlServer.FunctionalTests.csproj `
        --filter "FullyQualifiedName~MergeOption" `
        --configuration Release --no-build `
        --logger "trx;LogFileName=sqlserver-mergeoption.trx" `
        *>&1 | Tee-Object -FilePath "artifacts\TestResults\sqlserver-tests.log"
    
    if ($LASTEXITCODE -ne 0) { throw "SQL Server tests failed" }
    
    # SQLite
    dotnet test `
        .\test\EFCore.Sqlite.FunctionalTests\EFCore.Sqlite.FunctionalTests.csproj `
        --filter "FullyQualifiedName~MergeOption" `
        --configuration Release --no-build `
        --logger "trx;LogFileName=sqlite-mergeoption.trx" `
        *>&1 | Tee-Object -FilePath "artifacts\TestResults\sqlite-tests.log"
    
    if ($LASTEXITCODE -ne 0) { throw "SQLite tests failed" }
    
    Write-Host ""
    Write-Host "🎉 All CI simulation checks passed!" -ForegroundColor Green
    Write-Host "Results saved to: artifacts\TestResults\" -ForegroundColor Cyan
    
    exit 0
    
} catch {
    Write-Host ""
    Write-Host "❌ CI simulation failed: $_" -ForegroundColor Red
    Write-Host "Check logs in: artifacts\TestResults\" -ForegroundColor Yellow
    exit 1
}
