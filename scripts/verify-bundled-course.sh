#!/bin/sh
# Fails the app build when content.json or release-units.json is not in the built .app.
# Copy Bundle Resources places both files at the root of the iOS app wrapper.
set -eu

app="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is not set}/${WRAPPER_NAME:?WRAPPER_NAME is not set}"
missing=0

for name in content.json release-units.json; do
  if [ ! -f "${app}/${name}" ]; then
    echo "error: ${name} is missing from the built app (${app}/${name})"
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  exit 1
fi
