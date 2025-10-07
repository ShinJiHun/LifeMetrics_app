plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin must be applied after Android and Kotlin plugins
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.riding_information_apps"

    // ✅ 최신 SDK 및 NDK 버전 명시
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.1.13356709" // maplibre_gl이 요구하는 NDK 버전

    defaultConfig {
        applicationId = "com.example.riding_information_apps"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ✅ JDK 17 이상 사용
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // ✅ Kotlin JVM 타겟도 17로
    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
