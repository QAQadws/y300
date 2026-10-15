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

    // Kotlin's relocatable incremental cache cannot relativize C:/ Pub sources
    // against an E:/ project. Keep incremental compilation for same-root builds.
    // https://youtrack.jetbrains.com/issue/KT-65155
    if (System.getProperty("os.name").startsWith("Windows") &&
        projectDir.toPath().root != rootProject.projectDir.toPath().root
    ) {
        extensions.extraProperties.set("kotlin.incremental", "false")
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
