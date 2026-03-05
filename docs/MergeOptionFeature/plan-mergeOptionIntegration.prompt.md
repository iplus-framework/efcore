# Plan: MergeOption Feature Integration

The MergeOption feature is functionally complete but needs test restructuring, code quality fixes, and additional coverage before being ready for main branch integration. The core issue is that all tests are SQL Server-specific and need to be refactored into provider-agnostic specification tests with SQL baseline validation.

**Key Decisions from Review:**
- Move tests from [test/EFCore.SqlServer.FunctionalTests/MergeOptionFeature/](test/EFCore.SqlServer.FunctionalTests/MergeOptionFeature/) to [test/EFCore.Specification.Tests/](test/EFCore.Specification.Tests/)
- Use transactions instead of cleanup patterns for test isolation
- Add EntityEntry overloads for Reload/ReloadAsync with MergeOption
- Fix string-based expression validation to use proper visitor pattern
- Target `main` branch (rebase required from current `release/9.0`)

**Steps**

1. **Fix Core Code Quality Issues**
   - Rename `_MergeOption` to `_mergeOption` in [ShapedQueryCompilingExpressionVisitor.cs](src/EFCore/Query/ShapedQueryCompilingExpressionVisitor.cs) (lines 415, 533)
   - Refactor string-based validation in [EntityFrameworkQueryableExtensions.cs](src/EFCore/Extensions/EntityFrameworkQueryableExtensions.cs) `Refresh<T>()` method to use expression tree visitor pattern (similar to `QueryableMethodNormalizingExpressionVisitor`)
   - Ensure all error messages use string resources from CoreStrings (already done based on research)

2. **Add Missing EntityEntry API Surface**
   - Add `Reload(MergeOption mergeOption)` to [EntityEntry.cs](src/EFCore/ChangeTracking/EntityEntry.cs) and `EntityEntry<TEntity>.cs`
   - Add `ReloadAsync(MergeOption mergeOption, CancellationToken cancellationToken = default)` to both entry classes
   - Follow existing `Reload()` pattern but pass mergeOption to internal reload logic
   - Add XML documentation with proper `<see href="https://aka.ms/efcore-docs-*">` links
   - Update [InternalEntityEntry.cs](src/EFCore/ChangeTracking/Internal/InternalEntityEntry.cs) to support MergeOption parameter in existing Reload methods

3. **Create Specification Test Base Class**
   - Create [test/EFCore.Specification.Tests/Query/MergeOptionTestBase.cs](test/EFCore.Specification.Tests/Query/MergeOptionTestBase.cs) following pattern from `LoadTestBase` or similar query test bases
   - Define abstract `FixtureBase : SharedStoreFixtureBase<TContext>` with test model
   - Include test model with: collection/non-collection owned types, complex properties, many-to-many (no explicit join), global filters, shadow properties, computed columns, value converters, primitive collections, table-sharing
   - Implement provider-agnostic test methods for all scenarios (see step 5)
   - Use `AssertSql()` pattern for SQL baseline validation (provider will override)

4. **Implement Provider-Specific Test Classes**
   - Create [test/EFCore.SqlServer.FunctionalTests/Query/MergeOptionSqlServerTest.cs](test/EFCore.SqlServer.FunctionalTests/Query/MergeOptionSqlServerTest.cs) inheriting from `MergeOptionTestBase<MergeOptionSqlServerTest.MergeOptionSqlServerFixture>`
   - Create [test/EFCore.Sqlite.FunctionalTests/Query/MergeOptionSqliteTest.cs](test/EFCore.Sqlite.FunctionalTests/Query/MergeOptionSqliteTest.cs) with corresponding fixture
   - Each fixture specifies `TestStoreFactory` (SqlServerTestStoreFactory.Instance or SqliteTestStoreFactory.Instance)
   - Override `AssertSql` expectations with provider-specific SQL baselines

5. **Port and Consolidate Test Cases**
   - Port tests from existing 9 test files in [MergeOptionFeature/](test/EFCore.SqlServer.FunctionalTests/MergeOptionFeature/) to specification base
   - Replace try/finally cleanup with transaction pattern: `using var transaction = await context.Database.BeginTransactionAsync()`
   - Remove direct database modifications to shared Northwind database
   - Group tests logically: EntityStateTests, QueryOperationTests, IncludeTests, ProxyTests, ErrorConditionTests
   - Fix commented-out owned type tests using `LoadAsync(LoadOptions.ForceIdentityResolution)` pattern
   - Add SQL baseline assertions for each test

6. **Add Missing Test Coverage**
   - **PreserveChanges scenarios**: Test that modified properties are NOT overwritten, only original values updated
   - **Unchanged with mismatched original**: Entity unchanged but original value differs from database
   - **Modified with matching original**: Entity modified but original matches database  
   - **Owned entity replacement**: Track both Added and Deleted states when owned entity replaced
   - **Derived→Base replacement**: Replace derived entity with base entity having same key
   - **Streaming queries**: Non-buffering consumption with `await foreach` or manual `MoveNext()`
   - **Lazy-loading proxies**: Test with loaded and unloaded navigations
   - **Multiple projection**: Same entity projected multiple times with different values
   - **ThenInclude**: Multi-level include testing
   - **Error cases**: Non-tracking query throws `InvalidOperationException`, multiple `Refresh` throws error

7. **Delete Old Test Files**
   - Remove [test/EFCore.SqlServer.FunctionalTests/MergeOptionFeature/](test/EFCore.SqlServer.FunctionalTests/MergeOptionFeature/) directory completely after porting
   - Verify no references remain to old test classes

8. **Update Baselines**
   - Run tests with `$env:EF_TEST_REWRITE_BASELINES = "1"` to generate SQL baselines
   - Review generated baselines for correctness
   - Commit baseline files with test changes

9. **Rebase and Prepare for PR**
   - Rebase branch on latest `main` (currently targeting `release/9.0`)
   - Run `.\restore.cmd` and `. .\activate.ps1` to set up environment
   - Run full test suite: `.\test.cmd` to ensure no regressions
   - Verify builds succeed: `.\build.cmd`
   - Remove any Croatian comments or documentation
   - Ensure all public APIs have proper XML documentation

**Verification**

- `.\build.cmd` succeeds without warnings
- `.\test.cmd` passes all tests including new MergeOption tests
- Run specific test projects:
  - `dotnet test .\test\EFCore.Specification.Tests\EFCore.Specification.Tests.csproj --filter "FullyQualifiedName~MergeOption"`
  - `dotnet test .\test\EFCore.SqlServer.FunctionalTests\EFCore.SqlServer.FunctionalTests.csproj --filter "FullyQualifiedName~MergeOption"`
  - `dotnet test .\test\EFCore.Sqlite.FunctionalTests\EFCore.Sqlite.FunctionalTests.csproj --filter "FullyQualifiedName~MergeOption"`
- SQL baselines generated and look correct
- No test isolation issues (all tests use transactions)
- Code follows .editorconfig rules

**Decisions**

- **Specification tests over provider-specific**: Enables testing across all providers and follows EF Core patterns
- **Transactions over cleanup**: More reliable, prevents CI failures from database state pollution
- **Consolidate 9 test files**: Current structure has excessive duplication; grouping by scenario is more maintainable
- **Add EntityEntry overloads**: Provides consistency with existing Reload API and convenience for common scenarios
- **Expression visitor over string parsing**: More robust and follows EF Core conventions for query analysis
