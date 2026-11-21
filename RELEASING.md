# Builds and releases

Two GitHub Actions workflows live in `.github/workflows/`:

| Workflow | Runs on | Does |
|---|---|---|
| `ci.yml` | every push to `main` and every pull request | analyzes the code and runs all tests |
| `release.yml` | every pushed tag that starts with `v` | builds the server and both apps and publishes a GitHub release |

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
about ten minutes the release appears under *Releases* with:

| File | What it is |
|---|---|
| `ootd-<tag>-macos-arm64.tar.gz` | the server for Apple-silicon Macs, with the `data` folder it needs and `install-launchd.sh` |
| `ootd-<tag>-linux-x64.tar.gz` | the same for Linux (no network announcement there; enter the address in the app) |
| `OoT-Tracker-<tag>-macos.zip` | the macOS app, for Apple-silicon Macs |
| `OoT-Tracker-<tag>-android.apk` | the Android app |

## Installing from a release

- **Server:** unpack, then run `./ootd`, or `./install-launchd.sh` to start it
  at login. macOS may block the downloaded binary; clear that once with
  `xattr -dr com.apple.quarantine ootd`.
- **macOS app:** unpack and move it to Applications. It is not notarized by
  Apple, so the first start needs right-click → Open (or
  `xattr -dr com.apple.quarantine "OoT Tracker.app"`).
- **Android app:** open the APK on the phone and allow installing from that
  source, or `adb install -r OoT-Tracker-<tag>-android.apk`.
- **Maps:** the game's map artwork is never part of a release. Extract it from
  your own copy of the game into the server's `data/local/maps/` folder as the
  main README describes; without it the apps show the drawn diagram.

## If a build fails

- The Flutter version is pinned as `FLUTTER_VERSION` at the top of both
  workflow files; change it there when you upgrade locally.
- The macOS app is built for Apple silicon only (`EXCLUDED_ARCHS` in
  `app/macos/Runner/Configs/Release.xcconfig` and the Podfile). That is also a
  workaround: Flutter 3.38 cannot verify a universal build with Xcode 27. Once
  a newer Flutter fixes it, remove those two settings for a universal app.
- `app/android/gradle.properties` may contain an `org.gradle.java.home` line
  for your own machine. The Android job removes it and uses its own JDK 21.
