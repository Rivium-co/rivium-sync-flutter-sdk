# RiviumSync SDK ProGuard Rules
# These rules are automatically applied to consuming apps via consumerProguardFiles

# ---- OkHttp ----
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-keep class okio.** { *; }

# ---- Gson ----
-dontwarn com.google.gson.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
# Keep fields annotated with @SerializedName
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ---- RiviumSync SDK data classes (used by Gson reflection) ----
-keep class co.rivium.sync.sdk.MqttTokenResponse { *; }
-keep class co.rivium.sync.sdk.MqttConnectionInfo { *; }
-keep class co.rivium.sync.sdk.ApiResponse { *; }
-keep class co.rivium.sync.sdk.QueryParams { *; }
-keep class co.rivium.sync.sdk.QueryFilter { *; }
-keep class co.rivium.sync.sdk.DatabaseInfo { *; }
-keep class co.rivium.sync.sdk.CollectionInfo { *; }
-keep class co.rivium.sync.sdk.SyncDocument { *; }

# ---- Paho MQTT ----
-keep class org.eclipse.paho.client.mqttv3.** { *; }
-dontwarn org.eclipse.paho.client.mqttv3.**

# ---- Room Database (offline persistence) ----
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *
-dontwarn androidx.room.**

# ---- Kotlin Coroutines ----
-dontwarn kotlinx.coroutines.**

# ---- Gson generic types ----
# `object : TypeToken<Map<String, Any?>>() {}` needs the generic signatures and the TypeToken subclasses; R8 (full
# mode, the default since AGP 8) removes them, and release builds then fail with "TypeToken must be created with a
# type argument".
-keepattributes Signature, InnerClasses, EnclosingMethod, *Annotation*
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# ---- RiviumSync SDK classes read and written by Gson ----
-keep class co.rivium.sync.** { *; }
