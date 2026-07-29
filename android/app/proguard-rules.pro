# Flutter specific
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep serialization
-keepattributes *Annotation*, Signature
-keep class * extends java.util.List { *; }
-keep class * extends java.util.Map { *; }

# app models (json_serializable)
-keep class moritzu.hermes.** { *; }

# HTTP/networking
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# WebSocket
-keep class web_socket_channel.** { *; }

# Speech recognition & TTS native libs
-keep class com.speech_to_text.** { *; }
-keep class com.flutter_tts.** { *; }
