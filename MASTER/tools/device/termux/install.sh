#!/data/data/com.termux/files/usr/bin/bash
# Bootstrap the canonical Ubuntu installer from Termux's private home.
set -eu

fail() { printf 'master-install0: %s\n' "$*" >&2; exit 1; }
command -v pkg >/dev/null 2>&1 || fail "run this inside Termux, not Android's shell."
case "${PREFIX:-}" in
  /data/data/com.termux/files/usr|/data/user/0/com.termux/files/usr) ;;
  *) fail "unexpected Termux PREFIX; refusing to install." ;;
esac
[ "$(id -u)" != "0" ] || fail "refusing to install as root."

ROOT="${MASTER_INSTALL_DIR:-$HOME/pub5}"
REPO="https://github.com/anon987654321/pub5.git"
case "$ROOT" in "$HOME"/*) ;; *) fail "install path must be below Termux HOME." ;; esac
[ ! -L "$ROOT" ] || fail "install path must not be a symbolic link."

if ! command -v git >/dev/null 2>&1; then
  pkg update -y
  pkg install -y git
fi

if [ -d "$ROOT/.git" ]; then
  actual_origin="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
  [ "$actual_origin" = "$REPO" ] || fail "existing checkout origin does not match canonical pub5; found ${actual_origin:-<none>}."
  [ -f "$ROOT/MASTER/bin/master-mobile-install" ] || fail "existing checkout has no canonical mobile installer."
else
  [ ! -e "$ROOT" ] || fail "$ROOT exists but is not a Git checkout; move it aside and retry."
  git clone --depth 1 --branch main "$REPO" "$ROOT"
fi

MASTER_INSTALL_DIR="$ROOT" exec sh "$ROOT/MASTER/bin/master-mobile-install" --ubuntu "$@"
