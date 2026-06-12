

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.messaging_app"

    // Use fixed SDK because Firebase / notification / call plugins need newer SDK.
    compileSdk = 36

    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.messaging_app"

        // Keep at least 23/24 for modern call + notification plugins.
        minSdk = 24

        targetSdk = 36

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }

        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    implementation("androidx.multidex:multidex:2.0.1")

    // Firebase Messaging dependency. Flutter plugin also adds it,
    // but keeping this helps avoid missing native dependency issues.
    implementation("com.google.firebase:firebase-messaging:24.1.0")
}