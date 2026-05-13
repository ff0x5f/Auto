#!/bin/bash
#
# test-emulator.sh - Local Android emulator testing script
# Usage: ./test-emulator.sh [--api API_LEVEL] [--avd AVD_NAME]
#
# Prerequisites:
#   - Android SDK installed with emulator
#   - AVD created (e.g., using Android Studio AVD Manager)
#   - KVM enabled for better performance (Linux only)
#

set -e

API_LEVEL=${API_LEVEL:-34}
AVD_NAME=${AVD_NAME:-"autojs_test"}
SKIP_BUILD=${SKIP_BUILD:-false}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --api)
            API_LEVEL="$2"
            shift 2
            ;;
        --avd)
            AVD_NAME="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Find Android SDK
ANDROID_HOME=${ANDROID_HOME:-"$HOME/Android/Sdk"}
if [ ! -d "$ANDROID_HOME" ]; then
    ANDROID_HOME="/usr/local/lib/android/sdk"
fi

if [ ! -d "$ANDROID_HOME" ]; then
    echo "Error: Android SDK not found at $ANDROID_HOME"
    exit 1
fi

EMULATOR="$ANDROID_HOME/emulator/emulator"

echo "=== Android Emulator Test Script ==="
echo "API Level: $API_LEVEL"
echo "AVD Name: $AVD_NAME"
echo "Android SDK: $ANDROID_HOME"
echo ""

# Build APK if not skipping
if [ "$SKIP_BUILD" = false ]; then
    echo "=== Building APK ==="
    ./gradlew :app:assembleDebug --no-daemon
    echo ""
fi

# Check if emulator is already running
EMULATOR_PID=$(pgrep -f "emulator.*$AVD_NAME" || true)
if [ -n "$EMULATOR_PID" ]; then
    echo "Emulator already running (PID: $EMULATOR_PID)"
else
    echo "=== Starting Emulator ==="

    # Enable hardware acceleration on Linux
    ACCEL_FLAG=""
    if [ "$(uname)" = "Linux" ] && [ -e /dev/kvm ]; then
        ACCEL_FLAG="-accel kvm"
        echo "KVM acceleration enabled"
    fi

    # Start emulator in headless mode
    $EMULATOR -avd "$AVD_NAME" \
        -no-window \
        -no-audio \
        -no-boot-anim \
        -gpu swiftshader_indirect \
        $ACCEL_FLAG \
        -timezone Asia/Shanghai &

    EMULATOR_PID=$!
    echo "Emulator started (PID: $EMULATOR_PID)"
fi

# Wait for emulator to boot
echo ""
echo "=== Waiting for Emulator to Boot ==="
BOOT_TIMEOUT=300
BOOTED=false

for i in $(seq 1 $BOOT_TIMEOUT); do
    if $EMULATOR -avd "$AVD_NAME" -list-avds > /dev/null 2>&1; then
        # Check if device is ready by pinging adb
        if adb shell echo "ready" > /dev/null 2>&1; then
            # Check for boot completion
            BOOT_STATUS=$(adb shell getprop sys.boot_completed 2>/dev/null || echo "")
            if [ "$BOOT_STATUS" = "1" ]; then
                echo "Emulator booted successfully"
                BOOTED=true
                break
            fi
        fi
    fi

    if [ $((i % 10)) -eq 0 ]; then
        echo "  Waiting... ($i/$BOOT_TIMEOUT seconds)"
    fi

    sleep 1
done

if [ "$BOOTED" = false ]; then
    echo "Warning: Emulator boot timeout, continuing anyway..."
fi

# Unlock screen if needed
echo ""
echo "=== Unlocking Screen ==="
adb shell input keyevent 82 2>/dev/null || true

# Install APK
echo ""
echo "=== Installing APK ==="
APK_PATH=$(find app/build/outputs/apk/app/debug -name "*.apk" | head -1)
if [ -n "$APK_PATH" ]; then
    adb install -r "$APK_PATH"
    echo "APK installed: $APK_PATH"
else
    echo "Error: No APK found in app/build/outputs/apk/app/debug/"
    exit 1
fi

# Run instrumented tests
echo ""
echo "=== Running Instrumented Tests ==="
./gradlew :app:connectedDebugAndroidTest --no-daemon
TEST_RESULT=$?

# Cleanup
echo ""
echo "=== Cleanup ==="
if [ -n "$EMULATOR_PID" ]; then
    echo "Stopping emulator (PID: $EMULATOR_PID)"
    kill $EMULATOR_PID 2>/dev/null || true
fi

echo ""
echo "=== Test Result ==="
if [ $TEST_RESULT -eq 0 ]; then
    echo "✓ All tests passed!"
else
    echo "✗ Tests failed with exit code $TEST_RESULT"
fi

exit $TEST_RESULT