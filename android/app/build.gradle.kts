import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.intellisys.corretor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.intellisys.corretor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystorePropertiesFile = rootProject.file("key.properties")
            if (keystorePropertiesFile.exists()) {
                val keystoreProperties = Properties()
                keystorePropertiesFile.inputStream().use {
                    keystoreProperties.load(it)
                }
                
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Usar assinatura de release se key.properties existir, senão usar debug
            signingConfig = if (rootProject.file("key.properties").exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            
            // Habilitar minificação e otimização
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

// Celular físico + 127.0.0.1: USB redireciona a porta da API (usa adb do SDK, não só PATH).
afterEvaluate {
    listOf("assembleDebug", "installDebug").forEach { taskName ->
        tasks.findByName(taskName)?.doFirst {
            try {
                val home = System.getenv("ANDROID_HOME")
                    ?: System.getenv("ANDROID_SDK_ROOT")
                val adb = if (home != null) {
                    val sep = File.separator
                    val base = home.trimEnd('/', '\\')
                    val candidate = if (
                        System.getProperty("os.name").orEmpty().lowercase().contains("win")
                    ) {
                        "${base}${sep}platform-tools${sep}adb.exe"
                    } else {
                        "${base}${sep}platform-tools${sep}adb"
                    }
                    if (File(candidate).isFile) candidate else "adb"
                } else {
                    "adb"
                }
                project.exec {
                    commandLine(adb, "reverse", "tcp:3000", "tcp:3000")
                    isIgnoreExitValue = true
                }
            } catch (_: Exception) {
                // Sem SDK, sem dispositivo ou reverse já feito
            }
        }
    }
}
