# Builds and releases

Two GitHub Actions workflows live in `.github/workflows/`:

| Workflow | Runs on | Does |
|---|---|---|
| `ci.yml` | every push to `main` and every pull request | analyzes the code and runs all tests |
| `release.yml` | every pushed tag that starts with `v` | builds the server and the apps for every platform and publishes a GitHub release |

## One-time setup

1. Create an empty repository on GitHub and push this one to it:

   ```sh
   git add -A
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin git@github.com:<you>/oot-auto-tracker.git
   git push -u origin main
   ```

   `fixtures/save` (a real save, used by the tests) is part of the commit.
   The game's map artwork in `data/local/` is not: git ignores it.

2. Optional, but recommended: give the Android app a fixed signing key.
   Without one, every release is signed with a new throwaway key and Android
   refuses to install it over the previous version (you have to uninstall
   first, which also resets the app's settings).

   ```sh
   keytool -genkeypair -v -keystore release.jks -alias oot-tracker \
     -keyalg RSA -keysize 2048 -validity 10000
   base64 -i release.jks | pbcopy     # the keystore, as text, in the clipboard
   ```

   Keep `release.jks` and its password somewhere safe and out of the
   repository. Then add these under *Settings → Secrets and variables →
   Actions → New repository secret*:

   | Secret | Value |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | the clipboard content from above |
   | `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
   | `ANDROID_KEY_ALIAS` | `oot-tracker` |
   | `ANDROID_KEY_PASSWORD` | the key password (leave out if it equals the keystore password) |

   To sign local release builds with the same key, put `release.jks` into
   `app/android/` and create `app/android/key.properties` (both are ignored
   by git):

   ```properties
   storeFile=release.jks
   storePassword=...
   keyAlias=oot-tracker
   keyPassword=...
   ```

Nothing else needs configuring: the workflows use the token GitHub provides.

## Making a release

```sh
git tag v0.1.0
git push origin v0.1.0
```

The version of the apps is taken from the tag (`v0.1.0` → `0.1.0`). After
about fifteen minutes the release appears under *Releases* with:

| File | What it is |
|---|---|
| `OoT-Tracker-Server-<tag>-macos-arm64.zip` | the server as a menu-bar app, for Apple-silicon Macs |
| `OoT-Tracker-Server-<tag>-windows-x64.zip` | the server as a tray app for Windows |
| `OoT-Tracker-Server-<tag>-linux-x64.AppImage` | the server as a tray app for Linux, as a single file |
| `OoT-Tracker-Server-<tag>-linux-x64.tar.gz` | the same as a folder |
| `OoT-Tracker-<tag>-macos-arm64.zip` | the tracker app for Apple-silicon Macs |
| `OoT-Tracker-<tag>-windows-x64.zip` | the tracker app for Windows |
| `OoT-Tracker-<tag>-linux-x64.AppImage` | the tracker app for Linux, as a single file |
| `OoT-Tracker-<tag>-linux-x64.tar.gz` | the same as a folder |
| `OoT-Tracker-<tag>-android.apk` | the tracker app for Android |
| `OoT-Tracker-<tag>-ios-unsigned.ipa` | the tracker app for iPhone and iPad, without a signature (see below) |
| `ootd-<tag>-macos-arm64.tar.gz`, `-linux-x64.tar.gz`, `-windows-x64.zip` | the command-line server with the `data` folder it needs, for headless machines |

## Installing from a release

- **Server app (the easy way):** unpack it and start *OoT Tracker Server*.
  It lives in the menu bar (macOS), the notification area (Windows) or the
  system tray (Linux); its window has all the settings, including "Start
  when I log in".
  - macOS: move it to Applications first. It is not notarized by Apple, so
    the first start needs right-click → Open (or
    `xattr -dr com.apple.quarantine "OoT Tracker Server.app"`).
  - Windows: keep the whole unpacked folder together and start
    `oot_tracker_host.exe`. SmartScreen warns about an unknown publisher
    ("More info" → "Run anyway"), and the firewall asks once whether the
    server may be reached from the network: allow it for private networks.
  - Linux: make the `.AppImage` executable (`chmod +x`, or in the file
    manager's properties) and start it. "Start when I log in" remembers
    where the file is, so move it to its final place first. Or unpack the
    `.tar.gz`, keep the folder together and start `oot_tracker_host`. The
    tray-icon libraries come with both. (A build from source needs
    `libayatana-appindicator3-1` installed, `libayatana-appindicator-gtk3`
    on Fedora.)
    GNOME shows tray icons only with the AppIndicator extension; without it
    the server still runs, and starting the app again shows its window.
- **Command-line server:** unpack, then run `./ootd` (`ootd.exe` on Windows).
  On macOS `./install-launchd.sh` starts it at login, and a blocked download
  is cleared with `xattr -dr com.apple.quarantine ootd`. Run either this or
  the server app, not both.
- **macOS app:** unpack and move it to Applications; first start as above
  (`xattr -dr com.apple.quarantine "OoT Tracker.app"`).
- **Windows app:** unpack, keep the folder together, start
  `oot_tracker_app.exe`.
- **Linux app:** make the `.AppImage` executable and start it, or unpack the
  `.tar.gz`, keep the folder together and start `oot_tracker_app`.
- **Android app:** open the APK on the phone and allow installing from that
  source, or `adb install -r OoT-Tracker-<tag>-android.apk`.
- **iOS app:** Apple only runs signed apps, and the release cannot be signed
  without a paid developer account. Sign the `.ipa` with your own Apple ID
  using a sideloading tool such as AltStore or Sideloadly (with a free Apple
  ID the signature lasts seven days), or build and install from source with
  Xcode: `cd app && flutter run --release` with the iPhone connected and
  your team selected in `ios/Runner.xcworkspace`. On first start, allow
  access to the local network.
- **Maps:** the game's map artwork is never part of a release. In the server
  app, open "Maps" and choose "Read from game file…": pick the `RomFS.img`
  of the PC port (or "From a folder…" for unpacked game files). With the
  command-line server it is `ootd --extract-maps <RomFS.img or folder>`.
  Without the pictures the apps show a drawn diagram.

## If a build fails

- The Flutter version is pinned as `FLUTTER_VERSION` at the top of both
  workflow files; change it there when you upgrade locally.
- The macOS app is built for Apple silicon only (`EXCLUDED_ARCHS` in
  `app/macos/Runner/Configs/Release.xcconfig` and the Podfile). That is also a
  workaround: Flutter 3.38 cannot verify a universal build with Xcode 27. Once
  a newer Flutter fixes it, remove those two settings for a universal app.
- `app/android/gradle.properties` may contain an `org.gradle.java.home` line
  for your own machine. The Android job removes it and uses its own JDK 21.
- The server app bundles the checklist from `host/assets/data/`, which
  `dart run tool/sync_data.dart` (in `host`) copies from `data/`. The
  workflows run it; a local build that skips it fails on the missing folder.
- The iOS and macOS projects require iOS 15 and macOS 13, the oldest that
  Xcode 27 still builds for.
- Linux builds install their packages from the `LINUX_PACKAGES` line at the
  top of `release.yml`.
- The AppImages are made by `tools/appimage/make.sh` with `appimagetool`,
  which the workflow downloads from its project's rolling "continuous"
  release; if a build breaks there without a change on our side, pin a
  dated release in `release.yml`.
