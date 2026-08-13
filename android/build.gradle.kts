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

// Alinha Java e Kotlin para JVM 17 em TODOS os módulos (app + plugins).
//
// Alguns plugins (ex.: `live_activities`) declaram Java 11 no próprio
// build.gradle. Se só o Kotlin for forçado para 17, o Gradle aborta com:
//   "Inconsistent JVM-target compatibility ... Java (11) e Kotlin (17)".
//
// Este bloco NÃO usa `evaluationDependsOn`, então o `afterEvaluate` é válido
// e roda DEPOIS do bloco `android {}` do plugin (vencendo o Java 11) e ANTES
// de o AGP finalizar as `compileOptions`.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            if (ext is com.android.build.gradle.BaseExtension) {
                ext.compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
        // Kotlin 2.2 REMOVEU o `kotlinOptions` (virou erro de compilação do
        // script). A DSL atual é `compilerOptions`, com enum em vez de string.
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
