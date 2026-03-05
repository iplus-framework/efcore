# MergeOption GitHub CI Test Simulation Plan

**Purpose:** Automate execution and analysis of GitHub CI/CD test procedures locally. This plan captures command outputs for problem diagnosis and validates the MergeOption feature is ready for CI.

**Target Audience:** Automated agents or developers running batch validation

**Execution Time:** ~60-90 minutes (mostly automated)

**Working Directory:** `C:\Devel\iplus-github\ef_main_iPlus`

---

## Output Directory Structure

All test outputs are saved to `artifacts\TestResults\` for analysis:

```
artifacts\TestResults\
├── build-output.log           # Build process output
├── build-errors.log           # Build warnings/errors only
├── sqlserver-tests.log        # SQL Server test execution
├── sqlserver-tests.trx        # SQL Server test results (XML)
├── sqlite-tests.log           # SQLite test execution
├── sqlite-tests.trx           # SQLite test results (XML)
├── core-tests.log             # EFCore.Tests execution
├── relational-tests.log       # Relational tests execution
└── test-summary.json          # Combined test results
```

---

## Phase 1: Environment Setup and Build (5-10 min)

### Task 1.1: Restore Dependencies
```powershell
Write-Host "=== Restoring Dependencies ===" -ForegroundColor Cyan

$restoreOutput = & .\restore.cmd 2>&1 | Tee-Object -Variable restoreLog
$restoreLog | Out-File "artifacts\TestResults\restore-output.log"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Restore failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Dependencies restored" -ForegroundColor Green
```

**Success Criteria:**
- Exit code: 0
- Output contains: "Restore complete"
- No error messages

---

### Task 1.2: Activate Development Environment
```powershell
Write-Host "=== Activating Environment ===" -ForegroundColor Cyan

. .\activate.ps1

# Verify activation
$dotnetPath = (Get-Command dotnet).Source
if ($dotnetPath -notlike "*ef_main_iPlus*") {
    Write-Host "❌ Wrong dotnet version active: $dotnetPath" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Environment activated: $dotnetPath" -ForegroundColor Green
```

**Success Criteria:**
- `dotnet` command points to `.dotnet\dotnet.exe` in repo
- Version: 10.0.100-rc.1.25451.107

---

### Task 1.3: Build Solution (Release Mode)
```powershell
Write-Host "=== Building Solution (Release) ===" -ForegroundColor Cyan

$buildStart = Get-Date

$buildOutput = & .\build.cmd -c Release 2>&1 | Tee-Object -Variable buildLog
$buildLog | Out-File "artifacts\TestResults\build-output.log"

$buildEnd = Get-Date
$buildDuration = ($buildEnd - $buildStart).TotalSeconds

# Extract errors and warnings
$buildErrors = $buildLog | Where-Object { $_ -match "error (CS|MSB)" }
$buildWarnings = $buildLog | Where-Object { $_ -match "warning (CS|MSB)" }

$buildErrors | Out-File "artifacts\TestResults\build-errors.log"
$buildWarnings | Out-File "artifacts\TestResults\build-warnings.log"

# Create summary
$buildSummary = @{
    ExitCode = $LASTEXITCODE
    Duration = $buildDuration
    ErrorCount = $buildErrors.Count
    WarningCount = $buildWarnings.Count
    Success = ($LASTEXITCODE -eq 0)
} | ConvertTo-Json

$buildSummary | Out-File "artifacts\TestResults\build-summary.json"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed with $($buildErrors.Count) errors" -ForegroundColor Red
    Write-Host "First error:" -ForegroundColor Yellow
    $buildErrors | Select-Object -First 1
    exit 1
}

if ($buildWarnings.Count -gt 0) {
    Write-Host "⚠️  Build succeeded with $($buildWarnings.Count) warnings" -ForegroundColor Yellow
} else {
    Write-Host "✅ Build succeeded (${buildDuration}s, 0 warnings)" -ForegroundColor Green
}
```

**Success Criteria:**
- Exit code: 0
- 0 errors
- 0 warnings (strict mode)
- Build time: < 120 seconds

---

## Phase 2: MergeOption Feature Tests (10-15 min)
### Task 2.1: Run SQL Server MergeOption Tests
```powershell
Write-Host "=== Running SQL Server MergeOption Tests ===" -ForegroundColor Cyan

$sqlServerStart = Get-Date

$sqlServerOutput = dotnet test `
    .\test\EFCore.SqlServer.FunctionalTests\EFCore.SqlServer.FunctionalTests.csproj `
    --filter "FullyQualifiedName~MergeOption" `
    --configuration Release `
    --no-build `
    --logger "console;verbosity=normal" `
    --logger "trx;LogFileName=sqlserver-mergeoption.trx" `
    2>&1 | Tee-Object -Variable sqlServerLog

$sqlServerLog | Out-File "artifacts\TestResults\sqlserver-tests.log"

$sqlServerEnd = Get-Date
$sqlServerDuration = ($sqlServerEnd - $sqlServerStart).TotalSeconds

# Parse test results
$sqlServerPassed = ($sqlServerLog | Select-String "Passed!.*?(\d+) passed").Matches.Groups[1].Value
$sqlServerFailed = ($sqlServerLog | Select-String "Failed!.*?(\d+) failed").Matches.Groups[1].Value
$sqlServerTotal = ($sqlServerLog | Select-String "Total: (\d+)").Matches.Groups[1].Value

if (-not $sqlServerPassed) { $sqlServerPassed = "0" }
if (-not $sqlServerFailed) { $sqlServerFailed = "0" }
if (-not $sqlServerTotal) { $sqlServerTotal = "0" }

$sqlServerSummary = @{
    Provider = "SQL Server"
    ExitCode = $LASTEXITCODE
    Duration = $sqlServerDuration
    Total = [int]$sqlServerTotal
    Passed = [int]$sqlServerPassed
    Failed = [int]$sqlServerFailed
    Success = ($LASTEXITCODE -eq 0 -and [int]$sqlServerFailed -eq 0)
} | ConvertTo-Json

$sqlServerSummary | Out-File "artifacts\TestResults\sqlserver-summary.json"

if ($LASTEXITCODE -ne 0 -or [int]$sqlServerFailed -gt 0) {
    Write-Host "❌ SQL Server tests failed: $sqlServerFailed failures" -ForegroundColor Red
    
    # Extract failed test names
    $failedTests = $sqlServerLog | Select-String "Failed\s+(.+)\[" | ForEach-Object { $_.Matches.Groups[1].Value }
    Write-Host "Failed tests:" -ForegroundColor Yellow
    $failedTests | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    
    exit 1
}

Write-Host "✅ SQL Server: $sqlServerPassed/$sqlServerTotal tests passed (${sqlServerDuration}s)" -ForegroundColor Green
```

**Success Criteria:**
- Exit code: 0
- 28 tests passed
- 0 tests failed
- Test time: < 30 seconds

---

### Task 2.2: Run SQLite MergeOption Tests
```powershell
Write-Host "=== Running SQLite MergeOption Tests ===" -ForegroundColor Cyan

$sqliteStart = Get-Date

$sqliteOutput = dotnet test `
    .\test\EFCore.Sqlite.FunctionalTests\EFCore.Sqlite.FunctionalTests.csproj `
    --filter "FullyQualifiedName~MergeOption" `
    --configuration Release `
    --no-build `
    --logger "console;verbosity=normal" `
    --logger "trx;LogFileName=sqlite-mergeoption.trx" `
    2>&1 | Tee-Object -Variable sqliteLog

$sqliteLog | Out-File "artifacts\TestResults\sqlite-tests.log"

$sqliteEnd = Get-Date
$sqliteDuration = ($sqliteEnd - $sqliteStart).TotalSeconds

# Parse test results
$sqlitePassed = ($sqliteLog | Select-String "Passed!.*?(\d+) passed").Matches.Groups[1].Value
$sqliteFailed = ($sqliteLog | Select-String "Failed!.*?(\d+) failed").Matches.Groups[1].Value
$sqliteTotal = ($sqliteLog | Select-String "Total: (\d+)").Matches.Groups[1].Value

if (-not $sqlitePassed) { $sqlitePassed = "0" }
if (-not $sqliteFailed) { $sqliteFailed = "0" }
if (-not $sqliteTotal) { $sqliteTotal = "0" }

$sqliteSummary = @{
    Provider = "SQLite"
    ExitCode = $LASTEXITCODE
    Duration = $sqliteDuration
    Total = [int]$sqliteTotal
    Passed = [int]$sqlitePassed
    Failed = [int]$sqliteFailed
    Success = ($LASTEXITCODE -eq 0 -and [int]$sqliteFailed -eq 0)
} | ConvertTo-Json

$sqliteSummary | Out-File "artifacts\TestResults\sqlite-summary.json"

if ($LASTEXITCODE -ne 0 -or [int]$sqliteFailed -gt 0) {
    Write-Host "❌ SQLite tests failed: $sqliteFailed failures" -ForegroundColor Red
    
    # Extract failed test names
    $failedTests = $sqliteLog | Select-String "Failed\s+(.+)\[" | ForEach-Object { $_.Matches.Groups[1].Value }
    Write-Host "Failed tests:" -ForegroundColor Yellow
    $failedTests | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    
    exit 1
}

Write-Host "✅ SQLite: $sqlitePassed/$sqliteTotal tests passed (${sqliteDuration}s)" -ForegroundColor Green
```

**Success Criteria:**
- Exit code: 0
- 28 tests passed
- 0 tests failed
- Test time: < 20 seconds

---

### Task 2.3: Verify SQL Baselines Exist
```powershell
Write-Host "=== Verifying SQL Baselines ===" -ForegroundColor Cyan

$baselinePattern = "*.verified.txt"
$sqlServerBaselines = Get-ChildItem "test\EFCore.SqlServer.FunctionalTests\Query" -Filter $baselinePattern -Recurse | Where-Object { $_.Name -like "*MergeOption*" }
$sqliteBaselines = Get-ChildItem "test\EFCore.Sqlite.FunctionalTests\Query" -Filter $baselinePattern -Recurse | Where-Object { $_.Name -like "*MergeOption*" }

$baselineReport = @{
    SqlServerBaselines = $sqlServerBaselines.Count
    SqliteBaselines = $sqliteBaselines.Count
    SqlServerFiles = $sqlServerBaselines.Name
    SqliteFiles = $sqliteBaselines.Name
} | ConvertTo-Json

$baselineReport | Out-File "artifacts\TestResults\baseline-check.json"

if ($sqlServerBaselines.Count -eq 0) {
    Write-Host "❌ No SQL Server baselines found!" -ForegroundColor Red
    exit 1
}

if ($sqliteBaselines.Count -eq 0) {
    Write-Host "❌ No SQLite baselines found!" -ForegroundColor Red
    exit 1
}

Write-Host "✅ SQL Server: $($sqlServerBaselines.Count) baseline files" -ForegroundColor Green
Write-Host "✅ SQLite: $($sqliteBaselines.Count) baseline files" -ForegroundColor Green
```

**Success Criteria:**
- SQL Server: > 0 baseline files
- SQLite: > 0 baseline files

---

## Phase 3: Regression Tests (30-60 min)

### Task 3.1: Run Core EFCore Tests
```powershell
Write-Host "=== Running EFCore.Tests (Regression) ===" -ForegroundColor Cyan

$coreStart = Get-Date

$coreOutput = dotnet test `
    .\test\EFCore.Tests\EFCore.Tests.csproj `
    --configuration Release `
    --no-build `
    --logger "console;verbosity=minimal" `
    --logger "trx;LogFileName=core-tests.trx" `
    2>&1 | Tee-Object -Variable coreLog

$coreLog | Out-File "artifacts\TestResults\core-tests.log"

$coreEnd = Get-Date
$coreDuration = ($coreEnd - $coreStart).TotalSeconds

# Parse results
$corePassed = ($coreLog | Select-String "Passed!.*?(\d+) passed").Matches.Groups[1].Value
$coreFailed = ($coreLog | Select-String "Failed!.*?(\d+) failed").Matches.Groups[1].Value

if (-not $corePassed) { $corePassed = "0" }
if (-not $coreFailed) { $coreFailed = "0" }

if ([int]$coreFailed -gt 0) {
    Write-Host "⚠️  EFCore.Tests: $coreFailed failures (check if pre-existing)" -ForegroundColor Yellow
} else {
    Write-Host "✅ EFCore.Tests: $corePassed passed (${coreDuration}s)" -ForegroundColor Green
}
```

**Success Criteria:**
- Exit code: 0 OR pre-existing failures only
- No NEW failures introduced by MergeOption

---

### Task 3.2: Run Relational Tests
```powershell
Write-Host "=== Running Relational.Tests (Regression) ===" -ForegroundColor Cyan

$relationalStart = Get-Date

$relationalOutput = dotnet test `
    .\test\EFCore.Relational.Tests\EFCore.Relational.Tests.csproj `
    --configuration Release `
    --no-build `
    --logger "console;verbosity=minimal" `
    --logger "trx;LogFileName=relational-tests.trx" `
    2>&1 | Tee-Object -Variable relationalLog

$relationalLog | Out-File "artifacts\TestResults\relational-tests.log"

$relationalEnd = Get-Date
$relationalDuration = ($relationalEnd - $relationalStart).TotalSeconds

# Parse results
$relationalPassed = ($relationalLog | Select-String "Passed!.*?(\d+) passed").Matches.Groups[1].Value
$relationalFailed = ($relationalLog | Select-String "Failed!.*?(\d+) failed").Matches.Groups[1].Value

if (-not $relationalPassed) { $relationalPassed = "0" }
if (-not $relationalFailed) { $relationalFailed = "0" }

if ([int]$relationalFailed -gt 0) {
    Write-Host "⚠️  Relational.Tests: $relationalFailed failures" -ForegroundColor Yellow
} else {
    Write-Host "✅ Relational.Tests: $relationalPassed passed (${relationalDuration}s)" -ForegroundColor Green
}
```

**Success Criteria:**
- Exit code: 0
- 0 new failures

---

## Phase 4: Analysis and Reporting

### Task 4.1: Generate Combined Test Report
```powershell
Write-Host "=== Generating Test Summary ===" -ForegroundColor Cyan

# Load individual results
$buildSum = Get-Content "artifacts\TestResults\build-summary.json" | ConvertFrom-Json
$sqlServerSum = Get-Content "artifacts\TestResults\sqlserver-summary.json" | ConvertFrom-Json
$sqliteSum = Get-Content "artifacts\TestResults\sqlite-summary.json" | ConvertFrom-Json

$overallReport = @{
    TestRun = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Build = @{
        Success = $buildSum.Success
        Duration = $buildSum.Duration
        Errors = $buildSum.ErrorCount
        Warnings = $buildSum.WarningCount
    }
    MergeOptionTests = @{
        SqlServer = @{
            Passed = $sqlServerSum.Passed
            Failed = $sqlServerSum.Failed
            Total = $sqlServerSum.Total
            Duration = $sqlServerSum.Duration
        }
        Sqlite = @{
            Passed = $sqliteSum.Passed
            Failed = $sqliteSum.Failed
            Total = $sqliteSum.Total
            Duration = $sqliteSum.Duration
        }
        Combined = @{
            Passed = $sqlServerSum.Passed + $sqliteSum.Passed
            Failed = $sqlServerSum.Failed + $sqliteSum.Failed
            Total = $sqlServerSum.Total + $sqliteSum.Total
        }
    }
    OverallSuccess = (
        $buildSum.Success -and
        $sqlServerSum.Success -and
        $sqliteSum.Success
    )
}

$overallReport | ConvertTo-Json -Depth 5 | Out-File "artifacts\TestResults\test-summary.json"

# Display summary
Write-Host ""
Write-Host "=== TEST SUMMARY ===" -ForegroundColor Cyan
Write-Host "Build: $(if($buildSum.Success){'✅ PASSED'}else{'❌ FAILED'})" -ForegroundColor $(if($buildSum.Success){'Green'}else{'Red'})
Write-Host "  Duration: $($buildSum.Duration)s"
Write-Host "  Errors: $($buildSum.ErrorCount)"
Write-Host "  Warnings: $($buildSum.WarningCount)"
Write-Host ""
Write-Host "MergeOption Tests: $(if($overallReport.MergeOptionTests.Combined.Failed -eq 0){'✅ PASSED'}else{'❌ FAILED'})" -ForegroundColor $(if($overallReport.MergeOptionTests.Combined.Failed -eq 0){'Green'}else{'Red'})
Write-Host "  SQL Server: $($sqlServerSum.Passed)/$($sqlServerSum.Total) passed ($($sqlServerSum.Duration)s)"
Write-Host "  SQLite: $($sqliteSum.Passed)/$($sqliteSum.Total) passed ($($sqliteSum.Duration)s)"
Write-Host "  TOTAL: $($overallReport.MergeOptionTests.Combined.Passed)/$($overallReport.MergeOptionTests.Combined.Total) passed"
Write-Host ""

if ($overallReport.OverallSuccess) {
    Write-Host "🎉 ALL CHECKS PASSED - Ready for CI" -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ CHECKS FAILED - Review logs in artifacts\TestResults\" -ForegroundColor Red
    exit 1
}
```

---

## Phase 5: Failure Analysis (On Demand)

### Task 5.1: Analyze Build Failures
```powershell
if (Test-Path "artifacts\TestResults\build-errors.log") {
    $errors = Get-Content "artifacts\TestResults\build-errors.log"
    if ($errors) {
        Write-Host "=== Build Errors Analysis ===" -ForegroundColor Yellow
        
        # Group by error code
        $errorGroups = $errors | Group-Object { 
            if ($_ -match "(error (CS|MSB)\d+)") { $matches[1] } else { "Other" }
        }
        
        foreach ($group in $errorGroups) {
            Write-Host "  $($group.Name): $($group.Count) occurrences" -ForegroundColor Yellow
            $group.Group | Select-Object -First 3 | ForEach-Object { Write-Host "    $_" }
        }
    }
}
```

### Task 5.2: Analyze Test Failures
```powershell
# Parse .trx files for detailed failure information
$trxFiles = Get-ChildItem "artifacts\TestResults" -Filter "*.trx"

foreach ($trx in $trxFiles) {
    Write-Host "=== Analyzing $($trx.Name) ===" -ForegroundColor Yellow
    
    [xml]$trxContent = Get-Content $trx.FullName
    $failedTests = $trxContent.TestRun.Results.UnitTestResult | Where-Object { $_.outcome -eq "Failed" }
    
    if ($failedTests) {
        Write-Host "Failed tests in $($trx.BaseName):" -ForegroundColor Red
        foreach ($test in $failedTests) {
            Write-Host "  - $($test.testName)" -ForegroundColor Red
            Write-Host "    $($test.Output.ErrorInfo.Message)" -ForegroundColor Yellow
        }
    }
}
```

---

## Complete Automation Script

Save this as `run-ci-simulation.ps1`:

```powershell
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
```

**Usage:**
```powershell
.\run-ci-simulation.ps1
```

---

## Success Checklist

After running the automation:

- [ ] `build-summary.json` shows `Success: true`
- [ ] `sqlserver-summary.json` shows 28 passed, 0 failed
- [ ] `sqlite-summary.json` shows 28 passed, 0 failed
- [ ] `test-summary.json` shows `OverallSuccess: true`
- [ ] No errors in `build-errors.log`
- [ ] All `.trx` files show 0 failures

---

## Output Files Reference

| File | Purpose | Check For |
|------|---------|-----------|
| `restore-output.log` | Dependency restoration | "Restore complete" |
| `build-output.log` | Full build log | Exit code, duration |
| `build-errors.log` | Build errors only | Should be empty |
| `build-warnings.log` | Build warnings only | Should be empty |
| `build-summary.json` | Build metrics | `Success: true` |
| `sqlserver-tests.log` | SQL Server test output | Test pass/fail counts |
| `sqlserver-summary.json` | SQL Server metrics | `Passed: 28, Failed: 0` |
| `sqlite-tests.log` | SQLite test output | Test pass/fail counts |
| `sqlite-summary.json` | SQLite metrics | `Passed: 28, Failed: 0` |
| `test-summary.json` | Combined report | `OverallSuccess: true` |
| `*.trx` | XML test results | For CI integration |
