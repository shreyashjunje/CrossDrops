# Release builds

How to make builds that can go to people other than the test phones. Device tests come first ([STATUS.md](STATUS.md)); this page only covers signing and identity.

## App identity (D-063)

| Platform | Id |
| --- | --- |
| Android application id and namespace | `io.github.shreyashjunje.crossdrop` |
| iOS app | `io.github.shreyashjunje.crossdrop` |
| iOS Share Extension | `io.github.shreyashjunje.crossdrop.ShareExtension` |
| iOS App Group | `group.io.github.shreyashjunje.crossdrop` (`APP_GROUP_ID` build setting) |

Changing an id after the first store upload makes a new app: users lose their trusted devices and history. Change it, if at all, before then; the places are `android/app/build.gradle.kts`, the Kotlin package folder, and `ios/Runner.xcodeproj/project.pbxproj`.

## Android signing

A release build needs a release key. Without one, `flutter build apk --release` stops with "No release signing key". For a quick test build signed with the debug key, set `CROSSDROP_ALLOW_DEBUG_SIGNING=true` (PowerShell: `$env:CROSSDROP_ALLOW_DEBUG_SIGNING='true'`). Such a build cannot update, or be updated by, any differently signed build.

**Create the key once** and keep it, with its passwords, somewhere safe and backed up. Losing it means no more updates under this application id.

```sh
keytool -genkeypair -v -keystore crossdrop-release.jks -keyalg RSA -keysize 4096 -validity 10000 -alias crossdrop
```

**Local builds:** create `android/key.properties` (ignored by git):

```properties
storeFile=C:/keys/crossdrop-release.jks
storePassword=...
keyAlias=crossdrop
keyPassword=...
```

`storeFile` is an absolute path, or relative to `android/app`.

**CI builds:** add these repository secrets (Settings > Secrets and variables > Actions):

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 crossdrop-release.jks` (PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes('crossdrop-release.jks'))`) |
| `ANDROID_KEYSTORE_PASSWORD` | the store password |
| `ANDROID_KEY_ALIAS` | `crossdrop` |
| `ANDROID_KEY_PASSWORD` | the key password |

With them, the Build workflow signs the APK with the release key. Without them it still builds, signed with the runner's debug key, and names the file `*-debugsigned.apk`.

For Google Play, use Play App Signing and upload an app bundle (`flutter build appbundle`) signed with this key as the upload key.

## iPhone

CI builds are unsigned; Sideloadly signs them with a free Apple ID for the test phones (D-017). Free accounts cannot use the App Group across the app and the Share Extension as published ids, nor the Hotspot Configuration capability (D-055). Distribution (TestFlight or the App Store) needs a paid Apple Developer account, App IDs for the app and the extension with the App Group above, and signing on a Mac or in CI with the account's certificates.

## Before the first public build

- Device tests passed on one iPhone and one Android phone ([DEVICE_TESTS.md](DEVICE_TESTS.md)).
- Version in `pubspec.yaml` raised (`version: x.y.z+build`).
- App icon and store listing; privacy text: no accounts, no analytics, nothing leaves the local network.
- A licence chosen for any public release of the source; [LICENSE](../LICENSE) is "all rights reserved" until then.
