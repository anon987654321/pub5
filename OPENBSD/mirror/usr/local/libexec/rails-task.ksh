#!/bin/ksh
# Root-owned dispatcher for a closed set of Rails tasks; application code runs as the app user.
set -eu
PATH=/usr/local/bin:/usr/bin:/bin
export PATH
unset RUBYOPT RUBYLIB RUBYPATH RUBYGEMS_GEMDEPS GEM_HOME GEM_PATH
unset BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_WITH BUNDLE_WITHOUT

app=${1:-}
task=${2:-}
database=${3:-}
case "$app" in
  master|brgen|amber|bsdports|mrdamascy) ;;
  *) echo "rails-task: refused unknown app: $app" >&2; exit 64 ;;
esac
case "$task" in
  bundle-check|bundle-sibling-hydrate|bundle-install|db-prepare|db-seed|db-storage-migrate|npm-cache|\
overlay-initializers|overlay-public) [[ "$#" -ne 2 ]] || exit 64 ;;
  bundle-cas-hydrate)
    [ "$#" -eq 3 ] || exit 64
    printf "%s\n" "$database" | /usr/bin/grep -Eq "^ruby([0-9]{2}|[0-9]+[.][0-9]+)\$" || exit 64
    ;;
  demo-seed) [ "$#" -eq 2 ] && { [ "$app" = brgen ] || [ "$app" = amber ]; } || exit 64 ;;
  schema-load|secondary-db-check) [ "$#" -eq 3 ] || exit 64; case "$database" in cache|queue|cable) ;; *) exit 64 ;; esac ;;
  *) echo "rails-task: refused task: $task" >&2; exit 64 ;;
esac

[[ "$(id -u)" -eq 0 ]] || { echo "rails-task: must run as root through the fixed helper" >&2; exit 77; }

# The app's production secrets live in /etc/<app>.env, which rc.d/<app> also
# sources. This only re-exported whatever SECRET_KEY_BASE the caller had, so a
# db:prepare from a clean root shell refused with "Missing secret_key_base for
# production" (vm23, 2026-11-25). Root reads it here; su -m carries it over.
env_file="/etc/$app.env"
if [[ -f $env_file && ! -L $env_file ]]; then
  set -a
  . "$env_file"
  set +a
fi

app_uid=$(/usr/bin/id -u "$app")
[ -d /home ] && [ ! -L /home ] && [ "$(stat -f %u /home)" -eq 0 ] || {
  echo "rails-task: /home must be a real root-owned directory" >&2
  exit 1
}
app_home="/home/$app"
app_dir="$app_home/app"
[ -d "$app_home" ] && [ ! -L "$app_home" ] && [ "$(stat -f %u "$app_home")" = "$app_uid" ] || {
  echo "rails-task: app home must be a real app-owned directory: $app_home" >&2
  exit 1
}
[ -d "$app_dir" ] && [ ! -L "$app_dir" ] && [ "$(stat -f %u "$app_dir")" = "$app_uid" ] || {
  echo "rails-task: app directory must be a real app-owned directory: $app_dir" >&2
  exit 1
}
app_bundle="$app_dir/.bundle"
if [ -e "$app_bundle" ] || [ -L "$app_bundle" ]; then
  [ -d "$app_bundle" ] && [ ! -L "$app_bundle" ] &&
    [ "$(stat -f %u "$app_bundle")" = "$app_uid" ] || {
      echo "rails-task: app .bundle must be a real app-owned directory" >&2
      exit 1
    }
fi
for cache_dir in "$app_home/.npm" "$app_home/.cache" "$app_home/.bundle"; do
  if [ -e "$cache_dir" ] || [ -L "$cache_dir" ]; then
    [ -d "$cache_dir" ] && [ ! -L "$cache_dir" ] &&
      [ "$(stat -f %u "$cache_dir")" = "$app_uid" ] || {
        echo "rails-task: cache path must be a real app-owned directory: $cache_dir" >&2
        exit 1
      }
  fi
done
# Database tasks must not follow a symlinked db/storage path into another
# application or a root-managed location. Missing storage is allowed only for
# the one-time db-storage-migrate operation, which may create it as the app.
if [ -e "$app_dir/db" ] || [ -L "$app_dir/db" ]; then
  [ -d "$app_dir/db" ] && [ ! -L "$app_dir/db" ] &&
    [ "$(stat -f %u "$app_dir/db")" = "$app_uid" ] || {
      echo "rails-task: db must be a real app-owned directory" >&2
      exit 1
    }
fi
if [ -e "$app_dir/storage" ] || [ -L "$app_dir/storage" ]; then
  [ -d "$app_dir/storage" ] && [ ! -L "$app_dir/storage" ] &&
    [ "$(stat -f %u "$app_dir/storage")" = "$app_uid" ] || {
      echo "rails-task: storage must be a real app-owned directory" >&2
      exit 1
    }
fi

bundle=/usr/local/bin/bundle
ruby_path=/usr/local/bin/ruby
if [ ! -x "$ruby_path" ]; then
  ruby_path=
  for candidate in /usr/local/bin/ruby[0-9]*; do
    [ -x "$candidate" ] || continue
    ruby_path=$candidate
    break
  done
fi
found_ruby=1
[ -n "$ruby_path" ] || { echo "rails-task: no system Ruby found" >&2; exit 127; }
base=${ruby_path##*/}
suffix=${base#ruby}
candidate="/usr/local/bin/bundle$suffix"
[ ! -x "$candidate" ] || bundle=$candidate
[ "$found_ruby" -eq 1 ] || { echo "rails-task: no supported system Ruby found" >&2; exit 127; }
[ -x "$bundle" ] || { echo "rails-task: no supported system Bundler found" >&2; exit 127; }

# Sibling-bundle hydration runs root-side, before the su: reading another
# application's bundle needs another uid, and the copies must land app-owned.
# A lockfile bump must not fail a deploy that could borrow same-version built
# gems from a sibling on the same box - proven by hand for brgen and mrdamascy
# on 2026-11-25 before this step existed. Nothing is compiled here; gems no
# sibling carries are left to the bounded bundle-install task.
if [[ "$task" == bundle-sibling-hydrate ]]; then
  bundle_install_root() {
    (
      export HOME="$1"
      export BUNDLE_USER_HOME="$1/.bundle"
      export BUNDLE_WITHOUT=development:test
      export RUBY_YJIT_ENABLE=0
      unset BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_WITH GEM_HOME GEM_PATH RUBYOPT RUBYLIB
      cd "$2" && "$ruby_path" -e 'require "bundler"; print Bundler.bundle_path'
    )
  }
  app_gid=$(/usr/bin/id -g "$app")
  app_root=$(bundle_install_root "$app_home" "$app_dir") || {
    echo "rails-task: cannot resolve the $app bundle install root" >&2
    exit 1
  }
  case "$app_root" in
    "$app_home"/*) ;;
    *) echo "rails-task: refusing a bundle install root outside $app_home: $app_root" >&2
       exit 1 ;;
  esac
  abi=${app_root##*/ruby/}
  [[ "$abi" != "$app_root" ]] || {
    echo "rails-task: bundle install root has no ruby version component: $app_root" >&2
    exit 1
  }
  if [[ -e "$app_root" ]]; then
    [[ -d "$app_root" && ! -L "$app_root" && "$(stat -f %u "$app_root")" = "$app_uid" ]] || {
      echo "rails-task: refusing an unsafe app bundle root: $app_root" >&2
      exit 1
    }
  else
    mkdir -p "$app_root"
    chown "$app_uid:$app_gid" "$app_home/.bundle" "$app_home/.bundle/gems" \
      "$app_home/.bundle/gems/ruby" "$app_root" 2>/dev/null || true
  fi
  needed=$("$ruby_path" -e '
    require "bundler"
    lock = Bundler::LockfileParser.new(File.read(ARGV.fetch(0)))
    lock.specs.each { |spec| puts "#{spec.name}-#{spec.version}" }
  ' "$app_dir/Gemfile.lock")
  # Sibling roots resolve once; the per-gem loop only stats files.
  sib_roots=
  for sibling in brgen amber bsdports mrdamascy master; do
    [[ "$sibling" == "$app" ]] && continue
    sib_home="/home/$sibling"
    [[ -d "$sib_home" ]] || continue
    sib_uid=$(/usr/bin/id -u "$sibling" 2>/dev/null) || continue
    sib_root=$(bundle_install_root "$sib_home" "$sib_home/app") || continue
    case "$sib_root" in "$sib_home"/*) ;; *) continue ;; esac
    # Same ABI only: a 3.3 gem directory cannot serve a 3.4 bundle.
    [[ "${sib_root##*/ruby/}" == "$abi" ]] || continue
    [[ -d "$sib_root" && ! -L "$sib_root" && "$(stat -f %u "$sib_root")" = "$sib_uid" ]] || continue
    sib_roots="$sib_roots $sib_root"
  done
  hydrated=0
  unborrowed=
  for needed_gem in $needed; do
    printf "%s\n" "$needed_gem" | grep -Eq "^[A-Za-z0-9_.+-]+$" || {
      echo "rails-task: refusing an odd lockfile spec name: $needed_gem" >&2
      exit 1
    }
    [[ -e "$app_root/specifications/$needed_gem.gemspec" ]] && continue
    source_root=
    for sib_root in $sib_roots; do
      if [[ -f "$sib_root/specifications/$needed_gem.gemspec" &&
        ! -L "$sib_root/specifications/$needed_gem.gemspec" ]]; then
        source_root=$sib_root
        break
      fi
    done
    if [[ -z "$source_root" ]]; then
      unborrowed="$unborrowed $needed_gem"
      continue
    fi
    mkdir -p "$app_root/specifications" "$app_root/gems"
    cp "$source_root/specifications/$needed_gem.gemspec" \
       "$app_root/specifications/$needed_gem.gemspec"
    chown "$app_uid:$app_gid" \
      "$app_root/specifications/$needed_gem.gemspec"
    if [[ -d "$source_root/gems/$needed_gem" &&
      ! -L "$source_root/gems/$needed_gem" ]]; then
      cp -R "$source_root/gems/$needed_gem" "$app_root/gems/$needed_gem"
      chown -R "$app_uid:$app_gid" "$app_root/gems/$needed_gem"
    fi
    for ext_dir in "$source_root"/extensions/*/*/"$needed_gem"; do
      [[ -d "$ext_dir" && ! -L "$ext_dir" ]] || continue
      rel=${ext_dir#"$source_root"/}
      mkdir -p "$app_root/${rel%/*}"
      cp -R "$ext_dir" "$app_root/$rel"
      chown -R "$app_uid:$app_gid" "$app_root/$rel"
    done
    hydrated=$((hydrated + 1))
  done
  if (( hydrated > 0 )); then
    echo "rails-task: borrowed $hydrated built gem(s) for $app from sibling bundles"
  fi
  [[ -z "$unborrowed" ]] ||
    echo "rails-task: gems no sibling carries (bounded bundle-install fills these):$unborrowed" >&2
  exit 0
fi

export SECRET_KEY_BASE

case "$task" in
  bundle-check)
    command="BUNDLE_FROZEN=true $bundle check" ;;
  bundle-install)
    # Bounded: 15 wall-clock minutes under nice for everything hydration
    # could not borrow, then a precise still-missing list instead of a
    # vague bundler backtrace. --frozen: a deploy installs exactly its
    # lockfile or refuses.
    command='nice -n 15 timeout 900 "$PUB4_TASK_BUNDLE" install --frozen --jobs 1
missing=$("$PUB4_TASK_RUBY" -e "
  require \"bundler\"
  need = Bundler.load.specs.map { |s| \"#{s.name}-#{s.version}\" }
  dir = Bundler.bundle_path.join(\"specifications\")
  have = Dir.glob(File.join(dir.to_s, \"*.gemspec\")).map { |f| File.basename(f, \".gemspec\") }
  puts (need - have).sort
")
if [[ -n "\$missing" ]]; then
  printf "rails-task: production bundle still missing:\\n%s\\n" "\$missing" >&2
  exit 1
fi
exit 0' ;;
  npm-cache)
    command="mkdir -p /home/$app/.npm /home/$app/.cache" ;;
  bundle-cas-hydrate)
    command='set -eu
cache_dir="/home/$PUB4_TASK_APP/.bundle/cache"
cas_root="/var/cache/pub4/bundle/$PUB4_TASK_CACHE_KEY/cas/sha256"
[ -d "$cache_dir" ] && [ ! -L "$cache_dir" ] && [ "$(stat -f %u "$cache_dir")" = "$PUB4_TASK_UID" ] || {
  echo "rails-task: refusing unsafe app cache directory" >&2
  exit 1
}
for dir in /var /var/cache /var/cache/pub4 /var/cache/pub4/bundle "/var/cache/pub4/bundle/$PUB4_TASK_CACHE_KEY" "$cas_root"; do
  [ -d "$dir" ] && [ ! -L "$dir" ] && [ "$(stat -f %u "$dir")" -eq 0 ] || {
    echo "rails-task: refusing unsafe CAS directory: $dir" >&2
    exit 1
  }
done
for source in "$cas_root"/*/*/*.gem; do
  [ -f "$source" ] && [ ! -L "$source" ] || continue
  [ "$(stat -f %u "$source")" -eq 0 ] && [ ! -w "$source" ] || {
    echo "rails-task: refusing writable or non-root CAS object: $source" >&2
    exit 1
  }
  name=${source##*/}
  digest=${name%.gem}
  printf "%s\n" "$digest" | /usr/bin/grep -Eq "^[0-9a-f]{64}$" || exit 1
  [ "$(sha256 -q "$source")" = "$digest" ] || {
    echo "rails-task: CAS object digest mismatch: $source" >&2
    exit 1
  }
  target="$cache_dir/$name"
  if [ -e "$target" ] || [ -L "$target" ]; then
    [ -f "$target" ] && [ ! -L "$target" ] && [ "$(stat -f %u "$target")" = "$PUB4_TASK_UID" ] || {
      echo "rails-task: refusing unsafe cache target: $target" >&2
      exit 1
    }
    [ "$(sha256 -q "$target")" = "$digest" ] || {
      echo "rails-task: existing cache object digest mismatch: $target" >&2
      exit 1
    }
    continue
  fi
  cp "$source" "$target"
done
' ;;
  db-storage-migrate)
    command='if [ ! -d db ]; then exit 0; fi
[ ! -L db ] || { echo "rails-task: refusing db symlink" >&2; exit 1; }
[ ! -L storage ] || { echo "rails-task: refusing storage symlink" >&2; exit 1; }
mkdir -p storage
for file in db/production*.sqlite3; do
  [ -f "$file" ] && [ ! -L "$file" ] || continue
  base=${file##*/}
  target="storage/$base"
  if [ -e "$target" ] || [ -L "$target" ]; then continue; fi
  mv "$file" "$target"
  printf "moved %s -> %s\\n" "$file" "$target"
done' ;;
  db-prepare)
    command="RAILS_ENV=production $bundle exec rails db:prepare" ;;
  db-seed)
    command="RAILS_ENV=production $bundle exec rails db:seed" ;;
  demo-seed)
    command="RAILS_ENV=production $bundle exec rails ${app}:demo_seed" ;;
  schema-load)
    command="DISABLE_DATABASE_ENVIRONMENT_CHECK=1 RAILS_ENV=production $bundle exec rails db:schema:load:${database}" ;;
  secondary-db-check)
    schema="/home/$app/app/db/${database}_schema.rb"
    db_file="/home/$app/app/storage/production_${database}.sqlite3"
    [ -f "$schema" ] && [ ! -L "$schema" ] && [ -s "$db_file" ] && [ ! -L "$db_file" ] || exit 1
    table=$("$ruby_path" -e 'm = File.read(ARGV.fetch(0), encoding: "UTF-8").match(/create_table "([A-Za-z_][A-Za-z0-9_]*)"/); print(m ? m[1] : "")' "$schema")
    case "$table" in
      ''|*[!A-Za-z0-9_]*|[!A-Za-z_]*) echo "rails-task: invalid schema table for $database" >&2; exit 1 ;;
    esac
    command="/usr/local/bin/sqlite3 $db_file \"select 1 from $table limit 1;\"" ;;
  overlay-initializers)
    command='shared=/home/dev/pub5/RAILS/__shared/config/initializers
target=/home/$PUB4_TASK_APP/app/config/initializers
[ -d "$shared" ] && [ ! -L "$shared" ] || exit 0
[ -d "/home/$PUB4_TASK_APP/app/config" ] && [ ! -L "/home/$PUB4_TASK_APP/app/config" ] || exit 1
if [ -e "$target" ] || [ -L "$target" ]; then
  [ -d "$target" ] && [ ! -L "$target" ] && [ "$(stat -f %u "$target")" = "$PUB4_TASK_UID" ] || exit 1
else
  mkdir -p "$target"
fi
for entry in "$shared"/* "$shared"/.[!.]*; do
  [ -e "$entry" ] || continue
  cp -R "$entry" "$target/"
done' ;;
  overlay-public)
    command='shared=/home/dev/pub5/RAILS/__shared/public
target=/home/$PUB4_TASK_APP/app/public
[ -d "$shared" ] && [ ! -L "$shared" ] || exit 0
if [ -e "$target" ] || [ -L "$target" ]; then
  [ -d "$target" ] && [ ! -L "$target" ] && [ "$(stat -f %u "$target")" = "$PUB4_TASK_UID" ] || exit 1
else
  mkdir -p "$target"
fi
for entry in "$shared"/* "$shared"/.[!.]*; do
  [ -e "$entry" ] || continue
  base=${entry##*/}
  case "$base" in
    icon.svg|icon.png|icon-192.png|apple-touch-icon.png|favicon.ico|manifest.json|manifest.webmanifest)
      [ -e "$target/$base" ] && continue
      ;;
  esac
  cp -R "$entry" "$target/"
done
shared_bin=/home/dev/pub5/RAILS/__shared/bin
target_bin=/home/$PUB4_TASK_APP/app/bin
if [ -d "$shared_bin" ] && [ ! -L "$shared_bin" ]; then
  if [ -e "$target_bin" ] || [ -L "$target_bin" ]; then
    [ -d "$target_bin" ] && [ ! -L "$target_bin" ] && [ "$(stat -f %u "$target_bin")" = "$PUB4_TASK_UID" ] || exit 1
  else
    mkdir -p "$target_bin"
  fi
  for tool in rubocop brakeman bundler-audit; do
    if [ -f "$shared_bin/$tool" ] && [ ! -L "$shared_bin/$tool" ]; then
      cp "$shared_bin/$tool" "$target_bin/$tool"
      chmod 755 "$target_bin/$tool"
    fi
  done
fi
rubocop_config=/home/dev/pub5/RAILS/__shared/.rubocop.yml
rubocop_target="/home/$PUB4_TASK_APP/app/.rubocop.yml"
if [ -f "$rubocop_config" ] && [ ! -L "$rubocop_config" ]; then
  [ ! -L "$rubocop_target" ] || { echo "rails-task: refusing .rubocop.yml symlink" >&2; exit 1; }
  cp "$rubocop_config" "$rubocop_target"
fi' ;;
esac

# A plain string, not a heredoc: see the overlay tasks above.
script="set -eu
export HOME=/home/$app
export PATH=/usr/local/bin:/usr/bin:/bin
export NPM_CONFIG_CACHE=/home/$app/.npm
export XDG_CACHE_HOME=/home/$app/.cache
export BUNDLE_USER_HOME=/home/$app/.bundle
export PUB4_TASK_APP=$app
export PUB4_TASK_UID=$app_uid
export PUB4_TASK_CACHE_KEY=$database
export PUB4_TASK_RUBY=$ruby_path
export PUB4_TASK_BUNDLE=$bundle
export PUB5_TASK_APP=$app
export PUB5_TASK_UID=$app_uid
export PUB5_TASK_CACHE_KEY=$database
export PUB5_TASK_RUBY=$ruby_path
export SECRET_KEY_BASE
unset RUBYOPT RUBYLIB RUBYPATH RUBYGEMS_GEMDEPS GEM_HOME GEM_PATH
unset BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_WITH
# Production never installs or loads the development and test groups. Only
# brgen happened to carry this in an untracked .bundle/config; amber, bsdports
# and mrdamascy demanded rubocop, selenium and brakeman at deploy (2026-11-25).
export BUNDLE_WITHOUT=development:test
# YJIT off, as rc.d runs the apps: a db:prepare with it on, beside a running
# brgen, grew until vm23 ran out of swap and stalled for 46 minutes (2026-11-25).
export RUBY_YJIT_ENABLE=0
# Bounded: 1 GB of data and 30 CPU minutes. The unbounded db:prepare above
# would have been stopped at the cap, not left to exhaust swap beside brgen.
ulimit -d 1048576
ulimit -t 1800
cd /home/$app/app
$command"
exec /usr/bin/su -m "$app" -c "$script"
