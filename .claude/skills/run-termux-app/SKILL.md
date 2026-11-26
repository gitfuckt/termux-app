---
name: run-termux-app
description: Build, install, launch, drive and screenshot the Termux Android app (termux-app) as a debuggable build — CI-built APK installed side-by-side as com.termux.dbg, driven on-device via a Shizuku su wrapper. Use to run, start, test, debug, screenshot or poke a change in termux-app.
---

# run-termux-app

termux-app is an Android APK. There is no JDK/SDK on the dev box (a phone running
Termux), so **GitHub Actions builds it** (`.github/workflows/debug_build.yml` builds
`debug` = `DEBUGGABLE` APKs on every push to `master` or `github-releases/**`), and
`.claude/skills/run-termux-app/driver.sh` downloads, installs and drives it on the phone
through a Shizuku-backed `su` (uid 2000 "shell": `pm`, `am`, `input`, `screencap`,
`run-as`). The app is shown on the phone's **virtual display** so it never steals the
user's screen. All paths are relative to the repo root. Run the driver with `bash`.

## Prerequisites (verified on Termux, Android SDK 37, Galaxy foldable)
- `gh` logged in with `repo,workflow` scopes (`gh auth status`). Inside Claude Code `gh auth login`
  hangs (no TTY) — log in from a normal Termux session.
- Shizuku running and `su` on PATH that wraps `rish` and returns real exit codes
  (`su -c 'exit 9'; echo $?` → `9`). Without it the driver falls back to `adb shell`.
- Fork: Actions are disabled on new forks; enable once:
  ```bash
  gh api -X PUT repos/<owner>/termux-app/actions/permissions -F enabled=true -f allowed_actions=all
  gh api -X PUT repos/<owner>/termux-app/actions/workflows/debug_build.yml/enable
  ```

## Build (CI)
The stock debug APK is `com.termux` signed with the GitHub test key — it cannot install
over a Play/F-Droid/Galaxy Store Termux (different signature) without uninstalling it,
which wipes `$HOME` and kills the session you are working in. So build a renamed copy:
```bash
git checkout -b github-releases/sbs
bash .claude/skills/run-termux-app/rename-package.sh          # -> com.termux.dbg, label "Termux Dbg"
git commit -qam "Build as com.termux.dbg (side-by-side debug install)"
git push -u origin github-releases/sbs                         # triggers the Build workflow (~3 min)
gh run list -b github-releases/sbs -L 1
```
For later changes: commit on that branch (re-run the rename script after merging/rebasing)
and push. `rename-package.sh` is idempotent.

## Run (agent path)
```bash
D=.claude/skills/run-termux-app/driver.sh
bash $D fetch            # newest successful run on github-releases/sbs -> $TMPDIR/termux-app-run/app.apk (slow: ~38 MB, minutes)
bash $D install          # "Success"
bash $D info             # pkgFlags=[ DEBUGGABLE ... ]
bash $D failsafe         # fresh failsafe session (/system/bin/sh) on the virtual display
bash $D cmd 'echo DRIVER_OK $(id -u); getprop ro.build.version.sdk'
bash $D ss driver-check  # -> $TMPDIR/termux-app-run/driver-check.png  (Read it to look)
bash $D runas id         # runs as the app uid: only possible because the build is debuggable
bash $D log 40           # app-process logcat
bash $D ui               # view tree of the focused window: text|desc|resource-id|bounds
bash $D launch           # normal launch (login shell — fails, see Gotchas)
bash $D stop             # / uninstall
```
Other: `tap X Y`, `swipe ...`, `key KEYCODE_*`, `text STR`, `displays`, `sh CMD`. Coordinates are
in the target display's pixels (virtual display here: 960x1066). `DISP=0` targets the real screen.

## Run (human path)
Open "Termux Dbg" from the launcher. It shows the login error below; long-press
"New session" in the drawer for a failsafe shell.

## Test
Unit tests run in CI (`run_tests.yml`); there is no local JDK, so not run here.

## Gotchas
- **The renamed app's normal shell cannot start**: `exec("/data/data/com.termux.dbg/files/usr/bin/login"): Permission denied`.
  Bootstrap binaries have `/data/data/com.termux/...` compiled in (shebangs, RUNPATH), which the
  dbg uid cannot read. App code, UI, sessions, settings, failsafe shell and `run-as` all work; for
  testing package-dependent behaviour you need the real `com.termux` package (uninstall Store Termux first).
- **`pm install` can't read `/sdcard`** (`System server has no access to read file context u:object_r:fuse:s0`).
  The driver copies the APK to `/data/local/tmp` from the shell uid first (Termux can't write there).
- **Launching on display 0 fights the user**: the activity draws, the user's keystrokes land in it,
  then it is backgrounded/destroyed (Samsung freezer) before the screenshot. Use the virtual display (default).
- **Display ids differ per tool**: `am`/`input` take the logical id (6), `screencap -d` takes the
  SurfaceFlinger id (19-digit). Display 1 on foldables is the cover screen — launching there when it's
  OFF gives `SecurityException ... launchDisplayId=1`. The driver picks the first non-"Built-in Screen" display.
- `uiautomator dump --display N` ignores the flag; it dumps the focused window (was the dbg app).
- Raw `rish -c` always exits 0 and resets cwd/env; use the `su` wrapper.
- Termux has no `/usr/bin/env` in non-termux-exec shells: call `bash driver.sh`, not `./driver.sh`.
- `gh run download` of the 38 MB artifact takes several minutes on mobile data; don't start two (fetch `rm -rf`s `dl/`).

## Troubleshooting
- `no successful Build run on <branch>` → push to `github-releases/**` and wait for `gh run list` = success.
- `Waiting for Shizuku authorization...` then nothing → Shizuku not running/authorized; open the Shizuku app.
- `INSTALL_FAILED_UPDATE_INCOMPATIBLE` would mean installing an un-renamed `com.termux` APK — use the `sbs` build.
