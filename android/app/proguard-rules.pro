# R8/ProGuard rules for Gota release builds (Sprint 08).
#
# Dart code is compiled AOT and is not processed by R8; these rules protect the
# Java/Kotlin layers: the Flutter embedding, plugins (firebase_messaging, etc.),
# and anything reached via reflection or annotations.

# --- Flutter embedding & plugins ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- @Keep annotations (androidx + legacy support variants) ---
-keep @androidx.annotation.Keep class * { *; }
-keep,allowobfuscation @interface androidx.annotation.Keep
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <methods>;
}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <fields>;
}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <init>(...);
}
-keep @android.support.annotation.Keep class * { *; }
-keep,allowobfuscation @interface android.support.annotation.Keep
-keepclasseswithmembers class * {
    @android.support.annotation.Keep <methods>;
}
-keepclasseswithmembers class * {
    @android.support.annotation.Keep <fields>;
}
-keepattributes *Annotation*

# --- Firebase (google-services plugin applies conditionally; be safe anyway) ---
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# --- Reflection/serialization boilerplate (gson and friends) ---
-keepattributes Signature
-keepattributes EnclosingMethod
-keep class com.google.gson.** { *; }
-dontwarn sun.misc.**
