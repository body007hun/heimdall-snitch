#!/usr/bin/env bash
set -uo pipefail

CONFIG_DIR="${HOME}/.config/heimdall-snitch"
ALIAS_FILE="${CONFIG_DIR}/aliases.tsv"
TMP_FILE="$(mktemp)"

mkdir -p "$CONFIG_DIR"

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }

add_alias() {
  local ip="$1"
  local name="$2"
  local source="${3:-manual}"

  [[ -z "$ip" || -z "$name" ]] && return

  # csak IPv4 most, egyszerűen
  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf "%s\t%s\t%s\n" "$ip" "$name" "$source" >> "$TMP_FILE"
  fi
}

collect_defaults() {
  info "Alap aliasok hozzáadása"

  add_alias "127.0.0.1" "localhost" "default"
  add_alias "1.1.1.1" "Cloudflare DNS" "default"
  add_alias "1.0.0.1" "Cloudflare DNS secondary" "default"
  add_alias "8.8.8.8" "Google DNS" "default"
  add_alias "8.8.4.4" "Google DNS secondary" "default"
  add_alias "9.9.9.9" "Quad9 DNS" "default"
  add_alias "149.112.112.112" "Quad9 DNS secondary" "default"
}

collect_hosts() {
  info "/etc/hosts olvasása"

  if [[ ! -r /etc/hosts ]]; then
    warn "/etc/hosts nem olvasható"
    return
  fi

  awk '
    /^[[:space:]]*#/ { next }
    NF >= 2 {
      ip=$1
      name=$2
      if (ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
        print ip "\t" name "\thosts"
      }
    }
  ' /etc/hosts >> "$TMP_FILE"
}

collect_tailscale() {
  info "Tailscale status olvasása"

  if ! command -v tailscale >/dev/null 2>&1; then
    warn "tailscale parancs nincs"
    return
  fi

  tailscale status 2>/dev/null | awk '
    /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {
      ip=$1
      name=$2
      if (ip != "" && name != "") {
        print ip "\t" name "\ttailscale"
      }
    }
  ' >> "$TMP_FILE"
}

collect_wireguard() {
  info "WireGuard peer nevek olvasása"

  local cmd=""

  if command -v wgshow >/dev/null 2>&1; then
    cmd="wgshow"
  elif command -v wg >/dev/null 2>&1; then
    cmd="sudo wg show"
  else
    warn "sem wgshow, sem wg parancs nincs"
    return
  fi

  # A te wgshow formátumodban:
  # peer: KEY  # név
  # allowed ips: 10.44.0.3/32
  #
  # Ebből készül:
  # 10.44.0.3    név    wireguard

  bash -c "$cmd" 2>/dev/null | awk '
    /^peer:/ {
      current_name=""

      # kommentből név
      hash=index($0, "#")
      if (hash > 0) {
        current_name=substr($0, hash+1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", current_name)
      }
      next
    }

    /^[[:space:]]*allowed ips:/ {
      line=$0
      sub(/^[[:space:]]*allowed ips:[[:space:]]*/, "", line)

      split(line, parts, ",")
      for (i in parts) {
        ip=parts[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", ip)
        sub(/\/32$/, "", ip)

        if (ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && current_name != "") {
          print ip "\t" current_name "\twireguard"
        }
      }
    }
  ' >> "$TMP_FILE"
}

write_alias_file() {
  info "Alias fájl írása: $ALIAS_FILE"

  {
    printf "# Heimdall Snitch aliases\n"
    printf "# Format: IP<TAB>Name<TAB>Source\n"
    printf "# Generated: %s\n" "$(date '+%F %T')"
    printf "#\n"
    sort -u "$TMP_FILE" | sort -V
  } > "$ALIAS_FILE"

  ok "Kész: $ALIAS_FILE"
}

show_result() {
  printf "\n"
  if command -v bat >/dev/null 2>&1; then
    bat --style=plain --language=tsv "$ALIAS_FILE"
  else
    cat "$ALIAS_FILE"
  fi
}

main() {
  : > "$TMP_FILE"

  collect_defaults
  collect_hosts
  collect_tailscale
  collect_wireguard

  write_alias_file
  show_result

  rm -f "$TMP_FILE"
}

main
