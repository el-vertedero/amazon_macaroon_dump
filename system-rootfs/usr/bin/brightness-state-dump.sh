#!/bin/bash

# Fail script if any commands fail. Fail on use of uninitialized variables.
# Print command results to the terminal. Do not mask underlying failures
set -euxo pipefail

printf "Starting device brightness states copy script\n"

brightness_states_file="$1"
tombstones_dir="$2"

#stdout file contents
cat ${brightness_states_file}
#copy the file into tombstone directory
cp ${brightness_states_file} ${tombstones_dir}

