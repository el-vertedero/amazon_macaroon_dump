#!/bin/bash

# Fail script if any commands fail. Fail on use of uninitialized variables.
# Do not mask underlying failures
set -euo pipefail

archive=""

log() {                                                                                 
  if [ -n "$archive" ]; then                       
    printf '%s\n' "$@" >> ${archive}
  else                              
    printf '%s\n' "$@"              
  fi                                
}

log_file() {
  if [ -n "$archive" ]; then
    cat "$1" >> ${archive}
  else
    cat "$1"
  fi
}
 
work_dir="$1"
pushd ${work_dir}                                                                                     

if [ $# -ge 2 ]; then
  tombstones_dir="$2"

  # Create bugreport as a fake tombstone                                                                
  # Crash reports must be preppended by "crash_", followed by the epoch time, and use the .acr extension
  epoch_time=$(date +%s)                                                                                
  filename="crash_bugreport_${epoch_time}"                                                              
  archive="${tombstones_dir}/${filename}.acr.tmp"
  touch ${archive}
fi

# Provide Crash header metadata
log "CrashDescriptor:"
log "CrashType: NativeCrash"
log "Process: bugreport"
log "CrashReason:"
log "CrashTimeUTC: 0"

# Crash HAL looks for this specific string in order to create the Process tag used by spectator
process_tag="  (code_file)                     = \""
log "${process_tag}/dev/null/bugreport\""

task_delimiter_key="bugreport_task_output"

# Loop over all files in the work directory
for file in *;
do
    # Mark the start of a new plugin output section
    log "<${task_delimiter_key} file=\"${file}\">"

    # Append plugin output contents
    #cat "${file}" >> ${archive}
    log_file "${file}"

    #printf "</${task_delimiter_key}>\n" >> ${archive}
    log "</${task_delimiter_key}>"

    # Remove individual plugin output files as we go along
    rm "${file}"
done

if [ $# -ge 2 ]; then
  # Remove the .tmp extension to allow dropbox to enroll the completed bugreport archive
  mv ${archive} "${tombstones_dir}/${filename}.acr"
fi

popd
