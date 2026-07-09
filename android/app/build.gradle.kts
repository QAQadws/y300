plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials are kept out of version control in
// `android/key.properties` (git-ignored). When the file is absent — a fresh
// clone, or a machine without the keystore — we fall back to debug signing so
// `flutter run` still works. Only real release builds require the file.
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}


android {
    namespace = "com.example.y300"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Base name for build artifacts, so the APK is emitted as `y300-release.apk`
    // instead of the module-default `app-release.apk`.
    setProperty("archivesBaseName", "y300")

    compileOptions {
        // flutter_local_notifications (v21+) requires Java 8+ API desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Public application identity used by the Play Store / sideloaded installs
        // for update matching. Fixed at release — do not change once distributed.
        // (The Kotlin `namespace` above stays internal and need not match this.)
        applicationId = "com.adws.y300"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Populated only when android/key.properties exists (real release builds).
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the real release keystore when configured; otherwise fall back to
            // debug signing so `flutter run --release` still works without a keystore.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
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

dependencies {
    // Required by flutter_local_notifications when core library desugaring is on.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
