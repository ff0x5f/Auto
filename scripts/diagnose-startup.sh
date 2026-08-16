#!/usr/bin/env bash
# Runs on the CI emulator (invoked via android-emulator-runner `script`).
# android-emulator-runner@v2 feeds its `script` lines to `sh -c` ONE LINE AT
# A TIME, so any multi-line control structure (if/then/fi across lines) dies
# with "Syntax error: expecting fi". To avoid that,
# .github/workflows/android.yml invokes THIS file as a single `bash scripts/...`
# line, so all the logic below runs under one bash process.
#
# Assumes `adb` targets the already-booted emulator (single device).
set +e

APK="$GITHUB_WORKSPACE/built-apk/app-debug-x86_64.apk"

if [ -f "$APK" ]; then
    echo "Resolved APK => OK $APK"
else
    echo "::error::APK not found at $APK"
    echo "workspace contents:"
    ls -la "$GITHUB_WORKSPACE/built-apk" 2>/dev/null || true
    exit 0
fi

echo "::group::Install APK"
adb install -r "$APK"
echo "adb install rc=$?"
echo "::endgroup::"

# If adb install succeeded, the package is queryable — confirm applicationId.
echo "::group::Verify install"
adb shell pm path com.simple.process
echo "pm path rc=$?"
echo "::endgroup::"

echo "::group::Clear logcat"
adb logcat -c
echo "::endgroup::"

echo "::group::Launch app (com.simple.process)"
adb shell am start -n com.simple.process/org.autojs.autojs.ui.splash.SplashActivity -a android.intent.action.MAIN -c android.intent.category.LAUNCHER
echo "am start rc=$?"
echo "::endgroup::"

echo "Waiting 12s for app to pass splash (1s) into MainActivity..."
sleep 12

echo "::group::Process alive check"
PID="$(adb shell pidof com.simple.process | tr -d '\r')"
echo "pidof com.simple.process => [$PID]"
if [ -n "$PID" ]; then
    echo "::notice::App process is ALIVE (no startup crash)"
else
    echo "::warning::App process is GONE (startup crash suspected)"
fi
echo "::endgroup::"

# UI verification: only meaningful if the process survived. Dump the on-screen
# view hierarchy and confirm the "Flash Sale" (抢购) Tab — added by wiring
# SnipeFragment into MainActivity's ViewPager — actually renders. TabLayout
# renders every Tab title regardless of selection, so no simulated tap needed.
if [ -n "$PID" ]; then
    echo "::group::UI hierarchy — verify 'Flash Sale' (抢购) Tab"
    adb shell uiautomator dump /sdcard/ui_dump.xml >/dev/null 2>&1
    adb pull /sdcard/ui_dump.xml "$GITHUB_WORKSPACE/ui_dump.xml" >/dev/null 2>&1
    if [ -s "$GITHUB_WORKSPACE/ui_dump.xml" ]; then
        if grep -qE 'Flash Sale|抢购' "$GITHUB_WORKSPACE/ui_dump.xml"; then
            echo "::notice::Tab 'Flash Sale' (抢购) IS visible in UI hierarchy"
        else
            echo "::warning::Tab 'Flash Sale' (抢购) NOT found in UI hierarchy"
            echo "--- dump snippet (text attributes only) ---"
            grep -oE 'text="[^"]*"' "$GITHUB_WORKSPACE/ui_dump.xml" | head -60 || true
        fi
    else
        echo "::warning::uiautomator dump failed (no ui_dump.xml produced)"
    fi
    echo "::endgroup::"

    echo "::group::Screenshot"
    adb exec-out screencap -p > "$GITHUB_WORKSPACE/screenshot.png" 2>/dev/null
    if [ -s "$GITHUB_WORKSPACE/screenshot.png" ]; then
        echo "::notice::Screenshot captured => $GITHUB_WORKSPACE/screenshot.png"
    else
        echo "::warning::screencap produced no image"
    fi
    echo "::endgroup::"
fi

echo "::group::logcat ERROR+FATAL (the crash stack)"
adb logcat -d *:E AndroidRuntime:E | grep -iE 'AndroidRuntime|FATAL|Exception|Caused by|at org\.autojs|at com\.simple|Process: com\.simple' || echo "(no AndroidRuntime FATAL lines found)"
echo "::endgroup::"

echo "::group::logcat full (last 250 lines)"
adb logcat -d -v time | tail -250
echo "::endgroup::"

# Persist logs to the workspace so the artifact step can upload them.
adb logcat -d -v time > "$GITHUB_WORKSPACE/full-logcat.txt"
adb logcat -d *:E AndroidRuntime:E > "$GITHUB_WORKSPACE/crash.log"
exit 0
