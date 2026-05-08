import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.dreamkeys.corretor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.dreamkeys.corretor"
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
            } else {
                // Fallback por variável de ambiente para build em CI/outra máquina.
                val envStoreFile = System.getenv("DK_STORE_FILE")
                val envStorePassword = System.getenv("DK_STORE_PASSWORD")
                val envKeyAlias = System.getenv("DK_KEY_ALIAS")
                val envKeyPassword = System.getenv("DK_KEY_PASSWORD")
                if (!envStoreFile.isNullOrBlank() &&
                    !envStorePassword.isNullOrBlank() &&
                    !envKeyAlias.isNullOrBlank() &&
                    !envKeyPassword.isNullOrBlank()
                ) {
                    storeFile = file(envStoreFile)
                    storePassword = envStorePassword
                    keyAlias = envKeyAlias
                    keyPassword = envKeyPassword
                }
            }
        }
    }

    buildTypes {
        release {
            val hasKeyProps = rootProject.file("key.properties").exists()
            val hasEnvSigning = !System.getenv("DK_STORE_FILE").isNullOrBlank() &&
                !System.getenv("DK_STORE_PASSWORD").isNullOrBlank() &&
                !System.getenv("DK_KEY_ALIAS").isNullOrBlank() &&
                !System.getenv("DK_KEY_PASSWORD").isNullOrBlank()
            if (!hasKeyProps && !hasEnvSigning) {
                throw GradleException(
                    "Release sem chave de assinatura. " +
                        "Crie android/key.properties ou defina DK_STORE_FILE, DK_STORE_PASSWORD, " +
                        "DK_KEY_ALIAS e DK_KEY_PASSWORD."
                )
            }
            signingConfig = signingConfigs.getByName("release")
            
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
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
