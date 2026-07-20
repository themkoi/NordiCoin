#!/bin/bash

cd baiky-app/

id=$(flutter devices --machine | jq -r '.[] | select(.targetPlatform | test("^android")) | .id')

flutter run --release -d $id
