allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Một số plugin (vd gallery_saver_plus) khai báo compileSdk cũ (android-31)
// nhưng các dependency AndroidX của chúng lại yêu cầu biên dịch với API 34+.
// Bump compileSdk lên 34 cho riêng các module bị thấp, không đụng tới app.
// Đăng ký hook này TRƯỚC block evaluationDependsOn để tránh lỗi
// "Cannot run afterEvaluate when the project is already evaluated".
subprojects {
    afterEvaluate {
        val android = project.extensions.findByName("android") ?: return@afterEvaluate
        val currentApi = (android.javaClass.getMethod("getCompileSdkVersion").invoke(android)
            as? String)?.removePrefix("android-")?.toIntOrNull() ?: return@afterEvaluate
        if (currentApi < 34) {
            android.javaClass
                .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                .invoke(android, 34)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
