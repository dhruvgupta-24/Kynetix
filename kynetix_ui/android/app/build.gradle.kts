import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Store (Play upload) signing ────────────────────────────────────────────
// App bundles (`flutter build appbundle`, the only thing Play takes) are
// always signed with the upload key, and the build fails without it, so a
// debug-signed bundle can never reach Play. APKs keep the debug key unless
// asked, so a sideloaded `flutter build apk` still installs over a dev
// install on a phone without an uninstall (which would wipe local data):
//   flutter build apk --release --android-project-arg=kynetixStoreRelease=true
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) load(FileInputStream(keystorePropertiesFile))
}
val buildingReleaseBundle = gradle.startParameter.taskNames.any {
    it.contains("bundle", ignoreCase = true) && it.contains("release", ignoreCase = true)
}
if (buildingReleaseBundle && !keystorePropertiesFile.exists()) {
    throw GradleException(
        "Release app bundles must be signed with the upload key: android/key.properties is missing.",
    )
}
val useStoreSigning = keystorePropertiesFile.exists() &&
    (buildingReleaseBundle || (project.findProperty("kynetixStoreRelease") as String?)?.toBoolean() == true)

android {
    namespace = "com.kynetix.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (rest-timer notifications) needs core
        // library desugaring on older Android versions.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.kynetix.app"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("upload") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (useStoreSigning) signingConfigs.getByName("upload")
                else signingConfigs.getByName("debug")
            // R8: shrink + obfuscate Java/Kotlin and drop unused resources.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
