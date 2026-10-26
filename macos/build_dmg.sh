#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# Garante que a app existe.
if [ ! -d "LockGuard.app" ]; then
    echo "==> LockGuard.app nao encontrada, a compilar primeiro..."
    ./build_app.sh
fi

STAGE="dmg_stage"
OUTDIR="../installers"
DMG="${OUTDIR}/LockGuard-Mac.dmg"

mkdir -p "${OUTDIR}"

echo "==> A preparar conteudo do .dmg..."
rm -rf "${STAGE}" "${DMG}"
mkdir -p "${STAGE}"
cp -R "LockGuard.app" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

echo "==> A criar ${DMG}..."
hdiutil create -volname "LockGuard" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}"

rm -rf "${STAGE}"
echo "==> Pronto: $(cd "${OUTDIR}" && pwd)/LockGuard-Mac.dmg"
