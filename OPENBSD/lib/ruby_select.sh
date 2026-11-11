# POSIX sh — sourced by sh, ksh and zsh callers alike.
#
# Prefer the generic Ruby selected by PATH. Discover versioned OpenBSD package
# names only when it is absent or below the shared compatibility floor.
# Never require a repository patch release.
#
# Sets RUBY (absolute path), RUBY_SUFFIX, BUNDLE, GEM and RUBY_CACHE_KEY.
# RUBY=/path/to/ruby in the environment is an explicit override and is checked.

_rs_find() {
  _rs_name=$1
  _rs_path=$(command -v "$_rs_name" 2>/dev/null) || _rs_path=
  case $_rs_path in
    /*) [ -x "$_rs_path" ] && { printf '%s\\n' "$_rs_path"; return 0; } ;;
  esac
  return 1
}

_rs_compatible() {
  [ -x "$1" ] || return 1
  "$1" -e 'require "rubygems"; exit(Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.3") ? 1 : 0)' >/dev/null 2>&1
}

if [ -n "${RUBY:-}" ]; then
  _rs_compatible "$RUBY" || {
    echo "ruby_select: configured Ruby is not executable or is older than 3.3: $RUBY" >&2
    return 1 2>/dev/null || exit 1
  }
else
  RUBY=$(_rs_find ruby) || RUBY=
  if [ -n "$RUBY" ] && ! _rs_compatible "$RUBY"; then
    RUBY=
  fi

  if [ -z "$RUBY" ]; then
    _rs_old_ifs=$IFS
    IFS=:
    for _rs_dir in $PATH; do
      [ -d "$_rs_dir" ] || continue
      for _rs_candidate in "$_rs_dir"/ruby[0-9]*; do
        [ -x "$_rs_candidate" ] || continue
        if _rs_compatible "$_rs_candidate"; then
          RUBY=$_rs_candidate
          break
        fi
      done
      [ -n "$RUBY" ] && break
    done
    IFS=$_rs_old_ifs
  fi
fi

if [ -z "${RUBY:-}" ]; then
  echo "ruby_select: no compatible Ruby found (requires Ruby >= 3.3)" >&2
  return 1 2>/dev/null || exit 1
fi

_rs_base=${RUBY##*/}
case $_rs_base in
  ruby*) RUBY_SUFFIX=${_rs_base#ruby} ;;
  *) RUBY_SUFFIX= ;;
esac

BUNDLE=$(_rs_find "bundle$RUBY_SUFFIX") || BUNDLE=$(_rs_find bundle) || BUNDLE=bundle
GEM=$(_rs_find "gem$RUBY_SUFFIX") || GEM=$(_rs_find gem) || GEM=gem
RUBY_CACHE_KEY=ruby$("$RUBY" -e 'print RUBY_VERSION.split(".").first(2).join' 2>/dev/null || printf '%s' "$RUBY_SUFFIX")

BUNDLE_VERSION=${BUNDLE_VERSION:-system}
export RUBY RUBY_SUFFIX BUNDLE GEM RUBY_CACHE_KEY BUNDLE_VERSION
unset _rs_name _rs_path _rs_candidate _rs_base _rs_old_ifs _rs_dir
unset -f _rs_find _rs_compatible 2>/dev/null || true
