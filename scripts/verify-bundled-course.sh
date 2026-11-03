#!/bin/sh
# Fails the app build when content.json or release-units.json is not in the built .app.
# Copy Bundle Resources places both files at the root of the iOS app wrapper.
# Those paths are this phase's inputs, and the stamp is its output, so the
# user-script sandbox can read the course files and write the stamp.
set -eu

resources="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is not set}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?UNLOCALIZED_RESOURCES_FOLDER_PATH is not set}"
stamp="${DERIVED_FILE_DIR:?DERIVED_FILE_DIR is not set}/course-files-check.stamp"
missing=0

for name in content.json release-units.json; do
  if [ ! -f "${resources}/${name}" ]; then
    echo "error: ${name} is missing from the built app (${resources}/${name})"
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  exit 1
fi

touch "$stamp"
