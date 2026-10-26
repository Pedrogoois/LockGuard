#!/bin/bash
set -euo pipefail

# Usa as Command Line Tools (não exige aceitar a licença do Xcode).
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
SWIFT=/Library/Developer/CommandLineTools/usr/bin/swift

cd "$(dirname "$0")"

echo "==> A compilar (release)…"
"$SWIFT" build -c release

APP="LockGuard.app"
echo "==> A criar o bundle ${APP} ..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"
cp ".build/release/LockGuard" "${APP}/Contents/MacOS/LockGuard"
cp "Info.plist" "${APP}/Contents/Info.plist"

echo "==> A assinar (ad-hoc, para manter a identidade das permissoes) ..."
codesign --force --deep --sign - "${APP}"

echo "==> Pronto: $(pwd)/${APP}"
