#!/bin/sh
set -eu
: "${APELIN_PACKAGE_DIR:?run this through apelin_project_build}"
: "${APELIN_PROJECT_ROOT:?}" "${APELIN_BOOTSTRAP:?}" "${APELIN_ARCHITECTURE:?}"
: "${APELIN_BUILD_ID:?}" "${TMPDIR:?}"
: "${APELIN_PREFIX?}"

cd "${APELIN_PROJECT_ROOT}"

ARCH_ONLY="${APELIN_ARCHITECTURE#iphoneos-}"
BUILD_ID="${APELIN_BUILD_ID}"
INCLUDE="apelin/include"
LIBDIR="apelin/lib/tweak"

stage="$(mktemp -d "${TMPDIR:?}stage.XXXXXX")"
trap 'rm -rf -- "${stage:?}"' EXIT

CFLAGS="-arch ${ARCH_ONLY} -fobjc-arc -DTHEOS_LEAN_AND_MEAN -I${INCLUDE}"
LDFLAGS="-arch ${ARCH_ONLY} -L${LIBDIR} -F${LIBDIR}"

# ── KayokoCore.dylib (SpringBoard tweak) ──────────────────────
echo "== Building KayokoCore.dylib =="
coredir="${stage}/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "${coredir}"

clang \
  Tweak/Core/KayokoCore.m \
  Tweak/Core/Views/KayokoView.m \
  Tweak/Core/Views/KayokoTableView.m \
  Tweak/Core/Views/KayokoTableViewCell.m \
  Tweak/Core/Views/KayokoFavoritesTableView.m \
  Tweak/Core/Views/KayokoHistoryTableView.m \
  Tweak/Core/Views/KayokoPreviewView.m \
  Manager/PasteboardManager.m \
  Manager/PasteboardItem.m \
  Manager/KayokoClipboardExecutor.m \
  Manager/KayokoHistoryStore.m \
  Utils/ImageUtil.m \
  ${CFLAGS} ${LDFLAGS} -DAPELIN_BUILD_ID=\""${BUILD_ID}"\" \
  -framework UIKit -framework CoreGraphics -framework QuartzCore -framework WebKit \
  -lsubstrate -lroothide \
  -dynamiclib \
  -install_name /Library/MobileSubstrate/DynamicLibraries/KayokoCore.dylib \
  -o "${coredir}/KayokoCore.dylib"

ldid -S "${coredir}/KayokoCore.dylib"
cp Tweak/Core/KayokoCore.plist "${coredir}/"

# ── KayokoHelper.dylib (UIKit tweak) ──────────────────────────
echo "== Building KayokoHelper.dylib =="
clang \
  Tweak/Helper/KayokoHelper.m \
  Manager/PasteboardManager.m \
  Manager/PasteboardItem.m \
  Manager/KayokoClipboardExecutor.m \
  Manager/KayokoHistoryStore.m \
  Utils/ImageUtil.m \
  ${CFLAGS} ${LDFLAGS} -DAPELIN_BUILD_ID=\""${BUILD_ID}"\" \
  -framework UIKit -framework CoreGraphics \
  -lsandy -lsubstrate -lroothide \
  -dynamiclib \
  -install_name /Library/MobileSubstrate/DynamicLibraries/KayokoHelper.dylib \
  -o "${coredir}/KayokoHelper.dylib"

ldid -S "${coredir}/KayokoHelper.dylib"
cp Tweak/Helper/KayokoHelper.plist "${coredir}/"

# ── kayokod (daemon) ──────────────────────────────────────────
echo "== Building kayokod =="
libexecdir="${stage}/usr/libexec"
mkdir -p "${libexecdir}"

clang \
  Daemon/KayokoDaemon.m \
  -arch "${ARCH_ONLY}" \
  -framework Foundation \
  -o "${libexecdir}/kayokod"

ldid -SDaemon/entitlements.plist "${libexecdir}/kayokod"

# ── KayokoPreferences (preference bundle) ─────────────────────
echo "== Building KayokoPreferences =="
bundledir="${stage}/Library/PreferenceBundles/KayokoPreferences.bundle"
mkdir -p "${bundledir}"

clang \
  Preferences/Controllers/KayokoRootListController.m \
  Preferences/Controllers/KayokoCreditsListController.m \
  Preferences/Cells/LinkCell.m \
  Preferences/Cells/SingleContactCell.m \
  ${CFLAGS} ${LDFLAGS} \
  -framework UIKit -framework CoreGraphics \
  -framework Preferences \
  -lroothide \
  -bundle \
  -o "${bundledir}/KayokoPreferences"

ldid -S "${bundledir}/KayokoPreferences"
cp Preferences/Resources/Info.plist "${bundledir}/"
cp Preferences/Resources/Root.plist "${bundledir}/"
cp Preferences/Resources/Credits.plist "${bundledir}/"
cp Preferences/Resources/Icon.png "${bundledir}/"
cp Preferences/Resources/Icon@2x.png "${bundledir}/"

# ── Layout files ──────────────────────────────────────────────
mkdir -p "${stage}/Library/LaunchDaemons"
cp layout/Library/LaunchDaemons/codes.aurora.kayokod.plist "${stage}/Library/LaunchDaemons/"

mkdir -p "${stage}/Library/libSandy"
cp layout/Library/libSandy/Kayoko.plist "${stage}/Library/libSandy/"

mkdir -p "${stage}/Library/PreferenceLoader/Preferences"
cp Preferences/layout/Library/PreferenceLoader/Preferences/KayokoPreferences.plist "${stage}/Library/PreferenceLoader/Preferences/"

# ── DEBIAN control + scripts ──────────────────────────────────
mkdir -p "${stage}/DEBIAN"
sed "s/^Architecture: .*/Architecture: ${APELIN_ARCHITECTURE}/" control > "${stage}/DEBIAN/control"
cp layout/DEBIAN/postinst "${stage}/DEBIAN/postinst"
cp layout/DEBIAN/prerm "${stage}/DEBIAN/prerm"
chmod 0755 "${stage}/DEBIAN/postinst" "${stage}/DEBIAN/prerm"

# ── Build .deb ────────────────────────────────────────────────
echo "== Building package =="
dpkg-deb -b --root-owner-group "${stage}" "${APELIN_PACKAGE_DIR}/codes.aurora.kayoko.deb"
echo "== Done =="
