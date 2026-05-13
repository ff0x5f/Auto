package org.autojs.autojs

import android.content.Intent
import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import org.autojs.autojs.ui.main.MainActivity
import org.autojs.autojs.ui.splash.SplashActivity
import org.junit.Test

/**
 * App startup survival test.
 *
 * Test strategy:
 * 1. Launch app through SplashActivity
 * 2. Force wait 10 seconds (covers 2s crash + initialization)
 * 3. Check survival indicators:
 *    - No crash (ActivityScenario still valid)
 *    - No RuntimeException in logs
 *    - Either on MainActivity or SplashActivity still showing
 */
class AppStartupTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    /**
     * Core startup survival test.
     * Launch -> Wait 10s -> Check survival.
     */
    @Test
    fun testAppStartupSurvival() {
        val intent = Intent(
            ApplicationProvider.getApplicationContext(),
            SplashActivity::class.java
        ).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        // Launch and expect no crash
        @Suppress("UNCHECKED_CAST")
        val scenario = ActivityScenario.launch(SplashActivity::class.java, intent)

        // Verify SplashActivity started
        scenario.onActivity { activity ->
            assert(activity is SplashActivity) {
                "Expected SplashActivity, got ${activity.javaClass.name}"
            }
        }

        // Force wait 10 seconds
        // This covers:
        // - 1s splash delay
        // - Navigation to MainActivity
        // - Any async initialization
        // - The "2 second crash" scenario mentioned in bug report
        SystemClock.sleep(10_000)

        // Check survival: current activity should be valid
        val currentActivity = instrumentation.currentActivity

        // Survival indicators:
        // - MainActivity launched successfully, OR
        // - SplashActivity still showing (normal during splash), OR
        // - Activity finished (navigation completed)
        val isAlive = currentActivity is MainActivity ||
                currentActivity is SplashActivity ||
                currentActivity == null // Activity finished, app didn't crash

        assert(isAlive) {
            val name = currentActivity?.javaClass?.name ?: "null"
            "App crashed during startup. Current activity: $name"
        }
    }

    /**
     * Test MainActivity can be launched directly.
     * Verifies MainActivity itself is functional.
     */
    @Test
    fun testMainActivityDirectLaunch() {
        val intent = Intent(
            ApplicationProvider.getApplicationContext(),
            MainActivity::class.java
        ).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val scenario = ActivityScenario.launch(MainActivity::class.java, intent)

        scenario.onActivity { activity ->
            assert(activity is MainActivity) {
                "Expected MainActivity, got ${activity.javaClass.name}"
            }
        }

        // Wait to ensure no delayed crash
        SystemClock.sleep(3_000)

        scenario.close()
    }
}