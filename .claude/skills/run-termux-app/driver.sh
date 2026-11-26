#!/usr/bin/env bash
# Drive a termux-app debug build on the Android device this runs on (from inside
# Termux, through a Shizuku-backed `su`) or on an `adb` device. One subcommand per call.
# Run as `bash driver.sh ...` (Termux has no /usr/bin/env unless termux-exec is loaded).
#
#   fetch [branch]        newest successful CI arm64 apt-android-7 APK for branch
#                         (default github-releases/sbs) -> $OUT/app.apk
#   install [apk]         pm install (default $OUT/app.apk)
#   launch                start TermuxActivity on display $DISP (wait for it)
#   failsafe              force-stop, then start a failsafe session (/system/bin/sh)
#   ss [name]             screenshot display $DISP -> $OUT/<name>.png (prints path)
#   ui                    uiautomator dump of the focused window: text|desc|id|bounds per node
#   tap X Y | swipe X1 Y1 X2 Y2 [ms] | key KEYCODE | text STR | cmd STR (text + Enter)
#   runas CMD...          run CMD as the app uid (works only because the build is debuggable)
#   log [N]               last N logcat lines of the app process
#   info                  version, flags (DEBUGGABLE), code path, pid
#   displays              logical + SurfaceFlinger display ids
#   stop | uninstall | sh CMD...
#
# Env: PKG=com.termux.dbg  OUT=$TMPDIR/termux-app-run  REPO=<gh repo of this checkout>
#      DISP=<logical display>  default: the first virtual display if one exists (off-screen,
#           does not disturb the phone user), else 0. Set DISP=0 to use the real screen.
#      SFDISP=<SurfaceFlinger id for screencap>  derived from DISP.
#      SU=su  (Shizuku su wrapper or real root)  else falls back to `adb shell`.
set -euo pipefail
PKG="${PKG:-com.termux.dbg}"
OUT="${OUT:-${TMPDIR:-/tmp}/termux-app-run}"
STAGE=/sdcard/Download/termux-app-run   # readable by the shell uid and by Termux
ACT="$PKG/com.termux.app.TermuxActivity"
mkdir -p "$OUT"

dsh() { # run a command string in the device shell (uid 2000 via Shizuku, or root)
  if [ -n "${SU:-}" ] || command -v su >/dev/null; then "${SU:-su}" -c "$1"; else adb shell "$1"; fi
}
disp() { # logical display id
  if [ -z "${DISP:-}" ]; then
    # first non-"Built-in Screen" logical display (a virtual one; 1 on foldables is the cover screen)
    DISP=$(dsh 'dumpsys display' | grep -oE 'DisplayInfo\{"[^"]*", displayId [0-9]+' | grep -v '"Built-in Screen"' \
           | sed -E 's/.*displayId //' | head -1 || true)
    DISP=${DISP:-0}
  fi
  echo "$DISP"
}
sfdisp() { # SurfaceFlinger display id for screencap
  if [ -z "${SFDISP:-}" ]; then
    local ids; ids=$(dsh 'dumpsys SurfaceFlinger --display-id')
    if [ "$(disp)" = 0 ]; then SFDISP=$(echo "$ids" | sed -n '1s/^Display \([0-9]*\).*/\1/p')
    else SFDISP=$(echo "$ids" | grep 'Virtual display' | head -1 | sed 's/^Display \([0-9]*\).*/\1/'); fi
  fi
  echo "$SFDISP"
}

c="${1:-help}"; shift || true
case "$c" in
  fetch)
    br="${1:-github-releases/sbs}"; repo="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
    id=$(gh run list -R "$repo" -b "$br" -w Build -s success -L 1 --json databaseId -q '.[0].databaseId')
    [ -n "$id" ] || { echo "no successful Build run on $br" >&2; exit 1; }
    name=$(gh api "repos/$repo/actions/runs/$id/artifacts" -q '.artifacts[].name' | grep 'apt-android-7-github-debug_arm64-v8a$')
    rm -rf "$OUT/dl" && gh run download "$id" -R "$repo" -n "$name" -D "$OUT/dl"
    cp "$OUT"/dl/*.apk "$OUT/app.apk" && echo "run $id -> $OUT/app.apk ($(basename "$OUT"/dl/*.apk))" ;;
  install)
    apk="${1:-$OUT/app.apk}"; mkdir -p "$STAGE"; cp "$apk" "$STAGE/app.apk"
    # system_server can't read /sdcard (FUSE); hop through /data/local/tmp (Termux can't write there).
    dsh "cp $STAGE/app.apk /data/local/tmp/termux-app-run.apk && pm install --user 0 -r -t /data/local/tmp/termux-app-run.apk; rc=\$?; rm -f /data/local/tmp/termux-app-run.apk; exit \$rc" ;;
  launch)   dsh "am start -W --user 0 --display $(disp) -n $ACT" ;;
  failsafe) dsh "am force-stop --user 0 $PKG; am start -W --user 0 --display $(disp) -n $ACT --ez $PKG.app.failsafe_session true" ;;
  ss)
    n="${1:-ss-$(date +%H%M%S)}"; mkdir -p "$STAGE"
    dsh "screencap -d $(sfdisp) -p $STAGE/$n.png"; cp "$STAGE/$n.png" "$OUT/$n.png"; echo "$OUT/$n.png" ;;
  ui)
    mkdir -p "$STAGE"; dsh "uiautomator dump $STAGE/ui.xml >/dev/null"; cp "$STAGE/ui.xml" "$OUT/ui.xml"
    grep -o '<node [^>]*>' "$OUT/ui.xml" | sed -E 's/.*text="([^"]*)".*resource-id="([^"]*)".*content-desc="([^"]*)".*bounds="([^"]*)".*/\1|\3|\2|\4/' | grep -v '^|||' || true ;;
  tap)   dsh "input -d $(disp) tap $1 $2" ;;
  swipe) dsh "input -d $(disp) swipe $1 $2 $3 $4 ${5:-300}" ;;
  key)   dsh "input -d $(disp) keyevent $1" ;;
  text)  t=$(printf %s "$*" | sed "s/ /%s/g; s/'/'\\\\''/g"); dsh "input -d $(disp) text '$t'" ;;
  cmd)   bash "$0" text "$*"; bash "$0" key KEYCODE_ENTER ;;
  runas) dsh "run-as $PKG $*" ;;
  log)   pid=$(dsh "pidof $PKG" || true); dsh "logcat -d -v brief ${pid:+--pid=$pid} | tail -n ${1:-60}" ;;
  info)  dsh "dumpsys package $PKG | grep -E 'versionName|pkgFlags|codePath' | head -3; echo pid=\$(pidof $PKG)" ;;
  displays) dsh "dumpsys display | grep -E 'mDisplayId=|mState=' | sort -u; dumpsys SurfaceFlinger --display-id" ;;
  stop)  dsh "am force-stop --user 0 $PKG" ;;
  uninstall) dsh "pm uninstall --user 0 $PKG" ;;
  sh)    dsh "$*" ;;
  *) sed -n '2,26p' "$0"; exit 1 ;;
esac
