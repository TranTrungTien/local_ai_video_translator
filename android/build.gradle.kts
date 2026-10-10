allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    project.layout.buildDirectory.value(newBuildDir.dir(project.name))
    pluginManager.withPlugin("com.android.library") {
        pluginManager.apply("org.jetbrains.kotlin.android")
    }
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.property("android") as? com.android.build.gradle.BaseExtension
            android?.apply {
                compileSdkVersion(35)
                buildToolsVersion("36.0.0")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
