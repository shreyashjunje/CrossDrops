import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (D-063, docs/RELEASE.md). The key comes from
// android/key.properties (storeFile, storePassword, keyAlias, keyPassword;
// never committed), or from the CROSSDROP_KEYSTORE_PATH,
// CROSSDROP_KEYSTORE_PASSWORD, CROSSDROP_KEY_ALIAS and CROSSDROP_KEY_PASSWORD
// environment variables (CI secrets). Without a key a release build stops,
// unless CROSSDROP_ALLOW_DEBUG_SIGNING=true (or -PallowDebugSigning=true)
// marks it as a test build: it is then signed with this machine's debug
// key, which can never update a properly signed install.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}

fun signingSetting(property: String, env: String): String? =
    (keyProperties.getProperty(property) ?: System.getenv(env))?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingSetting("storeFile", "CROSSDROP_KEYSTORE_PATH")
val allowDebugSigning =
    System.getenv("CROSSDROP_ALLOW_DEBUG_SIGNING") == "true" ||
        project.findProperty("allowDebugSigning") == "true"

if (releaseStoreFile == null &&
    !allowDebugSigning &&
    gradle.startParameter.taskNames.any { it.contains("Release") }
) {
    throw GradleException(
        "No release signing key. Add android/key.properties (docs/RELEASE.md), " +
            "or set CROSSDROP_ALLOW_DEBUG_SIGNING=true for a test build signed " +
            "with the debug key.",
    )
}

android {
    namespace = "io.github.shreyashjunje.crossdrop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // D-063: under the owner's GitHub namespace. Changing it later makes
        // a new app on every phone (and in the stores).
        applicationId = "io.github.shreyashjunje.crossdrop"
        // Android 10: MediaStore pending items, RELATIVE_PATH and the
        // Downloads collection (D-035).
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseStoreFile != null) {
            create("release") {
                storeFile = file(releaseStoreFile)
                storePassword = signingSetting("storePassword", "CROSSDROP_KEYSTORE_PASSWORD")
                keyAlias = signingSetting("keyAlias", "CROSSDROP_KEY_ALIAS")
                keyPassword = signingSetting("keyPassword", "CROSSDROP_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (releaseStoreFile != null) {
                    signingConfigs.getByName("release")
                } else {
                    // Only reached with CROSSDROP_ALLOW_DEBUG_SIGNING (see above).
                    signingConfigs.getByName("debug")
                }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
