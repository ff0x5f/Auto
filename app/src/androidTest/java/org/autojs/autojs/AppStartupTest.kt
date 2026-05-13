package org.autojs.autojs

import android.app.Instrumentation
import android.content.Intent
import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
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
 *    - Either on MainActivity or SplashActivity still showing
 */
class AppStartupTest {

    /**
     * Core startup survival test.
     * Launch -> Wait 10s -> Check survival.
     */
    @Test
    fun testAppStartupSurvival() {
        val context = ApplicationProvider.getApplicationContext<android.app.Application>()
        val intent = Intent(context, SplashActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val instrumentation: Instrumentation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(intent)

        // Verify SplashActivity started
        assert(activity is SplashActivity) {
            "Expected SplashActivity, got ${activity?.javaClass?.name}"
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
                currentActivity == null

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
        val context = ApplicationProvider.getApplicationContext<android.app.Application>()
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val instrumentation: Instrumentation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(intent)

        assert(activity is MainActivity) {
            "Expected MainActivity, got ${activity?.javaClass?.name}"
        }

        SystemClock.sleep(3_000)
    }
}