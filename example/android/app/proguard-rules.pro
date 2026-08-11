# ProGuard/R8 rules cho release.
#
# Hiện tại release đang để isMinifyEnabled = false (xem build.gradle.kts) nên
# file này CHƯA được áp dụng. Khi muốn bật tối ưu/thu nhỏ APK cho production:
#   1. Trong android/app/build.gradle.kts, buildTypes.release đặt:
#        isMinifyEnabled = true
#        isShrinkResources = true
#        proguardFiles(
#            getDefaultProguardFile("proguard-android-optimize.txt"),
#            "proguard-rules.pro"
#        )
#   2. Build lại: flutter build apk --release
#
# Các keep rule dưới đây fix lỗi màn trắng do R8 đổi tên androidx.work/Room
# (WorkManager khởi tạo WorkDatabase bằng reflection theo canonicalName).

# --- WorkManager / Room ---
-keep class androidx.work.** { *; }
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-keep class androidx.room.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep @androidx.room.Entity class * { *; }
-dontwarn androidx.work.**
-dontwarn androidx.room.**

# --- androidx.startup (InitializationProvider) ---
-keep class androidx.startup.** { *; }

# --- Flutter (an toàn cho plugin dùng reflection/method channel) ---
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
