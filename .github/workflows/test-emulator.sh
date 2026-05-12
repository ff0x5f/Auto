#!/bin/bash
set -e

echo "=== Cleaning Environment ==="
adb logcat -c
adb shell rm /sdcard/view.xml 2>/dev/null || true

echo "=== Installing APK ==="
adb install -r app/build/outputs/apk/app/debug/simple-process-x86_64.apk

echo "=== Starting app ==="
adb shell monkey -p com.simple.process -c android.intent.category.LAUNCHER 1

echo "=== Verification Loop (60s) ==="
n=0
while [ $n -lt 60 ]; do
  sleep 2
  n=$((n + 2))
  echo "--- Check at ${n}s ---"

  # 1. Process Check
  if ! adb shell pidof com.simple.process > /dev/null; then
    echo "Process not found"
  fi

  # 2. Crash Check
  if adb logcat -d | grep -iE "FATAL|NativeCrash|has stopped|ANR|Process.*crashed" | grep -q "com.simple.process"; then
    echo "CRASH DETECTED!"
    adb logcat -d | grep -iE "FATAL|Exception|AndroidRuntime" | grep -q "com.simple.process" && echo "=== Crash Details ===" && adb logcat -d | grep -iE "FATAL|Exception" | tail -20
    exit 1
  fi

  # 3. UI Content Check
  adb shell uiautomator dump /sdcard/view.xml > /dev/null
  adb pull /sdcard/view.xml /tmp/view.xml 2>/dev/null || true

  if [ -s /tmp/view.xml ]; then
    if grep -qiE "drawer_layout|viewpager|tab_layout|explorer|plugin|task_manager|snipe" /tmp/view.xml; then
      echo "SUCCESS: App main UI detected."
      exit 0
    fi
    if grep -qiE "文件|文档|插件|任务|sample|explorer" /tmp/view.xml; then
      echo "SUCCESS: App content detected."
      exit 0
    fi
  fi
done

echo "Timeout: UI elements not found within 60s."
exit 1
