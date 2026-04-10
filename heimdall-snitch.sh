#!/usr/bin/env bash
set -uo pipefail

APP_NAME="heimdall-snitch"
VERSION="0.2"
LOG_DIR="${HOME}/.local/share/heimdall-snitch/logs"
LOG_ENABLED=0
TAILSCALE_CGNAT="100.64.0.0/10"

# --- colors / ui -------------------------------------------------------------

bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
info()   { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn()   { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
error()  { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*"; }
ok()     { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }

pause() {
  printf '\nNyomj Entert a folytatáshoz...'
  read -r _
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

header() {
  clear
  bold "=== ${APP_NAME} v${VERSION} ==="
  printf 'Passzív hálózati megfigyelő headless Linux szerverekhez\n'
  printf 'Nem blokkol, nem nyúl tűzfalhoz, csak figyel és naplóz.\n\n'
  printf 'Logolás: '
  if [[ "$LOG_ENABLED" -eq 1 ]]; then
    printf '\033[1;32mBE\033[0m  (%s)\n\n' "$LOG_DIR"
  else
    printf '\033[1;31mKI\033[0m\n\n'
  fi
}

ensure_log_dir() {
  mkdir -p "$LOG_DIR"
}

log_file_for() {
  local slug="$1"
  ensure_log_dir
  printf '%s/%s_%s.log' "$LOG_DIR" "$slug" "$(date +%F_%H-%M-%S)"
}

run_and_maybe_log() {
  local slug="$1"
  shift
  local cmd="$*"

  printf '\n'
  info "Indítás: $cmd"

  if [[ "$LOG_ENABLED" -eq 1 ]]; then
    local logfile
    logfile="$(log_file_for "$slug")"
    info "Napló: $logfile"
    printf '\n'
    bash -c "$cmd" 2>&1 | tee -a "$logfile"
  else
    printf '\n'
    bash -c "$cmd"
  fi
}

# --- env helpers -------------------------------------------------------------

get_tailscale_iface() {
  ip -o link show 2>/dev/null | awk -F': ' '/tailscale/ {print $2; exit}'
}

get_default_iface() {
  ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
}

show_quick_status() {
  local ts_iface default_iface host
  ts_iface="$(get_tailscale_iface || true)"
  default_iface="$(get_default_iface || true)"
  host="$(hostname 2>/dev/null || printf 'unknown')"

  bold "Gyors állapot"
  printf 'Host: %s\n' "$host"
  printf 'Default interface: %s\n' "${default_iface:-n/a}"
  printf 'Tailscale interface: %s\n' "${ts_iface:-nincs}"
  printf 'Idő: %s\n' "$(date '+%F %T %Z')"
  printf '\n'
}

# --- screens ----------------------------------------------------------------

show_help() {
  header
  cat <<'EOF'
Heimdall Snitch v0.2

Mit tud?
- élő kapcsolatok figyelése
- processz és socket összerendelés
- sávszél figyelés processzenként
- DNS és általános forgalom figyelése
- tailscale fókuszú nézetek
- top talkers összesítés
- opcionális naplózás fájlba
- opcionális bpftrace connect logger

Mit NEM csinál?
- nem blokkol kapcsolatot
- nem módosít nftables/iptables szabályokat
- nem nyúl SSH-hoz, nem játssza el az OpenSnitch bohócot

Kilépés az élő nézetekből:
- watch / tcpdump / bpftrace: Ctrl+C
- nethogs: q
EOF
  pause
}

check_deps() {
  header
  show_quick_status
  bold "Függőségek ellenőrzése"
  local missing=0

  for cmd in ss lsof watch tcpdump ip awk sort uniq; do
    if need_cmd "$cmd"; then
      printf '  [OK]   %s\n' "$cmd"
    else
      printf '  [MISS] %s\n' "$cmd"
      missing=1
    fi
  done

  printf '\n'
  if need_cmd nethogs; then
    printf '  [OK]   nethogs\n'
  else
    printf '  [OPT]  nethogs nincs telepítve\n'
  fi

  if need_cmd bpftrace; then
    printf '  [OK]   bpftrace\n'
  else
    printf '  [OPT]  bpftrace nincs telepítve\n'
  fi

  printf '\n'
  if [[ "$missing" -eq 1 ]]; then
    warn "Néhány alap parancs hiányzik."
    printf 'Arch alatt:\n'
    printf '  sudo pacman -S iproute2 lsof procps-ng tcpdump gawk\n'
  else
    ok "Az alap eszközök rendben vannak."
  fi

  printf '\nOpcionális extra csomagok:\n'
  printf '  sudo pacman -S nethogs bpftrace\n'
  pause
}

show_live_connections() {
  header
  bold "Élő TCP kapcsolatok processzekkel"
  cat <<'EOF'
Magyarázat:
- ss: kernel socket állapotok
- -t: TCP
- -p: processz információ
- -n: nincs névfeloldás
EOF
  run_and_maybe_log "live_tcp" "sudo ss -tpn"
  pause
}

watch_established() {
  header
  bold "Established kapcsolatok élő figyelése"
  cat <<'EOF'
Magyarázat:
- 2 másodpercenként frissül
- csak felépült kapcsolatokat mutat
EOF
  run_and_maybe_log "watch_established" "watch -n 2 'sudo ss -tpn state established'"
  pause
}

show_lsof_connections() {
  header
  bold "Processz alapú hálózati lista (lsof)"
  cat <<'EOF'
Magyarázat:
- melyik processz melyik IP-re / portra csatlakozik
- established TCP kapcsolatok
EOF
  run_and_maybe_log "lsof_established" "sudo lsof -iTCP -sTCP:ESTABLISHED -n -P"
  pause
}

run_nethogs() {
  header
  bold "Forgalom folyamatonként (nethogs)"
  cat <<'EOF'
Magyarázat:
- interaktív nézet
- processzenként mutatja a forgalmat
- kilépés: q
EOF

  if ! need_cmd nethogs; then
    warn "A nethogs nincs telepítve."
    printf 'Telepítés Arch alatt:\n  sudo pacman -S nethogs\n'
    pause
    return
  fi

  run_and_maybe_log "nethogs" "sudo nethogs"
  pause
}

choose_iface() {
  local prompt="${1:-Melyik interfészen figyeljünk?}"
  local default_iface ts_iface iface
  default_iface="$(get_default_iface || true)"
  ts_iface="$(get_tailscale_iface || true)"

  printf '%s\n' "$prompt"
  printf '  1) any\n'
  if [[ -n "${default_iface:-}" ]]; then
    printf '  2) %s (default)\n' "$default_iface"
  fi
  if [[ -n "${ts_iface:-}" ]]; then
    printf '  3) %s (tailscale)\n' "$ts_iface"
  fi
  printf '  4) egyéni név\n'
  printf 'Választás [1]: '
  read -r iface
  iface="${iface:-1}"

  case "$iface" in
    1) printf 'any' ;;
    2) printf '%s' "${default_iface:-any}" ;;
    3) printf '%s' "${ts_iface:-any}" ;;
    4)
      printf 'Interfész neve: '
      read -r iface
      printf '%s' "${iface:-any}"
      ;;
    *) printf 'any' ;;
  esac
}

watch_dns() {
  header
  bold "DNS figyelés (tcpdump)"
  cat <<'EOF'
Magyarázat:
- DNS lekérdezéseket figyel
- jól látszik, ki milyen neveket old fel
EOF

  local iface
  iface="$(choose_iface)"
  printf '\n'
  run_and_maybe_log "dns_watch" "sudo tcpdump -i ${iface@Q} -nn port 53"
  pause
}

watch_general_traffic() {
  header
  bold "Általános forgalom figyelés (tcpdump)"
  cat <<'EOF'
Magyarázat:
- nyers hálózati forgalom névfeloldás nélkül
- adhatsz BPF szűrőt is
EOF

  local iface filter
  iface="$(choose_iface)"
  printf '\nAdj meg opcionális szűrőt (pl. host 1.1.1.1 vagy port 443), vagy hagyd üresen: '
  read -r filter

  if [[ -n "$filter" ]]; then
    run_and_maybe_log "traffic_watch" "sudo tcpdump -i ${iface@Q} -nn $filter"
  else
    run_and_maybe_log "traffic_watch" "sudo tcpdump -i ${iface@Q} -nn"
  fi

  pause
}

show_top_talkers() {
  header
  bold "Top talkers"
  cat <<'EOF'
Magyarázat:
- az ss kimenetből összesíti a peer endpointokat
- gyors képet ad arról, mely külső címek szerepelnek gyakran
EOF

  run_and_maybe_log "top_talkers" "sudo ss -tpn state established | awk 'NR>1 {print \$5}' | sed '/^\s* *$/d' | sort | uniq -c | sort -nr | head -20"
  pause
}

show_external_only() {
  header
  bold "Külső kapcsolatok (szűrt nézet)"
  cat <<'EOF'
Magyarázat:
- próbálja kiszűrni a loopback és tipikus lokális címeket
- gyorsabb áttekintés outbound irányban
EOF

  run_and_maybe_log "external_connections" "sudo ss -tpn state established | grep -Ev '127\\.0\\.0\\.1|\[::1\]|10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.' || true"
  pause
}

show_tailscale_view() {
  header
  bold "Tailscale fókuszú nézet"
  cat <<EOF
Magyarázat:
- a Tailscale CGNAT tartományára (${TAILSCALE_CGNAT}) szűr
- jó arra, hogy lásd, mi beszél a tailneten belül
EOF

  local ts_iface
  ts_iface="$(get_tailscale_iface || true)"
  if [[ -z "${ts_iface:-}" ]]; then
    warn "Nem találtam tailscale interfészt."
    pause
    return
  fi

  printf 'Talált tailscale interfész: %s\n\n' "$ts_iface"
  run_and_maybe_log "tailscale_view" "sudo ss -tpn | grep -E '100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.' || true"
  pause
}

show_listening_ports() {
  header
  bold "Figyelő portok és processzek"
  cat <<'EOF'
Magyarázat:
- nem outbound, hanem azt mutatja, mi hallgatózik a gépen
- hasznos gyors auditnak
EOF

  run_and_maybe_log "listening_ports" "sudo ss -ltnp"
  pause
}

run_bpftrace_connect() {
  header
  bold "Connect logger (bpftrace, haladó)"
  cat <<'EOF'
Magyarázat:
- a connect() rendszerhívásokat figyeli
- passzív, nem blokkol semmit
- kilépés: Ctrl+C

Megjegyzés:
A részletes címkiolvasás kernel- és bpftrace-verziófüggő, ezért ez a verzió
biztonságosan minimalista: comm + pid + fd.
EOF

  if ! need_cmd bpftrace; then
    warn "A bpftrace nincs telepítve."
    printf 'Telepítés Arch alatt:\n  sudo pacman -S bpftrace\n'
    pause
    return
  fi

  if [[ "$LOG_ENABLED" -eq 1 ]]; then
    local logfile
    logfile="$(log_file_for "bpftrace_connect")"
    info "Napló: $logfile"
    printf '\n'
    sudo bpftrace -e '
tracepoint:syscalls:sys_enter_connect
{
  printf("%s pid=%d fd=%d\\n", comm, pid, args->fd);
}
' 2>&1 | tee -a "$logfile"
  else
    sudo bpftrace -e '
tracepoint:syscalls:sys_enter_connect
{
  printf("%s pid=%d fd=%d\\n", comm, pid, args->fd);
}
'
  fi

  pause
}

show_install_notes() {
  header
  bold "Ajánlott csomagok Arch alatt"
  cat <<'EOF'
Alap:
  sudo pacman -S iproute2 lsof procps-ng tcpdump gawk

Opcionális:
  sudo pacman -S nethogs bpftrace

Eszközök:
- iproute2 -> ss
- lsof -> processz/socket összerendelés
- procps-ng -> watch
- tcpdump -> nyers hálózati megfigyelés
- nethogs -> sávszél processzenként
- bpftrace -> haladó kernel eseményfigyelés
EOF
  pause
}

show_logs_info() {
  header
  bold "Naplózás"
  cat <<EOF
A naplók könyvtára:
  $LOG_DIR

Ha a logolás be van kapcsolva, az egyszeri parancsok kimenete és több élő nézet
is mentésre kerül timestampelt fájlokba. Az interaktív programoknál ez best effort.
EOF

  if [[ -d "$LOG_DIR" ]]; then
    printf '\nLétező logok:\n\n'
    ls -lah "$LOG_DIR" 2>/dev/null || true
  else
    printf '\nMég nincs log könyvtár létrehozva.\n'
  fi

  pause
}

toggle_logging() {
  if [[ "$LOG_ENABLED" -eq 1 ]]; then
    LOG_ENABLED=0
    info "Logolás kikapcsolva."
  else
    LOG_ENABLED=1
    ensure_log_dir
    info "Logolás bekapcsolva: $LOG_DIR"
  fi
  pause
}

main_menu() {
  while true; do
    header
    show_quick_status
    cat <<'EOF'
1) Súgó / mi mire való
2) Függőségek ellenőrzése
3) Élő TCP kapcsolatok (ss)
4) Established kapcsolatok figyelése (watch + ss)
5) Processz alapú lista (lsof)
6) Forgalom folyamatonként (nethogs)
7) DNS figyelés (tcpdump)
8) Általános forgalom figyelés (tcpdump)
9) Connect logger (bpftrace, haladó)
T) Top talkers
E) Külső kapcsolatok (szűrt nézet)
S) Tailscale fókuszú nézet
L) Figyelő portok és processzek
G) Logolás BE/KI
V) Log könyvtár megnyitása / lista
I) Telepítési jegyzetek
Q) Kilépés
EOF
    printf '\nVálasztás: '
    read -r choice

    case "${choice,,}" in
      1) show_help ;;
      2) check_deps ;;
      3) show_live_connections ;;
      4) watch_established ;;
      5) show_lsof_connections ;;
      6) run_nethogs ;;
      7) watch_dns ;;
      8) watch_general_traffic ;;
      9) run_bpftrace_connect ;;
      t) show_top_talkers ;;
      e) show_external_only ;;
      s) show_tailscale_view ;;
      l) show_listening_ports ;;
      g) toggle_logging ;;
      v) show_logs_info ;;
      i) show_install_notes ;;
      q) break ;;
      *) warn "Ismeretlen menüpont."; pause ;;
    esac
  done
}

main_menu
