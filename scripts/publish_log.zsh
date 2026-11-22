#!/usr/bin/env zsh

# Use the same bounded, redacting publisher as /fix. Never send raw log bytes
# directly to a paste service from this convenience command.
publish_log() {
  local log_file="$1"
  local repo_root="${0:A:h:h}"
  local ruby_bin="${MASTER_RUBY:-ruby}"
  if [[ ! -f "$log_file" ]]; then
    print "Log file not found: $log_file" >&2
    return 1
  fi

  "$ruby_bin" -I"$repo_root/MASTER/lib" -r"$repo_root/MASTER/lib/fix/log_publication" -e '
    path = ARGV.fetch(0)
    text = File.binread(path).force_encoding(Encoding::UTF_8).scrub
    result = Master::Fix::LogPublication.publish(
      run_id: ENV.fetch("MASTER_RUN_ID", File.basename(path)),
      log_text: text
    )
    if result.url
      puts result.url
    else
      warn(result.skipped || result.error || "log publication failed")
      exit 1
    end
  ' "$log_file"
}
