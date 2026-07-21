#!/bin/bash

flutter build apk --debug --split-per-abi --target-platform=android-arm64

mv "build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk" "build/app/outputs/flutter-apk/app-release.apk"

sleep 0.5
killall -9 java 2>/dev/null
killall -9 adb 2>/dev/null
sleep 0.5

./scripts/install.sh
