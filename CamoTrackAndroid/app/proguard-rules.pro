# kotlinx.serialization: keep the generated serializers of the @Serializable models
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class app.camotrack.android.**$$serializer { *; }
-keepclassmembers class app.camotrack.android.** { *** Companion; }
-keepclasseswithmembers class app.camotrack.android.** { kotlinx.serialization.KSerializer serializer(...); }

# LevelPlay and its networks ship their own consumer rules; these cover reflection they document
-keep class com.unity3d.mediation.** { *; }
-keep class com.ironsource.** { *; }
-dontwarn com.ironsource.**
-dontwarn com.unity3d.**
