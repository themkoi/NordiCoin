#!/bin/bash

flutter build apk --release

sleep 3
killall -9 java
killall -9 adb
