#!/bin/bash

flutter build apk --release --split-per-abi --target-platform=android-arm64

mv "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" "build/app/outputs/flutter-apk/app-release.apk"

sleep 1
killall -9 java
killall -9 adb
sleep 1
