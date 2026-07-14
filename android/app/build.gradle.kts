plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

import java.util.Properties

// Shared upload/CI keystore (android/key.properties). Used for:
// - release builds
// - debug APKs when present so Firebase App Distribution + Google Sign-In
//   share a stable SHA-1 (not the ephemeral CI debug.keystore).
val keystorePropertiesFile = rootProject.projectDir.resolve("key.properties")
val keystoreProperties = Properties()
val hasUploadKeystore = keystorePropertiesFile.exists()
if (hasUploadKeystore) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

fun resolveStoreFile(path: String): java.io.File {
    val f = file(path)
    if (f.isFile) return f
    // Paths in key.properties are relative to android/
    return rootProject.file(path)
}

android {
    namespace = "com.logicrequire.room_craft"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        if (hasUploadKeystore) {
            create("upload") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = resolveStoreFile(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "com.logicrequire.room_craft"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("debug") {
            // Prefer stable upload key so distributed debug APKs keep one SHA-1.
            if (hasUploadKeystore) {
                signingConfig = signingConfigs.getByName("upload")
            }
        }
        release {
            signingConfig = if (hasUploadKeystore) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
