package com.xax.CryptoSavingsTracker.presentation

import com.google.common.truth.Truth.assertThat
import java.io.File
import org.junit.jupiter.api.Test

class UiRawExecutionStatusGuardTest {

    @Test
    fun presentationLayer_mustNotBranchOnRawExecutionStatus() {
        val rootPath = System.getProperty("user.dir") ?: error("user.dir is unavailable")
        val root = File(rootPath)
        val presentationDirCandidates = listOf(
            File(root, "app/src/main/java/com/xax/CryptoSavingsTracker/presentation"),
            File(root, "android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation"),
            File(root, "src/main/java/com/xax/CryptoSavingsTracker/presentation"),
            File(root, "../app/src/main/java/com/xax/CryptoSavingsTracker/presentation"),
            File(root, "../src/main/java/com/xax/CryptoSavingsTracker/presentation")
        )
        val presentationDir = presentationDirCandidates.firstOrNull { it.exists() }
        require(presentationDir != null) {
            val checked = presentationDirCandidates.joinToString(separator = ", ") { it.absolutePath }
            "Presentation directory not found. Checked: $checked"
        }

        val forbiddenPattern = Regex("""status\s*==\s*ExecutionStatus\.[A-Z_]+""")
        val violations = mutableListOf<String>()

        presentationDir
            .walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .forEach { file ->
                file.readLines().forEachIndexed { index, line ->
                    if (forbiddenPattern.containsMatchIn(line)) {
                        violations += "${file.absolutePath}:${index + 1}: ${line.trim()}"
                    }
                }
            }

        assertThat(violations).isEmpty()
    }
}
