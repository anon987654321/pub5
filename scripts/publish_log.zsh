#!/usr/bin/env zsh

publish_log() {
  local log_file="$1"
  if [[ -f "$log_file" ]]; then
    curl -F 'f:1=<-' ix.io < "$log_file"
  else
    print "Log file not found: $log_file" >&2
    return 1
  fi
}
