# Generiranje prilagođenih NuGet paketa (iPlus)

Ovaj dokument opisuje implementaciju generiranja NuGet paketa s prefiksom `iPlus` umjesto `Microsoft`, uz minimalne izmjene izvornog koda.

## Cilj
Omogućiti kreiranje paketa poput `iPlus.EntityFrameworkCore.SqlServer` iz istog source koda koji generira `Microsoft.EntityFrameworkCore.SqlServer`, koristeći switch pri buildanju. Ovo je odvojeno od standardnog build procesa kako se ne bi narušile ovisnosti u testovima.

## Implementacija

Promjene su napravljene isključivo u `Directory.Build.props` i `Directory.Build.targets` datotekama u korijenu repozitorija, što omogućuje globalnu primjenu bez mijenjanja stotina `.csproj` datoteka.

### 1. Directory.Build.props
Dodane su varijable za kontrolu procesa:
- `UseIPlusPackages`: Switch koji aktivira preimenovanje (Default: `false` kako ne bi ometalo standardni build i testove).
- `PackageIdPrefix`: Definira novi prefiks (Postavljeno na: `iPlus`).

```xml
<PropertyGroup>
  ...
  <UseIPlusPackages Condition="'$(UseIPlusPackages)' == ''">false</UseIPlusPackages>
  <PackageIdPrefix>iPlus</PackageIdPrefix>
</PropertyGroup>
```

### 2. Directory.Build.targets
Dodana je logika koja se izvršava na kraju učitavanja projekta:

1.  **Preimenovanje PackageId-a**: 
    - Mijenja `Microsoft.*` u `iPlus.*`.
    - Mijenja `EFCore` u `iPlus.EntityFrameworkCore`.
    - Mijenja `EFCore.*` u `iPlus.EntityFrameworkCore.*`.

2.  **Popravak unutarnje strukture paketa (Build Transitive)**: 
    - Neki paketi (npr. `EFCore`, `EFCore.Design`) sadrže `.props` i `.targets` datoteke u `build` folderima koje moraju imati isto ime kao i paket.
    - Logika automatski preimenuje te datoteke pri pakiranju (npr. `Microsoft.EntityFrameworkCore.props` postaje `iPlus.EntityFrameworkCore.props` unutar paketa). Ovo rješava `NU5129` grešku.

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
    <!-- ... slično i za ostale .targets i build/ folder ... -->
</ItemGroup>
```

## Upute za korištenje

### Standardni Build (Microsoft paketi)
Ovo je zadani način rada. Koristi se za razvoj, testiranje i CI koji očekuje standardne nazive.

```cmd
build.cmd
# ili
dotnet build
```

### Generiranje iPlus paketa
Za kreiranje paketa s `iPlus` prefiksom potrebno je postaviti `UseIPlusPackages=true`.

**Za sve pakete:**
Možete pokrenuti pack na razini solutiona ili root foldera (napomena: ovo može potrajati i buildati testove ako nije specificirano drugačije).

```cmd
dotnet pack -c Release -p:UseIPlusPackages=true
```

**Za specifičan projekt:**
```cmd
dotnet pack src\Microsoft.Data.Sqlite\Microsoft.Data.Sqlite.csproj -c Release -p:UseIPlusPackages=true
```

Paketi će se generirati u mapi: `artifacts\packages\Release\Shipping\`

**Primjeri generiranih paketa:**
- `iPlus.EntityFrameworkCore.10.0.0-dev.nupkg`
- `iPlus.EntityFrameworkCore.SqlServer.10.0.0-dev.nupkg`
- `iPlus.Data.Sqlite.10.0.0-dev.nupkg`

## Problemi i rješenja

### Greška u testnim projektima (EFCore.AspNet.Specification.Tests)

Prilikom pokretanja `dotnet pack` na razini cijelog rješenja (`EFCore.sln`), može doći do greške pri izgradnji testnih projekata kao što je `EFCore.AspNet.Specification.Tests`.

**Greška:**
`error CS0433: The type 'DbContextOptions' exists in both 'Microsoft.EntityFrameworkCore, Version=42.42.42.42...' and 'Microsoft.EntityFrameworkCore, Version=9.0.5.0...'`

**Uzrok:**
Ovaj testni projekt referencira lokalni projekt `EFCore` (koji je za testove i dalje "Microsoft.EntityFrameworkCore" assembly, ali druga verzija) i istovremeno ovisi o NuGet paketu (npr. `Microsoft.AspNetCore.Identity.EntityFrameworkCore`) koji povlači objavljenu verziju EF Core-a. Zbog razlike u verzijama dolazi do konflikta tipova.

**Rješenje:**
Ovu grešku možete **ignorirati** ako su vam potrebni samo glavni runtime paketi (`iPlus.EntityFrameworkCore`, `iPlus.EntityFrameworkCore.SqlServer`, itd.). Ti paketi se uspješno generiraju *prije* nego što build proces dođe do testnih projekata i sruši se. Provjerite mapu `artifacts\packages\Release\Shipping\` - paketi su tamo.

### Generiranje originalnih (Microsoft) i iPlus paketa istovremeno

Nije moguće generirati oba seta paketa (Microsoft.* i iPlus.*) u jednoj naredbi jer se projekt mora evaluirati s jednim `PackageId`-jem.

Ako želite oba, pokrenite naredbu dvaput:
1.  `dotnet pack -c Release` (za Microsoft pakete)
2.  `dotnet pack -c Release -p:UseIPlusPackages=true` (za iPlus pakete - ignorirajte greške na testovima)

