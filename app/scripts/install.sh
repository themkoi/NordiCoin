#!/bin/bash

adb install --user 0 build/app/outputs/flutter-apk/app-release.apk

#adb shell monkey -p com.szybet.nordicoin 1
adb shell am start -n com.szybet.nordicoin/.MainActivity

sleep 1
killall -9 adb
sleep 1
