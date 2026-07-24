#!/bin/bash

id=$(flutter devices --machine | jq -r '.[] | select(.targetPlatform | test("^android")) | .id')

if [ -z "$id" ]; then
  echo "No Android device found"
  exit 1
fi

flutter run --release -d $id
killall -9 adb
