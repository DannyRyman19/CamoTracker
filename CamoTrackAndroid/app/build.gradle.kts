plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "app.camotrack.android"
    compileSdk = 35
    defaultConfig {
        applicationId = "app.camotrack.android"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1"
    }
    buildFeatures { compose = true; buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

// The iPhone app's bundled data (games.json and every game's seed files), copied
// in at build time so both apps ship the same starting data from one place.
val copySeeds by tasks.registering(Copy::class) {
    from("../../MW4CamoTracker/Resources") { include("*.json") }
    into(layout.buildDirectory.dir("generated/seeds/seeds"))
}
android.sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/seeds"))
tasks.named("preBuild") { dependsOn(copySeeds) }

dependencies {
    val compose = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(compose)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.work:work-runtime-ktx:2.10.0")
    implementation("com.android.billingclient:billing-ktx:7.1.1")
    // LevelPlay (Unity's ad mediation) and its Unity Ads adapter, as on iPhone
    implementation("com.unity3d.ads-mediation:mediation-sdk:9.7.0")
    implementation("com.unity3d.ads-mediation:unityads-adapter:5.15.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
}
