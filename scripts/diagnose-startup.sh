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

echo "Waiting 40s for app to pass splash and finish Application.onCreate init chain..."
sleep 40

echo "::group::Process alive check"
PID="$(adb shell pidof com.simple.process | tr -d '\r')"
echo "pidof com.simple.process => [$PID]"
if [ -n "$PID" ]; then
    echo "::notice::App process is ALIVE (no startup crash)"
else
    echo "::warning::App process is GONE (startup crash suspected)"
fi
echo "::endgroup::"

# Startup diagnostics — quantify the init chain that's suspected of stalling
# the main thread. We grep the device logcat for the app PID's onCreate bookends
# and the symptoms observed in prior runs (resource id 0, blocking GC, ANR).
# These notices land in the job summary so we don't depend on a real device.
if [ -n "$PID" ]; then
    echo "::group::Application.onCreate init-chain diagnostics"
    adb logcat -d -v time > "$GITHUB_WORKSPACE/init-log.txt"
    LOG="$GITHUB_WORKSPACE/init-log.txt"

    echo "--- app onCreate bookends (PID $PID) ---"
    grep -E "\(\s*${PID}\):.*(App onCreate|attachBaseContext|TimedTaskScheduler|AutoJs isInitialized|WrappingShizuku.*onCreate|AbstractAutoJs|ScriptRuntime)" "$LOG" | head -40 || echo "(none)"

    # Stalled-input symptom: systemui ANR dialog drawn over our main interface.
    DUMP_BLOCKED=0
    if grep -qiE "ANR in com\.(simple|android\.systemui|android\.bluetooth)" "$LOG"; then
        echo "::warning::device-side ANR detected — init chain likely stalled main thread"
        grep -iE "ANR in com\." "$LOG" | sort -u | head
        DUMP_BLOCKED=1
    fi

    # The 0x00000000 resource-id error seen one line after attachBaseContext.
    if grep -qE "Invalid resource ID 0x00000000" "$LOG"; then
        echo "::warning::Invalid resource ID 0x00000000 found in app log"
        grep -E "\(\s*${PID}\):.*Invalid resource ID" "$LOG" | head -5 || true
    fi

    # Did the app actually throw a Java fatal, or was it ANR-killed / no-cb?
    if grep -qE "FATAL EXCEPTION|AndroidRuntime.*com\.simple" "$LOG"; then
        echo "::warning::Java FATAL EXCEPTION present in logcat"
    else
        echo "::notice::no Java FATAL EXCEPTION in logcat (crash, if any, is ANR-kill / resource / native — not Java Throwable)"
    fi

    # Rough onCreate wall-clock: first attachBaseContext vs last onCreate line.
    T0="$(grep -E "\(\s*${PID}\):.*attachBaseContext|Shizuku .*App attachBaseContext" "$LOG" | head -1 | sed -E 's/^([0-9-]+ [0-9:.]+).*/\1/')"
    T1="$(grep -E "\(\s*${PID}\):.*App onCreate|WrappedShizuku.*App onCreate" "$LOG" | tail -1 | sed -E 's/^([0-9-]+ [0-9:.]+).*/\1/')"
    if [ -n "$T0" ] && [ -n "$T1" ]; then
        echo "onCreate window: $T0  ->  $T1"
    else
        echo "onCreate window: could not pin both bookends (T0=$T0 T1=$T1)"
    fi
    echo "DUMP_BLOCKED=$DUMP_BLOCKED"
    echo "::endgroup::"
fi

# UI verification: only meaningful if the process survived. Dump the on-screen
# view hierarchy and confirm the "Flash Sale" (抢购) Tab — added by wiring
# SnipeFragment into MainActivity's ViewPager — actually renders. TabLayout
# renders every Tab title regardless of selection, so no simulated tap needed.
#
# If the init chain stalled the main thread enough to trip a systemui ANR,
# the emulator draws a "System UI isn't responding" dialog over our main
# interface and the dump comes back as just that dialog. Try to dismiss it
# first, then re-dump, so we don't report a false negative.
if [ -n "$PID" ]; then
    echo "::group::UI hierarchy — verify 'Flash Sale' (抢购) Tab"
    adb shell uiautomator dump /sdcard/ui_dump.xml >/dev/null 2>&1
    adb pull /sdcard/ui_dump.xml "$GITHUB_WORKSPACE/ui_dump.xml" >/dev/null 2>&1

    SNIPE_HIT=0
    [ -s "$GITHUB_WORKSPACE/ui_dump.xml" ] && grep -qE 'Flash Sale|抢购' "$GITHUB_WORKSPACE/ui_dump.xml" && SNIPE_HIT=1

    if [ "$SNIPE_HIT" = "0" ] && [ "$DUMP_BLOCKED" = "1" ]; then
        echo "Snipe Tab not visible AND systemui ANR fired — dismissing ANR dialog and re-dumping..."
        ANR_WAIT_Y=80   # near bottom of screen where the 'Wait' button sits
        adb exec-out uiautomator dump /dev/tty >/dev/null 2>&1
        # 'Wait' is typically the negative button, lower-left on the dialog.
        adb shell input tap 540 1640 >/dev/null 2>&1
        sleep 5
        adb shell uiautomator dump /sdcard/ui_dump.xml >/dev/null 2>&1
        adb pull /sdcard/ui_dump.xml "$GITHUB_WORKSPACE/ui_dump.xml" >/dev/null 2>&1
        [ -s "$GITHUB_WORKSPACE/ui_dump.xml" ] && grep -qE 'Flash Sale|抢购' "$GITHUB_WORKSPACE/ui_dump.xml" && SNIPE_HIT=1
    fi

    if [ -s "$GITHUB_WORKSPACE/ui_dump.xml" ]; then
        if [ "$SNIPE_HIT" = "1" ]; then
            echo "::notice::Tab 'Flash Sale' (抢购) IS visible in UI hierarchy"
        elif [ "$DUMP_BLOCKED" = "1" ]; then
            echo "::warning::Tab 'Flash Sale' (抢购) NOT found — main interface blocked by systemui ANR (onCreate init chain stalled main thread)"
        else
            echo "::warning::Tab 'Flash Sale' (抢购) NOT found in UI hierarchy (no ANR detected — UI may not have reached MainActivity)"
        fi
        echo "--- dump snippet (text attributes only) ---"
        grep -oE 'text="[^"]*"' "$GITHUB_WORKSPACE/ui_dump.xml" | head -60 || true
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
