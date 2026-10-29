import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
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
    // على جهاز المطور (بدون الملف) نرجع لمفتاح debug العادي.
    // نسخة Google Play تنبني على السيرفر (server/build-aab.sh) بمفتاح الرفع، و FISHID_UPLOAD_KEY يشير لملف خصائصه.
    val testKeystore = file("test-builds.keystore")
    val upload = System.getenv("FISHID_UPLOAD_KEY")?.let { file(it) }?.takeIf { it.exists() }?.let { f ->
        Properties().apply { f.inputStream().use { load(it) } }
    }
    signingConfigs {
        create("testBuilds") {
            storeFile = testKeystore
            storePassword = "android"
            keyAlias = "fishid-test"
            keyPassword = "android"
        }
        if (upload != null) {
            create("upload") {
                storeFile = file(upload.getProperty("storeFile"))
                storePassword = upload.getProperty("storePassword")
                keyAlias = upload.getProperty("keyAlias")
                keyPassword = upload.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                when {
                    upload != null -> "upload"
                    testKeystore.exists() -> "testBuilds"
                    else -> "debug"
                },
            )
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
