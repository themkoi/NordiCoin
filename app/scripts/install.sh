#!/bin/bash

adb install -r --user 0 build/app/outputs/flutter-apk/app-release.apk
adb shell am start -n com.szybet.nordicoin/.MainActivity
adb logcat -c
adb logcat -v time -s flutter com.szybet.nordicoin
