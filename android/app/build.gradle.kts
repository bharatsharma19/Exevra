import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Build defines passed by `flutter build/run --dart-define[-from-file]`,
// base64-encoded as "KEY=value" entries. Used here only for non-secret values.
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.filter { it.isNotBlank() }
        ?.map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
        ?.mapNotNull { entry ->
            entry.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] }
        }
        ?.toMap()
        ?: emptyMap()

// Host of the verified invite App Links. Must match AppConfig.defaultAppLinkHost
// in lib/core/config/app_config.dart. Order: the APP_LINK_HOST build define,
// then the Gradle property exevra.appLinkHost, then the default.
val appLinkHost: String =
    dartDefines["APP_LINK_HOST"]?.trim()?.takeIf { it.isNotEmpty() }
        ?: (project.findProperty("exevra.appLinkHost") as String?)?.trim()?.takeIf { it.isNotEmpty() }
        ?: "exevra.app"

if (!Regex("^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$").matches(appLinkHost)) {
    throw GradleException("APP_LINK_HOST must be a bare host name such as exevra.app, got '$appLinkHost'.")
}

// Release signing. The upload key is read from android/key.properties, which
// is gitignored (see android/key.properties.example). Without it a release
// build fails, unless the Gradle property
// exevra.allowDebugSigningForLocalTesting=true is set, in which case the
// release build is signed with the debug key and must never be distributed.
val keystorePropertiesFile: File = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val releaseSigningProblem: String? =
    if (!keystorePropertiesFile.exists()) {
        "android/key.properties was not found."
    } else {
        val missing =
            listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
                .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
        when {
            missing.isNotEmpty() ->
                "android/key.properties is missing ${missing.joinToString()}."
            !rootProject.file(keystoreProperties.getProperty("storeFile")).isFile ->
                "the keystore named by storeFile in android/key.properties does not exist."
            else -> null
        }
    }
val allowDebugSigningForLocalTesting: Boolean =
    (project.findProperty("exevra.allowDebugSigningForLocalTesting") as String?)
        ?.trim()
        ?.equals("true", ignoreCase = true) == true

android {
    namespace = "com.exevra.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.exevra.app"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLinkHost"] = appLinkHost
    }

    signingConfigs {
        if (releaseSigningProblem == null) {
            create("release") {
                // A relative storeFile is resolved against the android/ directory.
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                when {
                    releaseSigningProblem == null -> signingConfigs.getByName("release")
                    allowDebugSigningForLocalTesting -> signingConfigs.getByName("debug")
                    else -> null
                }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// Stops a release build that would otherwise be unsigned or debug-signed.
val verifyReleaseSigning by tasks.registering {
    description = "Checks that release signing is configured."
    val problem = releaseSigningProblem
    val allowDebug = allowDebugSigningForLocalTesting
    doFirst {
        if (problem != null && !allowDebug) {
            throw GradleException(
                """
                |Release signing is not configured: $problem
                |Create android/key.properties with storeFile, storePassword, keyAlias and
                |keyPassword (see android/key.properties.example). For a local test build
                |only, set the Gradle property exevra.allowDebugSigningForLocalTesting=true
                |(for example ORG_GRADLE_PROJECT_exevra.allowDebugSigningForLocalTesting=true);
                |such a build is signed with the debug key and must never be distributed.
                """.trimMargin(),
            )
        }
        if (problem != null) {
            logger.warn("WARNING: this release build is signed with the DEBUG key for local testing only.")
        }
    }
}
tasks.configureEach {
    if (name == "preReleaseBuild") dependsOn(verifyReleaseSigning)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
