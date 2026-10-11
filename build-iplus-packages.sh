#!/usr/bin/env bash
# Builds the standard project and then generates iPlus NuGet packages.
# Linux equivalent of build-iplus-packages.ps1 (see docs/iplus-packages/generate-custom-package-spec.md).
#
# Usage:
#   ./build-iplus-packages.sh                 # default: UseIPlusPackages=true, stable versions
#   ./build-iplus-packages.sh --keep-dev      # keep the -dev version suffix
#   EXTRA_ARGS are forwarded to build.sh, e.g.:
#   ./build-iplus-packages.sh /p:ArcadeBuildFromSource=true
set -uo pipefail

cd "$(dirname "$0")"

# Use the workspace-shared NuGet cache (same redirect the other V5 repos use).
# MUST be consistent between restore and pack, otherwise package build assets
# (e.g. the GenerateFileFromTemplate task of Microsoft.DotNet.Build.Tasks.Templating)
# are imported from a store the condition doesn't find.
export NUGET_PACKAGES="${NUGET_PACKAGES:-/home/damir/SHARED/Devel/iPlusGit/V5/packages}"

KEEP_DEV=false
EXTRA_ARGS=()
for arg in "$@"; do
    if [[ "$arg" == "--keep-dev" ]]; then
        KEEP_DEV=true
    else
        EXTRA_ARGS+=("$arg")
    fi
done

STABILIZE_ARGS=()
if [[ "$KEEP_DEV" == false ]]; then
    STABILIZE_ARGS=(-p:StabilizePackageVersion=true)
fi

step() {
    echo
    echo "------------------------------------------------------------"
    echo "$1"
    echo "------------------------------------------------------------"
}

# 1. Clean artifacts
step "Step 1: Cleaning previous artifacts..."
if [[ -d artifacts ]]; then
    echo "Removing 'artifacts' directory..."
    rm -rf artifacts
else
    echo "'artifacts' directory not found. Skipping clean."
fi

# 2. Run standard build (restore + build, sets up SDK via eng/common)
step "Step 2: Running standard build (build.sh)..."
./build.sh --build --restore "${EXTRA_ARGS[@]}"
rc=$?
if [[ $rc -ne 0 ]]; then
    echo "ERROR: Standard build failed with exit code $rc." >&2
    exit $rc
fi

# 3. Generate iPlus packages
step "Step 3: Generating iPlus packages (dotnet pack EFCore.sln -p:UseIPlusPackages=true)..."
# Note: packing the full solution may fail on some test projects (e.g. CS0433 type
# conflicts) AFTER the shipping packages have been produced — hence no set -e here.
dotnet pack EFCore.sln -c Release -p:UseIPlusPackages=true "${STABILIZE_ARGS[@]}" "${EXTRA_ARGS[@]}"
pack_rc=$?

# 4. Verify results
step "Verification..."
packageDir="artifacts/packages/Release/Shipping"
if [[ -d "$packageDir" ]]; then
    packages=$(find "$packageDir" -maxdepth 1 -name 'iPlus.*.nupkg' | sort)
    if [[ -n "$packages" ]]; then
        count=$(echo "$packages" | wc -l)
        echo "SUCCESS: Generated $count iPlus packages:"
        echo "$packages" | sed 's/^/ - /'
        echo
        echo "Location: $packageDir"
    else
        echo "WARNING: No packages starting with 'iPlus.' were found in $packageDir." >&2
    fi
else
    echo "WARNING: Package directory not found: $packageDir" >&2
fi

echo
echo "Done."
exit $pack_rc
