#!/usr/bin/env bash
# Rename the app's package so a debug build installs side-by-side with an
# existing com.termux (Play/F-Droid/Galaxy Store) install, which is signed with
# a different key. Run anywhere in the repo. Idempotent.
#   usage: rename-package.sh [new.package.name]   (default: com.termux.dbg)
set -euo pipefail
PKG="${1:-com.termux.dbg}"
cd "$(git rev-parse --show-toplevel)"

# applicationId + manifest placeholder (sharedUserId, provider authorities).
# `namespace "com.termux"` stays: it is the R/BuildConfig Java package.
sed -i "s/manifestPlaceholders.TERMUX_PACKAGE_NAME = \"[^\"]*\"/manifestPlaceholders.TERMUX_PACKAGE_NAME = \"$PKG\"/" app/build.gradle
sed -i '/^\s*applicationId "/d' app/build.gradle
sed -i "s/^\(\s*\)versionCode \([0-9]*\)$/\1applicationId \"$PKG\"\n\1versionCode \2/" app/build.gradle

sed -i "s/String TERMUX_PACKAGE_NAME = \"[^\"]*\";/String TERMUX_PACKAGE_NAME = \"$PKG\";/" \
  termux-shared/src/main/java/com/termux/shared/termux/TermuxConstants.java
for f in app/src/main/res/values/strings.xml termux-shared/src/main/res/values/strings.xml; do
  sed -i "s/<!ENTITY TERMUX_PACKAGE_NAME \"[^\"]*\">/<!ENTITY TERMUX_PACKAGE_NAME \"$PKG\">/" "$f"
done
# Distinct launcher label so the two icons can be told apart.
sed -i 's|<string name="application_name">[^<]*</string>|<string name="application_name">Termux Dbg</string>|' \
  app/src/main/res/values/strings.xml

git --no-pager diff --stat -- app termux-shared
