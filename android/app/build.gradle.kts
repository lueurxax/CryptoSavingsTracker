plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

android {
    namespace = "com.xax.CryptoSavingsTracker"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.xax.CryptoSavingsTracker"
        minSdk = 34
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "com.xax.CryptoSavingsTracker.HiltTestRunner"

        // Room schema export for migrations
        ksp {
            arg("room.schemaLocation", "$projectDir/schemas")
            arg("room.incremental", "true")
            arg("room.generateKotlin", "true")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    // Core Android
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)

    // Jetpack Compose (BOM)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)

    // Navigation
    implementation(libs.androidx.navigation.compose)
    implementation(libs.hilt.navigation.compose)

    // Room Database
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)

    // Hilt DI
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)

    // Networking
    implementation(libs.retrofit)
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging.interceptor)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.retrofit.kotlinx.serialization.converter)

    // DataStore (preferences)
    implementation(libs.datastore.preferences)

    // Security (API key storage)
    implementation(libs.security.crypto)

    // WorkManager (reminders)
    implementation(libs.work.runtime.ktx)
    implementation(libs.hilt.work)

    // Charts
    implementation(libs.vico.compose.m3)

    // ========== TESTING ==========

    // Unit Tests (JUnit 5)
    testImplementation(platform(libs.junit5.bom))
    testImplementation(libs.junit5.jupiter.api)
    testImplementation(libs.junit5.jupiter.params)
    testRuntimeOnly(libs.junit5.jupiter.engine)

    // Mocking & Assertions
    testImplementation(libs.mockk)
    testImplementation(libs.truth)
    testImplementation(libs.turbine)

    // Coroutines Testing
    testImplementation(libs.kotlinx.coroutines.test)

    // Room Testing
    testImplementation(libs.room.testing)

    // Network Mocking
    testImplementation(libs.mockwebserver)

    // Android Instrumented Tests
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.rules)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.hilt.android.testing)
    kspAndroidTest(libs.hilt.compiler)
    androidTestImplementation(libs.mockk.android)
}

tasks.withType<Test> {
    useJUnitPlatform()
}
