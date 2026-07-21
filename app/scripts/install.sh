#!/bin/bash

adb install build/app/outputs/flutter-apk/app-release.apk
sleep 1
killall -9 adb
sleep 1
adb shell am start -n com.example.nordicoin/.MainActivity
