#!/usr/bin/env bash
set -euo pipefail

APP_NAME="heimdall-snitch"
VERSION="0.1"

# --- basic ui helpers --------------------------------------------------------

bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
info()   { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn()   { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
error()  { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*"; }

pause() {
  printf '\nNyomj Entert a folytatáshoz...'
  read -r _
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run_cmd() {
  local cmd="$1"
  info "Indítás: $cmd"
  printf '\n'
  bash -c "$cmd"
}

header() {
  clear
  bold "=== ${APP_NAME} v${VERSION} ==="
  printf 'Passzív hálózati megfigyelő headless Linux szerverekhez\n'
  printf 'Nem blokkol, nem okoskodik, csak les.\n\n'
}

show_help() {
  header
  cat <<'EOF'
Mit tud ez a script?

1) Élő kapcsolatok (ss)
   Megmutatja az aktív TCP kapcsolatokat és a hozzájuk tartozó processzeket.

2) Established kapcsolatok figyelése (watch + ss)
   Kétmásodpercenként frissülő nézet arról, mi kommunikál éppen.

3) Processz alapú hálózati lista (lsof)
   Megmutatja, melyik PID milyen socketet használ.

4) Forgalom folyamatonként (nethogs)
   Interaktív nézet arról, melyik processz mennyi hálózati forgalmat használ.

5) DNS figyelés (tcpdump)
   DNS lekérdezések figyelése. Jó arra, hogy lásd, ki milyen neveket old fel.

6) Általános forgalom figyelés (tcpdump)
   Nyers csomagszintű figyelés.

7) Connect logger (bpftrace)
   Opcionális, haladó. A connect() hívásokat logolja processz szinten.

Ez a script nem módosít tűzfalszabályt, nem tilt le kapcsolatot, nem nyúl nftables/iptables alá.
EOF
  pause
}

check_deps() {
  header
  bold "Függőségek ellenőrzése"
  local missing=0

  for cmd in ss lsof watch tcpdump; do
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
    warn "Néhány kötelező parancs hiányzik."
    printf 'Arch alatt javaslat:\n'
    printf '  sudo pacman -S iproute2 lsof procps-ng tcpdump\n'
  else
    info "Az alap cuccok rendben vannak."
  fi

  printf '\n'
  printf 'Opcionális extra csomagok:\n'
  printf '  sudo pacman -S nethogs bpftrace\n'

  pause
}

show_live_connections() {
  header
  bold "Élő TCP kapcsolatok processzekkel"
  cat <<'EOF'
Magyarázat:
- ss: a kernel socket állapotait mutatja
- -t: TCP
- -p: processz információ
- -n: ne oldjon neveket, gyorsabb és tisztább
EOF
  printf '\n'
  run_cmd "sudo ss -tpn"
  pause
}

watch_established() {
  header
  bold "Established kapcsolatok élő figyelése"
  cat <<'EOF'
Magyarázat:
- 2 másodpercenként frissül
- csak a már felépült kapcsolatokat mutatja
- Ctrl+C-vel kiléphetsz
EOF
  printf '\n'
  run_cmd "watch -n 2 'sudo ss -tpn state established'"
  pause
}

show_lsof_connections() {
  header
  bold "Processz alapú hálózati lista (lsof)"
  cat <<'EOF'
Magyarázat:
- melyik processz melyik IP-re / portra csatlakozik
- established TCP nézet
EOF
  printf '\n'
  run_cmd "sudo lsof -iTCP -sTCP:ESTABLISHED -n -P"
  pause
}

run_nethogs() {
  header
  bold "Forgalom folyamatonként (nethogs)"
  cat <<'EOF'
Magyarázat:
- interaktív nézet
- valós időben látod, melyik processz mennyi sávszélt használ
- kilépés: q
EOF
  printf '\n'

  if ! need_cmd nethogs; then
    warn "A nethogs nincs telepítve."
    printf 'Telepítés Arch alatt:\n'
    printf '  sudo pacman -S nethogs\n'
    pause
    return
  fi

  run_cmd "sudo nethogs"
  pause
}

watch_dns() {
  header
  bold "DNS figyelés (tcpdump)"
  cat <<'EOF'
Magyarázat:
- DNS forgalmat figyel
- jól látszik, melyik szolgáltatás mit próbál feloldani
- Ctrl+C-vel kiléphetsz
EOF
  printf '\n'

  printf 'Melyik interfészen figyeljünk? [alapértelmezett: any]: '
  read -r iface
  iface="${iface:-any}"

  run_cmd "sudo tcpdump -i ${iface@Q} -nn port 53"
  pause
}

watch_general_traffic() {
  header
  bold "Általános forgalom figyelés (tcpdump)"
  cat <<'EOF'
Magyarázat:
- nyers hálózati forgalmat mutat
- névfeloldás nélkül (-nn), így gyorsabb és kevésbé zajos
- Ctrl+C-vel kiléphetsz
EOF
  printf '\n'

  printf 'Melyik interfészen figyeljünk? [alapértelmezett: any]: '
  read -r iface
  iface="${iface:-any}"

  printf 'Adj meg opcionális szűrőt (pl. host 1.1.1.1 vagy port 443), vagy hagyd üresen: '
  read -r filter

  if [[ -n "$filter" ]]; then
    run_cmd "sudo tcpdump -i ${iface@Q} -nn $filter"
  else
    run_cmd "sudo tcpdump -i ${iface@Q} -nn"
  fi

  pause
}

run_bpftrace_connect() {
  header
  bold "Connect logger (bpftrace)"
  cat <<'EOF'
Magyarázat:
- haladó mód
- a connect() rendszerhívásokat figyeli
- processz szinten megmutatja, ki próbál kapcsolatot nyitni
- ez passzív, nem blokkol semmit
- kilépés: Ctrl+C

Megjegyzés:
A pontos mezők kernel- és bpftrace-verziófüggők lehetnek.
Ha ez a rész hibázik, az nem tragédia, csak a rendszer mondja, hogy ma nincs ilyen buli.
EOF
  printf '\n'

  if ! need_cmd bpftrace; then
    warn "A bpftrace nincs telepítve."
    printf 'Telepítés Arch alatt:\n'
    printf '  sudo pacman -S bpftrace\n'
    pause
    return
  fi

  sudo bpftrace -e '
tracepoint:syscalls:sys_enter_connect
{
  printf("%s pid=%d fd=%d\n", comm, pid, args->fd);
}
'
  pause
}

show_install_notes() {
  header
  bold "Ajánlott csomagok Arch alatt"
  cat <<'EOF'
Alap:
  sudo pacman -S iproute2 lsof procps-ng tcpdump

Opcionális:
  sudo pacman -S nethogs bpftrace

Megjegyzés:
- iproute2 -> ss
- lsof -> processz/socket összerendelés
- procps-ng -> watch
- tcpdump -> nyers hálózati megfigyelés
- nethogs -> sávszél processzenként
- bpftrace -> haladó, kernel eseményfigyelés
EOF
  pause
}

main_menu() {
  while true; do
    header
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
      i) show_install_notes ;;
      q) break ;;
      *) warn "Ismeretlen menüpont."; pause ;;
    esac
  done
}

main_menu
