# Kynetix release keep rules (R8).
# Flutter engine + plugin registrant
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# App code (MainActivity, method channels, home-screen widget provider)
-keep class com.kynetix.app.** { *; }

# Health Connect (health plugin uses reflection / generated records)
-keep class androidx.health.** { *; }
-keep class cachet.plugins.health.** { *; }
-dontwarn androidx.health.**

# Google Sign-In / Play services auth
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.android.gms.**

# Kotlin coroutines / serialization metadata used by plugins
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-dontwarn kotlinx.**

# Play Core split-install classes referenced by the Flutter embedding
-dontwarn com.google.android.play.core.**
