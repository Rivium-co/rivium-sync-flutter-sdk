pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")

// Include local RiviumSync Android SDK for development
// Substitutes Maven dependency co.rivium.sync:rivium-sync-android:1.0.0 with local build
val localSyncSdkDir = file("../../../android")
if (localSyncSdkDir.exists() && file("${localSyncSdkDir}/rivium_sync").exists()) {
    println("RiviumSync: Including local Android SDK from ${localSyncSdkDir.absolutePath}")
    includeBuild(localSyncSdkDir) {
        name = "rivium-sync-sdk"
        dependencySubstitution {
            substitute(module("co.rivium.sync:rivium-sync-android")).using(project(":rivium_sync"))
        }
    }
}

// Include local RiviumPush Android SDK for development
// Substitutes Maven dependency co.rivium:rivium-push-android with local build
val localPushSdkDir = file("../../../../pushino_project/android")
if (localPushSdkDir.exists() && file("${localPushSdkDir}/rivium-push").exists()) {
    println("RiviumPush: Including local Android SDK from ${localPushSdkDir.absolutePath}")
    includeBuild(localPushSdkDir) {
        name = "rivium-push-sdk"
        dependencySubstitution {
            substitute(module("co.rivium:rivium-push-android")).using(project(":rivium-push"))
        }
    }
}
