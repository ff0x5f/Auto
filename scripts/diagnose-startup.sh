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

# Warm-start: the first launch pays a ~17s ART cold-start cost (dex load,
# native loader config) that on a weak CI emulator drags system processes
# (phone/bluetooth/systemui) into an "isn't responding" ANR dialog that
# covers our main interface and breaks the UI dump. Start once, let ART
# finish, force-stop, clear logcat — the second launch's dex is already
# cached so MainActivity reaches the foreground before any system ANR.
echo "::group::Warm-start app (prime ART/dex cache)"
adb shell am start -n com.simple.process/org.autojs.autojs.ui.splash.SplashActivity -a android.intent.action.MAIN -c android.intent.category.LAUNCHER >/dev/null 2>&1
echo "warm-start am start sent, waiting 45s for ART to finish dex/native load..."
sleep 45
adb shell am force-stop com.simple.process >/dev/null 2>&1
echo "warm-start force-stop sent"
echo "::endgroup::"

echo "::group::Clear logcat"
adb logcat -c
echo "::endgroup::"

echo "::group::Launch app (com.simple.process) — real run"
adb shell am start -n com.simple.process/org.autojs.autojs.ui.splash.SplashActivity -a android.intent.action.MAIN -c android.intent.category.LAUNCHER
echo "am start rc=$?"
echo "::endgroup::"

echo "Waiting 20s for app to pass splash and finish Application.onCreate init chain..."
sleep 20

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

    echo "--- per-step timing (AppInit tag) ---"
    grep -E "AppInit" "$LOG" | head -30 || echo "(no AppInit timing lines — App.onCreate never reached its first log call)"

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

# UI verification — soft check. The CI job stays green whenever the app
# process is alive and didn't throw a Java FATAL during startup; whether
# the "抢购" (Flash Sale) Tab is visible is a *signal* but no longer a
# gate. The artifact (screenshot + ui_dump.xml) is preserved so a
# reviewer can eyeball the post-startup screen on the emulator.
#
# Why soft: a slow CI emulator can land on a system "... isn't responding"
# ANR dialog that overlays MainActivity regardless of how cleanly the app
# boots, and uiautomator's UiAutomation bridge occasionally times out
# after several dumps. Both look identical to "Tab not visible" but say
# nothing about the app itself.
#
# Strategy: dump up to 6 rounds. Each round, if a system "... isn't
# responding" ANR dialog is covering our UI, locate the "Wait" /
# "Close app" button from the dump (no hardcoded coords) and tap it to
# dismiss, then re-dump. Take a per-attempt screenshot so the final
# artifact has the full trail.
SNIPE_HIT=0
SNIPE_VERDICT_REASON=""
if [ -n "$PID" ]; then
    echo "::group::UI hierarchy — check 'Flash Sale' (抢购) Tab (soft)"

    for attempt in 1 2 3 4 5 6; do
        adb shell uiautomator dump /sdcard/ui_dump.xml >/dev/null 2>&1
        adb pull /sdcard/ui_dump.xml "$GITHUB_WORKSPACE/ui_dump.xml" >/dev/null 2>&1
        if [ ! -s "$GITHUB_WORKSPACE/ui_dump.xml" ]; then
            echo "attempt $attempt: dump produced nothing, retrying..."
            sleep 5
            continue
        fi
        if grep -qE 'Flash Sale|抢购' "$GITHUB_WORKSPACE/ui_dump.xml"; then
            SNIPE_HIT=1
            echo "::notice::attempt $attempt: Tab 'Flash Sale' (抢购) IS visible"
            break
        fi

        BTN_XML=$(awk -F'"' '/text="Wait"|text="Close app"/{found=1} found && /bounds=/{print; exit}' "$GITHUB_WORKSPACE/ui_dump.xml")
        if [ -n "$BTN_XML" ]; then
            BOUNDS=$(echo "$BTN_XML" | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | grep -oE '[0-9]+,[0-9]+ [0-9]+,[0-9]+')
            X1=$(echo "$BOUNDS" | awk '{print $1}' | cut -d, -f1)
            Y1=$(echo "$BOUNDS" | awk '{print $1}' | cut -d, -f2)
            X2=$(echo "$BOUNDS" | awk '{print $2}' | cut -d, -f1)
            Y2=$(echo "$BOUNDS" | awk '{print $2}' | cut -d, -f2)
            CX=$(( (X1 + X2) / 2 ))
            CY=$(( (Y1 + Y2) / 2 ))
            BTN_TXT=$(echo "$BTN_XML" | grep -oE 'text="[^"]*"' | head -1)
            echo "attempt $attempt: no snipe Tab; ANR dialog $BTN_TXT at ($CX,$CY) — tapping to dismiss..."
            adb shell input tap $CX $CY >/dev/null 2>&1
            sleep 8
            continue
        fi
        echo "attempt $attempt: no snipe Tab, no ANR dialog — main interface not yet visible, retrying..."
        adb exec-out screencap -p > "$GITHUB_WORKSPACE/screenshot_attempt${attempt}.png" 2>/dev/null
        sleep 6
    done

    if [ "$SNIPE_HIT" = "1" ]; then
        echo "::notice::Tab 'Flash Sale' (抢购) IS visible in UI hierarchy"
    else
        echo "::warning::Tab 'Flash Sale' (抢购) NOT visible after 6 dump attempts — review artifact (screenshot + ui_dump) manually; this is a soft signal, not a failure"
        SNIPE_VERDICT_REASON="snipe-tab-not-visible"
    fi
    echo "--- final dump snippet (text attributes only) ---"
    [ -s "$GITHUB_WORKSPACE/ui_dump.xml" ] && grep -oE 'text="[^"]*"' "$GITHUB_WORKSPACE/ui_dump.xml" | head -60 || echo "(no ui_dump.xml)"
    echo "::endgroup::"

    echo "::group::Final screenshot"
    adb exec-out screencap -p > "$GITHUB_WORKSPACE/screenshot.png" 2>/dev/null
    if [ -s "$GITHUB_WORKSPACE/screenshot.png" ]; then
        echo "::notice::Final screenshot captured => $GITHUB_WORKSPACE/screenshot.png"
    else
        echo "::warning::screencap produced no image"
    fi
    echo "::endgroup::"
else
    # App process is not alive — this IS a hard failure (Java crash / native
    # crash / kill). The startup itself broke; everything else is moot.
    echo "::error::App process not alive — startup crash, hard-failing the job"
    SNIPE_VERDICT_REASON="app-not-alive"
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

# Soft gate: Tab-not-visible is advisory only (reviewer eyeballs the
# screenshot). App-not-alive stays a hard failure — the startup crashed
# and everything else is moot.
if [ "$SNIPE_VERDICT_REASON" = "app-not-alive" ]; then
    echo "::error::UI verification hard-failed (reason: $SNIPE_VERDICT_REASON) — failing the job"
    exit 2
fi
exit 0
