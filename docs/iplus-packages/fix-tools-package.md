# Popravak generiranja `iPlus.EntityFrameworkCore.Tools` paketa

Ovaj dokument opisuje korake poduzete da se omogući ispravno generiranje `iPlus.EntityFrameworkCore.Tools` paketa koji je nedostajao u `artifacts` folderu.

## Problem
Paket `EFCore.Tools` se nije ispravno generirao s prefiksom `iPlus` jer ovaj projekt koristi prilagođenu `.nuspec` datoteku (`src\EFCore.Tools\EFCore.Tools.nuspec`) za pakiranje, umjesto standardnog MSBuild procesa. U toj `.nuspec` datoteci bila je **hardkodirana** zavisnost na `Microsoft.EntityFrameworkCore.Design`.

## Rješenje

### 1. Izmjena `.nuspec` datoteke
Lokacija: `src\EFCore.Tools\EFCore.Tools.nuspec`

Izmijenili smo hardkodirani ID paketa u varijablu `$DesignPackageId$` koju možemo kontrolirati iz projekta.

**Stari kod:**
```xml
<dependency id="Microsoft.EntityFrameworkCore.Design" version="$Version$" />
```

**Novi kod:**
```xml
<dependency id="$DesignPackageId$" version="$Version$" />
```

### 2. Izmjena projekta `.csproj`
Lokacija: `src\EFCore.Tools\EFCore.Tools.csproj`

U `SetPackageProperties` targetu dodali smo logiku koja postavlja vrijednost varijable `DesignPackageId` ovisno o tome koristimo li `UseIPlusPackages` switch.

**Dodani kod:**
```xml
  <Target Name="SetPackageProperties" BeforeTargets="InitializeStandardNuspecProperties" DependsOnTargets="Build">
    <PropertyGroup>
      <!-- Logika za odabir ispravnog imena zavisnog paketa -->
      <DesignPackageId Condition="'$(UseIPlusPackages)' == 'true'">$(PackageIdPrefix).EntityFrameworkCore.Design</DesignPackageId>
      <DesignPackageId Condition="'$(UseIPlusPackages)' != 'true'">Microsoft.EntityFrameworkCore.Design</DesignPackageId>
    </PropertyGroup>
    <ItemGroup>
      <!-- Postojeća svojstva -->
      <NuspecProperty Include="configuration=$(Configuration)" />
      <NuspecProperty Include="intermediateOutputPath=$(IntermediateOutputPath)" />
      
      <!-- Novo svojstvo koje prosljeđujemo u .nuspec -->
      <NuspecProperty Include="DesignPackageId=$(DesignPackageId)" />
    </ItemGroup>
  </Target>
```

### 3. Generiranje paketa
Paket se sada mora eksplicitno generirati ako nije prošao u skupnom buildanju (ili ako samo želite taj paket):

```powershell
dotnet pack src/EFCore.Tools/EFCore.Tools.csproj -c Release -p:UseIPlusPackages=true
```

## Rezultat
Nakon ovih izmjena, u folderu `artifacts\packages\Release\Shipping` pojavljuje se:
- `iPlus.EntityFrameworkCore.Tools.9.0.7.nupkg`
- Unutar njega, dependency je ispravno postavljen na `iPlus.EntityFrameworkCore.Design`.
