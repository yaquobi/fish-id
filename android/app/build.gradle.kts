plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "sa.hawat.fish_id"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "sa.hawat.fish_id"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // توقيع ثابت لنسخ التجربة اللي تنبني في GitHub Actions، عشان كل نسخة تتركّب فوق اللي قبلها.
    // المفتاح ما ينحفظ في المستودع: سير العمل apk.yml ينشئه مرة وحدة ويحفظه في ذاكرة Actions المؤقتة.
    // على جهاز المطور (بدون الملف) نرجع لمفتاح debug العادي. نسخة Google Play تحتاج مفتاحًا خاصًا منفصلًا.
    val testKeystore = file("test-builds.keystore")
    signingConfigs {
        create("testBuilds") {
            storeFile = testKeystore
            storePassword = "android"
            keyAlias = "fishid-test"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (testKeystore.exists()) "testBuilds" else "debug")
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
