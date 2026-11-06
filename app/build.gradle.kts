plugins {
    id("com.android.application") version "9.2.0"
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.10"
}

android {
    namespace = "id.seiran.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "id.seiran.app"
        minSdk = 29
        targetSdk = 36
        versionCode = 2
        versionName = "0.2"
    }

    signingConfigs {
        create("release") {
            val ks = System.getenv("SEIRAN_APP_KS_FILE")
            if (ks != null) {
                storeFile = file(ks)
                storePassword = System.getenv("SEIRAN_APP_KS_PASS")
                keyAlias = "seiran"
                keyPassword = System.getenv("SEIRAN_APP_KS_PASS")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.06.00"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.compose.material:material-icons-core")
    implementation("com.github.topjohnwu.libsu:core:6.0.0")
}
