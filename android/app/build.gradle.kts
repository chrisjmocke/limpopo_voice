plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // 🔥 Add this line exactly as requested:
    ndkVersion = "28.2.13676358"

    namespace = "com.limpopovoice.translate"
    compileSdk = flutter.compileSdkVersion
    namespace = "com.limpopovoice.translate"
    compileSdk = flutter.compileSdkVersion

    defaultConfig {
        applicationId = "com.limpopovoice.translate"

        // 🔥 IMPORTANT FIX
        minSdk = flutter.minSdkVersion

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    signingConfigs {
        create("release") {
            keyAlias = "limpopo"
            keyPassword = "KatbokStudiosLimpopoVoice2026"
            storeFile = file("limpopo-release-key.jks")
            storePassword = "KatbokStudiosLimpopoVoice2026"
        }
    }

    buildTypes {

        release {

            // 🔥 USE REAL SIGNING
            signingConfig = signingConfigs.getByName("release")

            // 🔥 KEEP THESE OFF FOR NOW
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
