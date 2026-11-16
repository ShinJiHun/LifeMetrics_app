import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 맥북과 다른 PC 를 번갈아 빌드해도 같은 키로 서명해야 앱이 재설치(데이터 삭제)되지 않음.
// android/key.properties + 키스토어를 두 PC 에 똑같이 두면 그 키를, 없으면 PC 의 기본 debug 키를 씀
val sharedKeyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasSharedKey = sharedKeyProps.getProperty("storeFile") != null

android {
    namespace = "com.example.lifemetrics_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.lifemetrics_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26 // 헬스 커넥트
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasSharedKey) {
            create("shared") {
                storeFile = rootProject.file(sharedKeyProps.getProperty("storeFile"))
                storePassword = sharedKeyProps.getProperty("storePassword")
                keyAlias = sharedKeyProps.getProperty("keyAlias")
                keyPassword = sharedKeyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        val signing = signingConfigs.getByName(if (hasSharedKey) "shared" else "debug")
        debug {
            signingConfig = signing
        }
        release {
            signingConfig = signing
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
