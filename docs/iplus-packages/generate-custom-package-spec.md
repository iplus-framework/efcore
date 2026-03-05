# Generating Custom NuGet Packages (iPlus)

This document describes the implementation of generating NuGet packages with the `iPlus` prefix instead of `Microsoft`, with minimal changes to the source code.

## Goal
Enable the creation of packages like `iPlus.EntityFrameworkCore.SqlServer` from the same source code that generates `Microsoft.EntityFrameworkCore.SqlServer`, using a switch during the build. This is separate from the standard build process so as not to disrupt dependencies in tests.

## Implementation

Changes are made exclusively in the `Directory.Build.props` and `Directory.Build.targets` files in the root of the repository, allowing for global application without changing hundreds of `.csproj` files.

### 1. Directory.Build.props
Variables have been added to control the process:
- `UseIPlusPackages`: Switch that activates renaming (Default: `false` so as not to interfere with standard build and tests).
- `PackageIdPrefix`: Defines the new prefix (Set to: `iPlus`).

```xml
<PropertyGroup>
  ...
  <UseIPlusPackages Condition="'$(UseIPlusPackages)' == ''">false</UseIPlusPackages>
  <PackageIdPrefix>iPlus</PackageIdPrefix>
</PropertyGroup>
```

### 2. Directory.Build.targets
Logic has been added that executes at the end of project loading:

1.  **Renaming PackageId**:
    - Changes `Microsoft.*` to `iPlus.*`.
    - Changes `EFCore` to `iPlus.EntityFrameworkCore`.
    - Changes `EFCore.*` to `iPlus.EntityFrameworkCore.*`.

2.  **Fixing Internal Package Structure (Build Transitive)**:
    - Some packages (e.g. `EFCore`, `EFCore.Design`) contain `.props` and `.targets` files in `build` folders that must have the same name as the package.
    - Logic automatically renames these files during packaging (e.g. `Microsoft.EntityFrameworkCore.props` becomes `iPlus.EntityFrameworkCore.props` inside the package). This resolves the `NU5129` error.

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
    <!-- ... similarly for other .targets and build/ folder ... -->
</ItemGroup>
```

## Usage Instructions

### Standard Build (Microsoft Packages)
This is the default mode. Used for development, testing, and CI that expects standard names.

```cmd
build.cmd
# or
dotnet build
```

### Generating iPlus Packages
To create packages with the `iPlus` prefix, you need to set `UseIPlusPackages=true`.

**For all packages:**
You can run pack at the solution or root folder level (note: this may take a while and build tests if not specified otherwise).

```cmd
dotnet pack -c Release -p:UseIPlusPackages=true
```

**For a specific project:**
```cmd
dotnet pack src\Microsoft.Data.Sqlite\Microsoft.Data.Sqlite.csproj -c Release -p:UseIPlusPackages=true
```

Packages will be generated in the folder: `artifacts\packages\Release\Shipping\`

**Examples of generated packages:**
- `iPlus.EntityFrameworkCore.10.0.0-dev.nupkg`
- `iPlus.EntityFrameworkCore.SqlServer.10.0.0-dev.nupkg`
- `iPlus.Data.Sqlite.10.0.0-dev.nupkg`

## Issues and Solutions

### Error in Test Projects (EFCore.AspNet.Specification.Tests)

When running `dotnet pack` on the entire solution (`EFCore.sln`), an error may occur when building test projects such as `EFCore.AspNet.Specification.Tests`.

**Error:**
`error CS0433: The type 'DbContextOptions' exists in both 'Microsoft.EntityFrameworkCore, Version=42.42.42.42...' and 'Microsoft.EntityFrameworkCore, Version=9.0.5.0...'`

**Cause:**
This test project references the local project `EFCore` (which for tests is still the "Microsoft.EntityFrameworkCore" assembly, but a different version) and simultaneously depends on a NuGet package (e.g. `Microsoft.AspNetCore.Identity.EntityFrameworkCore`) that pulls in a published version of EF Core. Due to the version difference, a type conflict occurs.

**Solution:**
You can **ignore** this error if you only need the main runtime packages (`iPlus.EntityFrameworkCore`, `iPlus.EntityFrameworkCore.SqlServer`, etc.). These packages are successfully generated *before* the build process reaches the test projects and crashes. Check the `artifacts\packages\Release\Shipping\` folder - the packages are there.

### Generating Original (Microsoft) and iPlus Packages Simultaneously

Since the generation logic relies on the `UseIPlusPackages` property which changes the `PackageId` at evaluation time, it is not possible to generate both sets of packages in a single MSBuild pass.

To generate both, run the pack command twice sequentially:

1.  **Generate Standard Packages:**
    ```cmd
    dotnet pack -c Release
    ```

2.  **Generate iPlus Packages:**
    ```cmd
    dotnet pack -c Release -p:UseIPlusPackages=true
    ```

The packages will coexist in the output directory because they have different filenames (e.g., `Microsoft.EntityFrameworkCore...nupkg` and `iPlus.EntityFrameworkCore...nupkg`).
