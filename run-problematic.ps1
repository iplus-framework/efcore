# Clean everything (including NuGet cache for this repo)
Remove-Item -Recurse -Force .\artifacts
Remove-Item -Recurse -Force .\test\**\bin -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .\test\**\obj -ErrorAction SilentlyContinue

# Fresh restore
.\restore.cmd

# Reactivate
. .\activate.ps1

# Clean build
.\build.cmd -c Release

# Try running a problematic test
dotnet test .\test\EFCore.Proxies.Tests\EFCore.Proxies.Tests.csproj -c Release --no-build