# ML Kit's text-recognition plugin references the Chinese, Devanagari,
# Japanese and Korean recognisers, but we only ship the Latin model.
# Tell R8 those optional classes are allowed to be absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Release builds shrink and rename Java classes (R8). ML Kit finds its
# components and the Flutter plugin finds its handlers by class name at run
# time, so stripping them makes text recognition fail with
# "NullPointerException: ... getClass() on a null object reference".
# Keep them intact.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google.firebase.components.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }

# Supabase keeps your sign-in in shared_preferences. R8 rewrote that
# plugin's Kotlin code in release builds, so Supabase failed to start with
# "NoSuchMethodError: ... SharedPreferencesApiRegistrar.getAll". Keep the
# Flutter plugins' Android code exactly as built.
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class dev.flutter.pigeon.** { *; }
-keepclassmembers class * {
    @kotlin.jvm.JvmStatic *;
}
-keep class kotlin.coroutines.Continuation { *; }
-dontwarn io.flutter.embedding.**
