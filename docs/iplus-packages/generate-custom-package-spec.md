# Generating Custom NuGet Packages (iPlus)

This document explains how to generate NuGet packages with the `iPlus` prefix instead of `Microsoft`, using build properties and without editing individual `.csproj` files.

## Goal

Generate packages such as `iPlus.EntityFrameworkCore.SqlServer` from the same source code that normally produces `Microsoft.EntityFrameworkCore.SqlServer`.

The mechanism is opt-in and controlled through `UseIPlusPackages=true`, so the default development/test workflow remains unchanged.

## Implementation Summary

The implementation is centralized in the repository root files:

- `Directory.Build.props`
- `Directory.Build.targets`

### 1. `Directory.Build.props`

Adds properties to control package renaming:

- `UseIPlusPackages`: Enables iPlus package behavior (default: `false`)
- `PackageIdPrefix`: Prefix used for package names (`iPlus`)

When `UseIPlusPackages=true`, package metadata is also overridden (for example, `Authors`, `Company`, `Product`, `PackageProjectUrl`, and `PackageTags`).

```xml
<PropertyGroup>
    <UseIPlusPackages Condition="'$(UseIPlusPackages)' == ''">false</UseIPlusPackages>
    <PackageIdPrefix>iPlus</PackageIdPrefix>
</PropertyGroup>
```

### 2. `Directory.Build.targets`

When `UseIPlusPackages=true`, package IDs are rewritten as follows:

- `Microsoft.*` -> `iPlus.*`
- `EFCore` -> `iPlus.EntityFrameworkCore`
- `EFCore.*` -> `iPlus.EntityFrameworkCore.*`

It also updates packed `.props` and `.targets` file names in `build` and `buildTransitive` folders to match the rewritten `PackageId`. This avoids packaging inconsistencies such as `NU5129`.

```xml
<PropertyGroup Condition="'$(UseIPlusPackages)' == 'true'">
    <PackageId Condition="$(MSBuildProjectName.StartsWith('Microsoft.'))">$(MSBuildProjectName.Replace('Microsoft.', '$(PackageIdPrefix).'))</PackageId>
    <PackageId Condition="'$(MSBuildProjectName)' == 'EFCore'">$(PackageIdPrefix).EntityFrameworkCore</PackageId>
    <PackageId Condition="$(MSBuildProjectName.StartsWith('EFCore.'))">$(MSBuildProjectName.Replace('EFCore.', '$(PackageIdPrefix).EntityFrameworkCore.'))</PackageId>
</PropertyGroup>

<ItemGroup Condition="'$(UseIPlusPackages)' == 'true'">
    <None Update="buildTransitive\**\$(AssemblyName).props">
        <PackagePath>buildTransitive\%(RecursiveDir)$(PackageId).props</PackagePath>
    </None>
    <None Update="buildTransitive\**\$(AssemblyName).targets">
        <PackagePath>buildTransitive\%(RecursiveDir)$(PackageId).targets</PackagePath>
    </None>
    <None Update="build\**\$(AssemblyName).props">
        <PackagePath>build\%(RecursiveDir)$(PackageId).props</PackagePath>
    </None>
    <None Update="build\**\$(AssemblyName).targets">
        <PackagePath>build\%(RecursiveDir)$(PackageId).targets</PackagePath>
    </None>
</ItemGroup>
```

## Usage

### Prerequisites

Before building/packing in this repository:

```powershell
.\restore.cmd
. .\activate.ps1
```

### Standard build (Microsoft packages)

Default mode used for regular development and CI:

```cmd
build.cmd
```

### Generate iPlus packages

Enable iPlus naming by setting `UseIPlusPackages=true`.

For the full solution:

```cmd
dotnet pack EFCore.sln -c Release -p:UseIPlusPackages=true
```

For a specific project:

```cmd
dotnet pack src\Microsoft.Data.Sqlite\Microsoft.Data.Sqlite.csproj -c Release -p:UseIPlusPackages=true
```

Packages are generated under:

`artifacts\packages\Release\Shipping\`

Examples:

- `iPlus.EntityFrameworkCore.10.0.0-dev.nupkg`
- `iPlus.EntityFrameworkCore.SqlServer.10.0.0-dev.nupkg`
- `iPlus.Data.Sqlite.10.0.0-dev.nupkg`

## Known Issue: Test-project build conflicts during full-solution pack

When packing `EFCore.sln`, some test projects may fail with type-conflict errors (for example `CS0433` for `DbContextOptions`) because they can end up seeing both local and external EF Core assemblies with different versions.

If your goal is only to produce runtime iPlus packages, this failure can happen after many target packages are already produced. Verify output in:

`artifacts\packages\Release\Shipping\`

## Generating Microsoft and iPlus packages

Both package sets cannot be produced in one MSBuild evaluation because `UseIPlusPackages` changes `PackageId` during evaluation.

Run two separate pack commands:

1. Generate Microsoft packages:

     ```cmd
     dotnet pack -c Release
     ```

2. Generate iPlus packages:

     ```cmd
     dotnet pack -c Release -p:UseIPlusPackages=true
     ```

The outputs can coexist in the same folder because filenames differ.

## Generate iPlus packages without `-dev` suffix

To produce release-style version suffix behavior, set `StabilizePackageVersion=true`.

```cmd
dotnet pack -c Release -p:UseIPlusPackages=true -p:StabilizePackageVersion=true
dotnet pack -c Release -p:UseIPlusPackages=true -p:StabilizePackageVersion=true
```

Property summary:

- `UseIPlusPackages`: Rewrites package IDs to the `iPlus` prefix.
- `StabilizePackageVersion`: Uses release-style package versioning (no `-dev` suffix for shipping package versions).