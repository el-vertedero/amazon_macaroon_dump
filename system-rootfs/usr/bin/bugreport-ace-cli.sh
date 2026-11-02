#!/bin/bash

# Fail script if any commands fail. Fail on use of uninitialized variables.
# Print command results to the terminal. Do not mask underlying failures
set -euxo pipefail

printf "Starting ace cli bug report captures\n"

for ace_command in "$@"
do
    echo "Executing: $ace_command"
    eval "PATH=/usr/bin/ STEMD_LAUNCH_ENABLE=1 $ace_command"
done
