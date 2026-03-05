# MergeOption Feature - Integration Guide

This document provides guidance for integrating the MergeOption feature into the official EF Core repository.

## Table of Contents
1. [Running CI Tests Locally](#1-running-ci-tests-locally)
2. [PR Review Summary](#2-pr-review-summary)
3. [Implementation Analysis](#3-implementation-analysis)
4. [Test Assessment](#4-test-assessment)
5. [Recommendations](#5-recommendations)

---

## 1. Running CI Tests Locally

### Initial Setup

Before running any tests, you must set up the development environment:

```powershell
# 1. Restore dependencies (required first)
.\restore.cmd

# 2. Activate the development environment (sets up correct SDK paths)
. .\activate.ps1
```

These scripts configure:
- `DOTNET_ROOT` - Points to the project's specific .NET SDK
- `DOTNET_MULTILEVEL_LOOKUP` - Prevents SDK version conflicts
- `PATH` - Ensures correct SDK version is used

### Building the Code

```powershell
# Build all projects
.\build.cmd

# Build specific configuration
.\build.cmd -c Release

# Build and create NuGet packages
.\build.cmd -pack
```

### Running Tests

```powershell
# Run ALL tests (same as CI)
.\test.cmd

# Run tests for a specific test project
dotnet test .\test\EFCore.SqlServer.FunctionalTests\EFCore.SqlServer.FunctionalTests.csproj

# Run specific test class
dotnet test .\test\EFCore.SqlServer.FunctionalTests\EFCore.SqlServer.FunctionalTests.csproj --filter "FullyQualifiedName~MergeOptionFeature"

# Run with verbose output
dotnet test .\test\EFCore.SqlServer.FunctionalTests\EFCore.SqlServer.FunctionalTests.csproj --logger "console;verbosity=detailed"
```

### Prerequisites for Tests

1. **SQL Server LocalDb** - Install via Visual Studio ("ASP.NET and web development" workload) or SQL Server Express/Developer Edition

2. **Custom Connection String** (if not using LocalDb):
   ```powershell
   $env:Test__SqlServer__DefaultConnection = "Server=...;Database=...;..."
   ```

3. **Azure Cosmos Emulator** (optional, for Cosmos tests)

### Fixing Test Baselines

If tests fail due to baseline mismatches:
```powershell
$env:EF_TEST_REWRITE_BASELINES = "1"
dotnet test <path-to-test-project>
```

### CI Pipeline Behavior

The Azure Pipelines CI configuration (`azure-pipelines.yml`):
- Triggers on: `main`, `release/*`, `feature/*`, `internal/release/*` branches
- Runs on every PR (`pr: ['*']`)
- Uses Helix for distributed test execution

---

## 2. PR Review Summary

Based on the review at https://github.com/dotnet/efcore/pull/36556

### Required Changes (from @AndriySvyryd)

#### Branch Target
- **Current**: `iplus-framework:release/9.0`
- **Required**: Target `main` branch (rebase needed)

#### Test Structure Requirements

Tests must be **provider-agnostic** and placed in:
```
test\EFCore.Specification.Tests\MergeOptionTestBase.cs
```

Then override for each provider to assert SQL baselines.

#### Test Cases Required

**Entity State Tests:**
- Existing entries in all states
- Unchanged entries with original value ≠ database state  
- Modified entries with original value = database state
- Owned entity replaced (tracked as Added + Deleted)
- Derived entity replaced by base entity with same key

**Query Operation Tests:**
- Different terminating operators: `ToList`, `FirstOrDefault`, etc.
- Streaming (non-buffering) queries consumed one-by-one
- Queries with `Include`, filtered `Include`, and `ThenInclude`
- Projecting related entity in `Select` without `Include`
- Client-evaluated projections with calculated values
- Same entity projected multiple times with different property values

**Special Scenarios:**
- Lazy-loading proxies with loaded/unloaded navigations
- Non-tracking queries should throw `InvalidOperationException`
- Multiple `Refresh` with different values should throw

#### Test Model Requirements

- Collection and non-collection owned types
- Collection and non-collection complex properties
- Many-to-many relationships without explicit join type
- Global query filters
- Shadow and non-shadow properties
- Computed columns
- Value converters
- Primitive collections
- Table-sharing with shared non-key columns

### Code Review Comments

1. **Use transactions instead of cleanup patterns**
   ```csharp
   // Bad
   try { /* test */ }
   finally { /* cleanup SQL */ }
   
   // Good
   using var transaction = await ctx.Database.BeginTransactionAsync();
   // test
   // transaction automatically rolled back on dispose
   ```

2. **Don't catch exceptions in tests** - Let them fail naturally

3. **Naming convention**: `_MergeOption` → `_mergeOption` (private field)

4. **String parsing is fragile** - Use expression tree parsing:
   ```csharp
   // Current (fragile)
   string[] expressionNames = source.Expression.ToString().Split('.');
   
   // Suggested (robust)
   static bool HasNonTrackingOrIgnoreAutoIncludes(Expression expression)
   {
       Expression? current = expression;
       while (current is MethodCallExpression call)
       {
           var method = call.Method;
           if (method.DeclaringType == typeof(EntityFrameworkQueryableExtensions))
           {
               var name = method.Name;
               if (name == nameof(AsNoTracking) || ...)
                   return true;
           }
           current = call.Arguments.Count > 0 ? call.Arguments[0] : null;
       }
       return false;
   }
   ```

5. **Owned properties require special handling**:
   ```csharp
   // ReloadAsync doesn't reload owned properties (see #13890)
   // Use LoadAsync with ForceIdentityResolution
   addresses.LoadAsync(LoadOptions.ForceIdentityResolution);
   ```

6. **Add overloads to EntityEntry**:
   - `Reload(MergeOption)`
   - `ReloadAsync(MergeOption)`
   - `Load(MergeOption)` 
   - `LoadAsync(MergeOption)`

---

## 3. Implementation Analysis

### Core Components

#### MergeOption Enum (`src/EFCore/MergeOption.cs`)
```csharp
public enum MergeOption
{
    AppendOnly = 0,        // Default - only append new entities
    OverwriteChanges = 1,  // Overwrite both current and original values
    PreserveChanges = 2    // Only update original values, keep current
}
```

#### GetEntriesForState Method

**Location**: `src/EFCore/ChangeTracking/ChangeTracker.cs`

Purpose: Fast filtered access to tracked entities by state, avoiding the performance penalty of `ChangeTracker.Entries().Where(...)`.

**Call chain**:
1. `ChangeTracker.GetEntriesForState()` → 
2. `StateManager.GetEntriesForState()` → 
3. `EntityReferenceMap.GetEntriesForState()`

**Internal implementation** (`EntityReferenceMap`):
- Maintains separate dictionaries per state: `_addedReferenceMap`, `_modifiedReferenceMap`, etc.
- Returns entries directly from the appropriate maps
- O(n) where n = entities in requested states (vs O(total) for Entries())

#### Refresh Extension Method

**Location**: `src/EFCore/Extensions/EntityFrameworkQueryableExtensions.cs`

```csharp
public static IQueryable<T> Refresh<T>(this IQueryable<T> source, MergeOption mergeOption)
```

**Behavior**:
- Validates query is not non-tracking
- Validates no conflicting `MergeOption` already applied
- Wraps the expression with a `MethodCallExpression` for `RefreshMethodInfo`
- Processed during query compilation via `QueryCompilationContext.RefreshMergeOption`

### Query Processing

The `RefreshMergeOption` is read in `QueryCompilationContext` and used by `ShapedQueryCompilingExpressionVisitor` to determine how to handle materialized entities:
- `OverwriteChanges`: Updates both current and original property values
- `PreserveChanges`: Only updates original values, preserving local changes

---

## 4. Test Assessment

### Current Test Files in `MergeOptionFeature/`

| File                                                   | Status  | Issues                                         |
| ------------------------------------------------------ | ------- | ---------------------------------------------- |
| `RefreshFromDb_Northwind_SqlServer_Test.cs`            | Active  | Uses Northwind (shared DB), needs transactions |
| `RefreshFromDb_ComplexTypes_SqlServer_Test.cs`         | Partial | 3 tests commented out                          |
| `RefreshFromDb_ComputedColumns_SqlServer_Test.cs`      | Active  | -                                              |
| `RefreshFromDb_GlobalFilters_SqlServer_Test.cs`        | Active  | -                                              |
| `RefreshFromDb_ManyToMany_SqlServer_Test.cs`           | Active  | -                                              |
| `RefreshFromDb_PrimitiveCollections_SqlServer_Test.cs` | Active  | -                                              |
| `RefreshFromDb_ShadowProperties_SqlServer_Test.cs`     | Active  | -                                              |
| `RefreshFromDb_TableSharing_SqlServer_Test.cs`         | Active  | -                                              |
| `RefreshFromDb_ValueConverters_SqlServer_Test.cs`      | Active  | -                                              |

### Test Coverage Analysis

**✅ Covered by current tests:**
- Basic `GetEntriesForState` functionality
- `Refresh` with `MergeOption.OverwriteChanges`
- Many-to-many relationships
- Global query filters  
- Shadow properties
- Computed columns
- Value converters
- Primitive collections
- Table sharing

**❌ Missing or incomplete:**
- `MergeOption.PreserveChanges` scenarios (most tests only use `OverwriteChanges`)
- Unchanged entries with mismatched original values
- Modified entries with matching original values
- Owned entity replacement (Added + Deleted tracking)
- Derived → Base entity replacement
- Non-buffering streaming queries
- Lazy-loading proxy scenarios
- Entity projected multiple times with different values
- `ThenInclude` scenarios
- Non-tracking query error validation
- Multiple `Refresh` error validation

### Identified Issues

1. **Tests are SQL Server specific** - Should be in `EFCore.Specification.Tests` with provider overrides

2. **Tests modify Northwind database** - CI failures because other tests depend on Northwind state

3. **Uses cleanup pattern instead of transactions** - Cleanup in `finally` blocks is unreliable

4. **Commented-out tests indicate blockers**:
   - `Test_CollectionOwnedTypes` - Needs `LoadAsync(LoadOptions.ForceIdentityResolution)`
   - `Test_NonCollectionOwnedTypes` - `ReloadAsync` doesn't reload owned properties
   - `Test_CollectionComplexProperties` - Misidentified as owned collection

5. **Test redundancy** - Many tests follow identical patterns (load, modify DB externally, refresh, assert)

---

## 5. Recommendations

### Immediate Actions

#### 1. Restructure Tests

Create provider-agnostic base class:
```
test/EFCore.Specification.Tests/MergeOptionTestBase.cs
```

With provider implementations:
```
test/EFCore.SqlServer.FunctionalTests/Query/MergeOptionSqlServerTest.cs
test/EFCore.Sqlite.FunctionalTests/Query/MergeOptionSqliteTest.cs
```

#### 2. Fix Database Modification Issues

Use transactions:
```csharp
[Fact]
public async Task Refresh_overwrites_modified_entity()
{
    using var ctx = CreateContext();
    await using var transaction = await ctx.Database.BeginTransactionAsync();
    
    var entity = await ctx.Set<Customer>().FirstAsync();
    var newValue = "Modified by test";
    
    await ctx.Database.ExecuteSqlRawAsync(
        "UPDATE [Customers] SET [Name] = {0} WHERE [Id] = {1}", 
        newValue, entity.Id);
    
    var refreshed = await ctx.Set<Customer>()
        .Where(c => c.Id == entity.Id)
        .Refresh(MergeOption.OverwriteChanges)
        .FirstAsync();
    
    Assert.Equal(newValue, refreshed.Name);
    // Transaction auto-rollback on dispose
}
```

Or use a dedicated test database (not Northwind).

#### 3. Implement Missing Test Cases

Priority checklist:
- [ ] `PreserveChanges` scenarios
- [ ] Owned entity replacement tracking  
- [ ] Non-tracking query exception
- [ ] Multiple `Refresh` exception
- [ ] Lazy-loading proxy tests
- [ ] Streaming query tests

#### 4. Fix Commented-Out Tests

For owned properties:
```csharp
// Instead of ReloadAsync for owned properties
var ownedCollection = ctx.Entry(owner).Collection(o => o.OwnedEntities);
ownedCollection.IsLoaded = false;
await ownedCollection.LoadAsync(LoadOptions.ForceIdentityResolution);
```

#### 5. Code Fixes Required

1. Rename `_MergeOption` to `_mergeOption` in `ShapedQueryCompilingExpressionVisitor.cs`

2. Replace string parsing with expression tree analysis in `Refresh<T>()` method

3. Add `MergeOption` parameter overloads to `EntityEntry`:
   - `Reload(MergeOption mergeOption)`
   - `ReloadAsync(MergeOption mergeOption, CancellationToken cancellationToken = default)`

### Consolidation Suggestions

Current tests have significant overlap. Consider consolidating into:

1. **GetEntriesForStateTests** - Unit tests for the `GetEntriesForState` method
2. **RefreshQueryTests** - Tests for `Refresh()` LINQ extension
3. **MergeOptionBehaviorTests** - Tests for `AppendOnly`, `OverwriteChanges`, `PreserveChanges`
4. **MergeOptionEdgeCaseTests** - Error cases, streaming, projections

### Before Pushing to Official Repository

1. ✅ All tests pass locally (`.\test.cmd`)
2. ✅ Rebased on latest `main`
3. ✅ Tests use transactions (not cleanup)
4. ✅ Tests are provider-agnostic (in Specification.Tests)
5. ✅ No Croatian comments/documentation
6. ✅ Code follows naming conventions
7. ✅ XML documentation for public APIs
8. ✅ String resources in `.resx` for error messages

---

## References

- PR: https://github.com/dotnet/efcore/pull/36556
- Issue #16491: Ability to refresh a context from the database
- Issue #31819: DetectChanges slow in long-term contexts
- Issue #13890: ReloadAsync doesn't reload owned properties
- Fork: https://github.com/iplus-framework/efcore
