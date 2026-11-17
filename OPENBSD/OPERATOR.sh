#!/usr/bin/env zsh
# Copy-ready OpenBSD filesystem payload. No Ruby, rendering, templating or deletion.
# OPENBSD/mirror/<path> installs to /<path>. Operator tools live in OPENBSD/bin and lib.
set -euo pipefail
setopt extended_glob null_glob

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h}
MIRROR=${SCRIPT_DIR}/mirror
DATA=${SCRIPT_DIR}/data
BACKUP_ROOT=${OPENBSD_BACKUP_ROOT:-/var/backups/openbsd_setup}
ACTION=plan
INSTALL_DOAS=0
DOAS_NEEDED=0
RUN_ID=
LOCK_DIR=${OPENBSD_APPLY_LOCK_DIR:-/var/run/pub5-openbsd-apply.lock}
LOCK_HELD=0
typeset -a FILES CHANGED SIGNED_BEFORE
typeset -A BACKUPS
typeset -i failures=0 CRONTAB_APPLIED=0

usage() {
  print -r -- "usage: doas zsh OPENBSD/OPERATOR.sh [--plan|--apply|--verify] [--doas]"
  print -r -- "  --plan    compare tracked mirror files with vm23 (default, read-only)"
  print -r -- "  --apply   back up and install changed files, then validate/reload affected services"
  print -r -- "  --verify  require the installed filesystem and managed root cron to match"
  print -r -- "  --doas    explicitly install etc/doas.conf through validate_doas.ksh with its canary/rollback"
  print -r -- "  sshd_config is always protected from automatic replacement."
}

for arg in "$@"; do
  case "$arg" in
    --plan) ACTION=plan ;;
    --apply) ACTION=apply ;;
    --verify) ACTION=verify ;;
    --doas) INSTALL_DOAS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 -- "OPERATOR: unknown argument: $arg"; usage >&2; exit 64 ;;
  esac
done

[[ $(uname -s) == OpenBSD ]] || {
  print -u2 -- "OPERATOR: BLOCKED - this installer compares and changes the local OpenBSD host; current host is $(uname -s)"
  exit 78
}
if [[ $ACTION != plan && $(id -u) != 0 ]]; then
  print -u2 -- "OPERATOR: BLOCKED - --$ACTION must run as root (use doas)"
  exit 78
fi
if (( INSTALL_DOAS )) && [[ $ACTION != apply ]]; then
  print -u2 -- "OPERATOR: --doas is valid only with --apply"
  exit 64
fi
[[ -d $MIRROR && -d $DATA ]] || {
  print -u2 -- "OPERATOR: required OPENBSD/mirror or OPENBSD/data directory is missing"
  exit 1
}

# Only Git-tracked regular files under the four filesystem roots are eligible.
while IFS= read -r -d '' tracked; do
  rel=${tracked#OPENBSD/mirror/}
  case "$rel" in
    etc/*|home/*|usr/*|var/*) ;;
    *) print -u2 -- "OPERATOR: invalid mirror path: $rel"; exit 1 ;;
  esac
  source_file=$MIRROR/$rel
  [[ -f $source_file && ! -L $source_file ]] || {
    print -u2 -- "OPERATOR: BLOCKED - mirror source is missing, non-regular or symlinked: $rel"
    exit 1
  }
  FILES+=("$rel")
done < <(git -c safe.directory="$REPO_ROOT" -C "$REPO_ROOT" ls-files -z -- OPENBSD/mirror)

(( ${#FILES} > 0 )) || {
  print -u2 -- "OPERATOR: BLOCKED - no tracked filesystem payload found under OPENBSD/mirror"
  exit 1
}

release_apply_lock() {
  (( LOCK_HELD )) || return 0
  rm -f "$LOCK_DIR/owner"
  rmdir "$LOCK_DIR" 2>/dev/null || print -u2 -- "OPERATOR: stale lock directory remains: $LOCK_DIR"
  LOCK_HELD=0
}

acquire_apply_lock() {
  if ! mkdir -m 700 "$LOCK_DIR" 2>/dev/null; then
    print -u2 -- "OPERATOR: BLOCKED - another OpenBSD apply owns $LOCK_DIR (inspect it; do not remove a live lock)"
    return 1
  fi
  LOCK_HELD=1
  print -r -- "pid=$$ host=$(hostname) started=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$LOCK_DIR/owner" || {
    release_apply_lock
    return 1
  }
  trap release_apply_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

file_mode() {
  local rel=$1 source_file=$MIRROR/$1
  case "$rel" in
    etc/rc.d/master|etc/rc.d/brgen|etc/rc.d/amber|etc/rc.d/bsdports|etc/rc.d/mrdamascy|usr/local/sbin/*) print 555 ;;
    etc/doas.conf|etc/ssh/sshd_config) print 600 ;;
    etc/rc.d/*) print 755 ;;
    etc/daily.local|etc/weekly.local|usr/local/bin/*|usr/local/libexec/*) print 755 ;;
    home/johann/.muttrc|home/johann/.mailcap) print 600 ;;
    home/johann/bin/*) print 755 ;;
    var/nsd/zones/master/*) print 640 ;;
    *) if [[ -x $source_file ]]; then print 755; else print 644; fi ;;
  esac
}

file_owner() {
  case "$1" in
    home/johann/*) print johann:johann ;;
    var/nsd/zones/master/*) print _nsd:_nsd ;;
    *) print root:wheel ;;
  esac
}

file_matches() {
  local rel=$1 source_file=$MIRROR/$1 target=/$1 attrs owner_group owner group mode
  [[ -f $target && ! -L $target ]] || return 1
  cmp -s "$source_file" "$target" || return 1
  mode=$(file_mode "$rel")
  owner_group=$(file_owner "$rel")
  owner=${owner_group%%:*}
  group=${owner_group##*:}
  attrs=$(stat -f '%Lp:%Su:%Sg' "$target") || return 1
  [[ $attrs == "$mode:$owner:$group" ]]
}

print_plan() {
  local rel
  for rel in $FILES; do
    if [[ $rel == etc/ssh/sshd_config ]]; then
      if file_matches "$rel"; then
        print "SAME      /$rel (protected)"
      else
        print -u2 -- "PROTECTED /$rel (SSH configuration requires an out-of-band recovery path)"
        failures=1
      fi
    elif [[ $rel == etc/doas.conf ]]; then
      if file_matches "$rel"; then
        print "SAME      /$rel (protected)"
      elif (( INSTALL_DOAS )); then
        print "GUARDED   /$rel (dedicated doas canary and rollback)"
        DOAS_NEEDED=1
      else
        print -u2 -- "PROTECTED /$rel (pass --doas to use validate_doas.ksh)"
        failures=1
      fi
    elif file_matches "$rel"; then
      print "SAME      /$rel"
    else
      print "CHANGE    /$rel"
      CHANGED+=("$rel")
    fi
  done
  print "SPECIAL   root crontab: OPENBSD/data/root.crontab (merged through crontab(1), never copied to /etc)"
}

validate_payload() {
  [[ ! -f $MIRROR/etc/pf.conf ]] || /sbin/pfctl -nf "$MIRROR/etc/pf.conf"
  [[ ! -f $MIRROR/etc/relayd.conf ]] || /usr/sbin/relayd -n -f "$MIRROR/etc/relayd.conf"
  [[ ! -f $MIRROR/etc/httpd.conf ]] || /usr/sbin/httpd -n -f "$MIRROR/etc/httpd.conf"
  [[ ! -f $MIRROR/etc/mail/smtpd.conf ]] || /usr/sbin/smtpd -n -f "$MIRROR/etc/mail/smtpd.conf"
  [[ ! -f $MIRROR/etc/ssh/sshd_config ]] || /usr/sbin/sshd -t -f "$MIRROR/etc/ssh/sshd_config"
  [[ ! -f $MIRROR/var/nsd/etc/nsd.conf ]] || /usr/local/sbin/nsd-checkconf "$MIRROR/var/nsd/etc/nsd.conf"
}

no_symlink_path() {
  local path=$1 current=/ component
  local -a pieces
  pieces=(${(s:/:)path})
  for component in $pieces; do
    [[ -n $component ]] || continue
    current=${current%/}/$component
    [[ ! -L $current ]] || return 1
  done
  return 0
}

backup_signed_zones() {
  local dir=$BACKUP_ROOT/$RUN_ID/nsd-signed zone_file
  install -d -o root -g wheel -m 700 "$dir" || return 1
  SIGNED_BEFORE=(/var/nsd/zones/master/*.zone.signed(N))
  for zone_file in $SIGNED_BEFORE; do
    cp -p "$zone_file" "$dir/${zone_file:t}" || return 1
  done
}

restore_signed_zones() {
  local zone_file base dir=$BACKUP_ROOT/$RUN_ID/nsd-signed
  for zone_file in /var/nsd/zones/master/*.zone.signed(N); do
    (( ${SIGNED_BEFORE[(Ie)$zone_file]} )) || rm -f "$zone_file" || return 1
  done
  for zone_file in $SIGNED_BEFORE; do
    base=${zone_file:t}
    [[ -f $dir/$base ]] && cp -p "$dir/$base" "$zone_file" || return 1
  done
  /usr/local/sbin/nsd-control reload
}

backup_file() {
  local rel=$1 target=/$1 backup=$BACKUP_ROOT/$RUN_ID/$1
  install -d -o root -g wheel -m 700 "$backup:h"
  if [[ -e $target ]]; then
    [[ -f $target && ! -L $target ]] || {
      print -u2 -- "OPERATOR: refusing non-regular destination: $target"
      return 1
    }
    cp -p "$target" "$backup" || return 1
    cmp -s "$target" "$backup" || return 1
    BACKUPS[$rel]=$backup
  else
    BACKUPS[$rel]=MISSING
  fi
}

restore_files() {
  local rel target backup restore_failed=0 tmp
  for rel in $CHANGED; do
    target=/$rel
    backup=${BACKUPS[$rel]:-}
    [[ -n $backup ]] || continue
    if [[ $backup == MISSING ]]; then
      rm -f "$target" || restore_failed=1
    elif [[ -f $backup ]]; then
      tmp=$(mktemp "$target:h/.pub5-restore.XXXXXXXX") || { restore_failed=1; continue; }
      cp -p "$backup" "$tmp" && mv -f "$tmp" "$target" || {
        rm -f "$tmp"
        restore_failed=1
      }
    else
      restore_failed=1
    fi
  done
  return $restore_failed
}

install_one() {
  local rel=$1 source_file=$MIRROR/$1 target=/$1 owner_group owner group mode tmp
  owner_group=$(file_owner "$rel")
  owner=${owner_group%%:*}
  group=${owner_group##*:}
  mode=$(file_mode "$rel")
  no_symlink_path "$target" || {
    print -u2 -- "OPERATOR: refusing symlinked destination path: $target"
    return 1
  }
  if [[ $rel == home/johann/* ]] && ! id johann >/dev/null 2>&1; then
    print -u2 -- "OPERATOR: account johann is absent; refusing to create a home implicitly"
    return 1
  fi
  if [[ ! -d $target:h ]]; then
    install -d -o "$owner" -g "$group" -m 755 "$target:h" || return 1
  fi
  tmp=$(mktemp "$target:h/.pub5-install.XXXXXXXX") || return 1
  if ! install -o "$owner" -g "$group" -m "$mode" "$source_file" "$tmp" ||
     ! mv -f "$tmp" "$target"; then
    rm -f "$tmp"
    return 1
  fi
  print "INSTALLED /$rel ($owner:$group $mode)"
}

backup_root_crontab() {
  local backup=$BACKUP_ROOT/$RUN_ID/root.crontab error_file=$BACKUP_ROOT/$RUN_ID/root.crontab.err detail
  if crontab -l -u root > "$backup" 2> "$error_file"; then
    rm -f "$error_file"
    return 0
  fi
  detail=$(<"$error_file")
  rm -f "$error_file"
  if [[ $detail == *"no crontab for root"* ]]; then
    : > "$backup"
    return 0
  fi
  print -u2 -- "OPERATOR: cannot read root crontab safely: $detail"
  rm -f "$backup"
  return 1
}

restore_root_crontab() {
  local backup=$BACKUP_ROOT/$RUN_ID/root.crontab
  [[ -f $backup ]] || return 1
  crontab -u root "$backup" || return 1
  CRONTAB_APPLIED=0
  print "RESTORED  root crontab"
}

install_root_crontab() {
  local tracked=$DATA/root.crontab current=$BACKUP_ROOT/$RUN_ID/root.crontab merged path_line line cmdpath index work
  [[ -f $tracked && -f $current ]] || {
    print -u2 -- "OPERATOR: root crontab source or verified backup is missing"
    return 1
  }
  work=$(mktemp -d /var/db/pub5-crontab.XXXXXXXX) || return 1
  if ! chown root:wheel "$work" || ! chmod 700 "$work"; then
    rm -rf "$work"
    return 1
  fi
  merged=$work/merged
  path_line=
  while IFS= read -r line; do
    [[ $line == PATH=* ]] && { path_line=$line; break; }
  done < "$tracked"
  if [[ -n $path_line ]]; then print -r -- "$path_line" > "$merged"; else : > "$merged"; fi
  while IFS= read -r line; do
    [[ $line == PATH=* ]] && continue
    print -r -- "$line" >> "$merged"
  done < "$current"

  while IFS= read -r line; do
    [[ -z $line || $line == \#* || $line == PATH=* ]] && continue
    local -a fields
    fields=(${=line})
    if [[ ${fields[1]} == @* ]]; then
      (( ${#fields} >= 2 )) || {
        print -u2 -- "OPERATOR: malformed tracked cron entry: $line"
        rm -rf "$work"
        return 1
      }
      index=2
    else
      (( ${#fields} >= 6 )) || {
        print -u2 -- "OPERATOR: malformed tracked cron entry: $line"
        rm -rf "$work"
        return 1
      }
      index=6
    fi
    cmdpath=
    while (( index <= ${#fields} )); do
      if [[ ${fields[index]} == /* ]]; then cmdpath=${fields[index]}; break; fi
      (( index++ ))
    done
    [[ -n $cmdpath && -x $cmdpath ]] || {
      print -u2 -- "OPERATOR: tracked cron command is missing or not executable: $line"
      rm -rf "$work"
      return 1
    }
    cron_has_command "$cmdpath" "$merged" || print -r -- "$line" >> "$merged"
  done < "$tracked"

  if ! crontab -u root "$merged"; then
    rm -rf "$work"
    return 1
  fi
  CRONTAB_APPLIED=1
  rm -rf "$work"
}

cron_has_command() {
  local command=$1 file=$2
  awk -v command="$command" '
    /^([[:space:]]*#|[[:space:]]*$)/ { next }
    {
      start = ($1 ~ /^@/) ? 2 : 6
      for (i = start; i <= NF; i++) if ($i == command) found = 1
    }
    END { exit(found ? 0 : 1) }
  ' "$file"
}

verify_root_crontab() {
  local tracked=$DATA/root.crontab live line cmdpath index expected_path live_path
  [[ -f $tracked ]] || return 1
  live=$(mktemp /tmp/pub5-crontab.XXXXXXXX) || return 1
  local error_file
  error_file=$(mktemp /tmp/pub5-crontab-error.XXXXXXXX) || { rm -f "$live"; return 1; }
  if ! crontab -l -u root > "$live" 2>"$error_file"; then
    local detail
    detail=$(<"$error_file")
    if [[ $detail == *"no crontab for root"* ]]; then
      : > "$live"
    else
      print -u2 -- "DRIFT     cannot read root crontab: $detail"
      rm -f "$error_file" "$live"
      return 1
    fi
  fi
  rm -f "$error_file"
  expected_path=
  while IFS= read -r line; do
    [[ $line == PATH=* ]] && { expected_path=$line; break; }
  done < "$tracked"
  live_path=
  while IFS= read -r line; do
    [[ $line == PATH=* ]] && { live_path=$line; break; }
  done < "$live"
  if [[ -n $expected_path && $expected_path != $live_path ]]; then
    print -u2 -- "DRIFT     root crontab PATH assignment differs"
    rm -f "$live"
    return 1
  fi
  while IFS= read -r line; do
    [[ -z $line || $line == \#* || $line == PATH=* ]] && continue
    local -a fields
    fields=(${=line})
    index=6
    [[ ${fields[1]} == @* ]] && index=2
    cmdpath=
    while (( index <= ${#fields} )); do
      if [[ ${fields[index]} == /* ]]; then cmdpath=${fields[index]}; break; fi
      (( index++ ))
    done
    if [[ -z $cmdpath ]] || ! cron_has_command "$cmdpath" "$live"; then
      print -u2 -- "DRIFT     root crontab missing $cmdpath"
      rm -f "$live"
      return 1
    fi
  done < "$tracked"
  rm -f "$live"
  print "SAME      managed root-crontab entries"
}

case "$ACTION" in
  plan)
    [[ ! -d $LOCK_DIR ]] || { print -u2 -- "OPERATOR: BLOCKED - apply lock is active: $LOCK_DIR"; exit 75; }
    print "OPENBSD mirror plan (read-only; source paths map directly to /)"
    print_plan
    (( failures == 0 )) || exit 78
    ;;
  verify)
    [[ ! -d $LOCK_DIR ]] || { print -u2 -- "OPERATOR: BLOCKED - apply lock is active: $LOCK_DIR"; exit 75; }
    print "OPENBSD mirror verification"
    print_plan
    verify_root_crontab || failures=1
    (( failures == 0 )) || exit 1
    ;;
  apply)
    print "OPENBSD mirror apply"
    print_plan
    if (( DOAS_NEEDED && ${#CHANGED} )); then
      print -u2 -- "OPERATOR: BLOCKED - --doas may only change doas.conf by itself; apply other mirror changes separately"
      exit 78
    fi
    (( failures == 0 )) || {
      print -u2 -- "OPERATOR: BLOCKED - protected or invalid mirror differences must be handled separately"
      exit 78
    }
    validate_payload || {
      print -u2 -- "OPERATOR: BLOCKED - native OpenBSD configuration validation failed; nothing was copied"
      exit 1
    }
    acquire_apply_lock || exit 75
    RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)-$$
    install -d -o root -g wheel -m 700 "$BACKUP_ROOT/$RUN_ID"
    # Every recovery input is captured and verified before the first live write.
    for rel in $CHANGED; do
      backup_file "$rel" || {
        print -u2 -- "OPERATOR: backup failed for /$rel; nothing was installed"
        exit 1
      }
    done
    backup_root_crontab || {
      print -u2 -- "OPERATOR: root crontab backup failed; nothing was installed"
      exit 1
    }
    for rel in $CHANGED; do
      install_one "$rel" || {
        print -u2 -- "OPERATOR: install failed for /$rel"
        restore_files || print -u2 -- "DELIVERY_FAILED: automatic file restoration failed"
        exit 1
      }
    done
    for rel in $CHANGED; do
      file_matches "$rel" || {
        print -u2 -- "OPERATOR: installed file did not verify: /$rel"
        restore_files || print -u2 -- "DELIVERY_FAILED: automatic file restoration failed"
        exit 1
      }
    done
    install_root_crontab || {
      print -u2 -- "OPERATOR: root crontab merge failed"
      if (( CRONTAB_APPLIED )); then
        restore_root_crontab || { print -u2 -- "DELIVERY_FAILED: root crontab restoration failed"; exit 1; }
      fi
      restore_files || print -u2 -- "DELIVERY_FAILED: automatic file restoration failed"
      exit 1
    }
    verify_root_crontab || {
      print -u2 -- "OPERATOR: root crontab read-back verification failed"
      restore_root_crontab || { print -u2 -- "DELIVERY_FAILED: root crontab restoration failed"; exit 1; }
      restore_files || print -u2 -- "DELIVERY_FAILED: automatic file restoration failed"
      exit 1
    }
    if (( ${CHANGED[(Ie)etc/pf.conf]} )); then
      /sbin/pfctl -nf /etc/pf.conf && /sbin/pfctl -f /etc/pf.conf || failures=1
    fi
    if (( failures == 0 && ${CHANGED[(Ie)etc/relayd.conf]} )); then
      /usr/sbin/rcctl restart relayd || failures=1
    fi
    if (( failures == 0 && ${CHANGED[(Ie)etc/httpd.conf]} )); then
      /usr/sbin/rcctl restart httpd || failures=1
    fi
    if (( failures == 0 && ${CHANGED[(Ie)etc/mail/smtpd.conf]} )); then
      /usr/sbin/rcctl restart smtpd || failures=1
    fi
    if (( failures == 0 && ${CHANGED[(Ie)var/nsd/etc/nsd.conf]} )); then
      /usr/sbin/rcctl restart nsd || failures=1
    fi
    if (( failures == 0 && ${CHANGED[(I)var/nsd/zones/master/*.zone]} )); then
      if backup_signed_zones; then
        /usr/local/bin/nsd-resign || failures=1
      else
        failures=1
      fi
    fi
    if (( failures )); then
      print -u2 -- "OPERATOR: activation failed; restoring the previous tracked files"
      if (( CRONTAB_APPLIED )); then
        restore_root_crontab || { print -u2 -- "DELIVERY_FAILED: root crontab restoration failed"; exit 1; }
      fi
      restore_files || { print -u2 -- "DELIVERY_FAILED: automatic file restoration failed"; exit 1; }
      if (( ${#SIGNED_BEFORE} )) || [[ -d $BACKUP_ROOT/$RUN_ID/nsd-signed ]]; then
        restore_signed_zones || { print -u2 -- "DELIVERY_FAILED: DNSSEC signature restoration failed"; exit 1; }
      fi
      [[ ${CHANGED[(Ie)etc/pf.conf]} -gt 0 ]] && /sbin/pfctl -f /etc/pf.conf || :
      [[ ${CHANGED[(Ie)etc/relayd.conf]} -gt 0 ]] && /usr/sbin/rcctl restart relayd || :
      [[ ${CHANGED[(Ie)etc/httpd.conf]} -gt 0 ]] && /usr/sbin/rcctl restart httpd || :
      [[ ${CHANGED[(Ie)etc/mail/smtpd.conf]} -gt 0 ]] && /usr/sbin/rcctl restart smtpd || :
      [[ ${CHANGED[(Ie)var/nsd/etc/nsd.conf]} -gt 0 ]] && /usr/sbin/rcctl restart nsd || :
      exit 1
    fi
    if (( DOAS_NEEDED )); then
      if ! "$SCRIPT_DIR/bin/validate_doas.ksh" install "$MIRROR/etc/doas.conf" "pub5-openbsd"; then
        print -u2 -- "OPERATOR: guarded doas configuration change failed (helper restored the prior policy)"
        restore_root_crontab || { print -u2 -- "DELIVERY_FAILED: root crontab restoration failed"; exit 1; }
        exit 1
      fi
    fi
    print "PASS      OPENBSD filesystem mirror applied"
    print "BACKUP    $BACKUP_ROOT/$RUN_ID"
    ;;
esac
