#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$HOME/.dotnet:$PATH"
export DOTNET_CLI_TELEMETRY_OPTOUT=1

OUTDIR="../installers"
mkdir -p "${OUTDIR}"

echo "==> A compilar o .exe autonomo para Windows (win-x64)..."
dotnet publish -c Release -r win-x64 --self-contained true \
    -p:PublishSingleFile=true \
    -p:IncludeNativeLibrariesForSelfExtract=true \
    -p:EnableCompressionInSingleFile=true \
    -o dist

cp dist/LockGuard.exe "${OUTDIR}/LockGuard-Windows.exe"
echo "==> Pronto: $(cd "${OUTDIR}" && pwd)/LockGuard-Windows.exe"
