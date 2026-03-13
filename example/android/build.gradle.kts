allprojects {
    repositories {
        google()
        mavenCentral()
        mavenLocal()
        // RiviumSync SDK Repository (R2)
        maven { url = uri("https://pub-69e86fbad8904e4a8bd3a1b2d051df1f.r2.dev/maven") }
        // Eclipse Paho for MQTT
        maven { url = uri("https://repo.eclipse.org/content/repositories/paho-releases/") }
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
