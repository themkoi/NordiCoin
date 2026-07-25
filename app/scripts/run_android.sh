#!/bin/bash

id=$(flutter devices --machine | jq -r '.[] | select(.targetPlatform | test("^android")) | .id')

if [ -z "$id" ]; then
  echo "No Android device found"
  exit 1
fi

./scripts/build_debug.sh
adb install -r --user 0 build/app/outputs/flutter-apk/app-release.apk
adb shell am start -n com.szybet.nordicoin/.MainActivity
adb logcat -v time -s flutter com.szybet.nordicoin
