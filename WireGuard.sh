#!/bin/bash

# ===[ Colors ]===
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

clear

# ===[ Check dependencies ]===
HAS_AWG=false
HAS_WG=false
HAS_CURL=false
HAS_JQ=false

[[ -x "$(command -v awg)" && -x "$(command -v awg-quick)" ]] && HAS_AWG=true
[[ -x "$(command -v wg)" && -x "$(command -v wg-quick)" ]] && HAS_WG=true
[[ -x "$(command -v curl)" ]] && HAS_CURL=true
[[ -x "$(command -v jq)" ]] && HAS_JQ=true

echo "${CYAN}Tool detection:${RESET}"
if $HAS_AWG; then
  echo "  AmneziaWG: ${GREEN}found${RESET}"
elif $HAS_WG; then
  echo "  WireGuard: ${GREEN}found${RESET}"
else
  echo "  AmneziaWG: ${RED}not found${RESET}"
  echo "  WireGuard: ${RED}not found${RESET}"
  echo "${RED}No supported WireGuard tools found. Exiting.${RESET}"
  exit 1
fi

[[ $HAS_CURL == true ]] && echo "  curl:      ${GREEN}found${RESET}" || echo "  curl:      ${RED}not found${RESET}"
[[ $HAS_JQ == true ]] && echo "  jq:        ${GREEN}found${RESET}" || echo "  jq:        ${RED}not found${RESET}"

if ! $HAS_CURL || ! $HAS_JQ; then
  echo "${RED}Missing required tools: curl and/or jq. Exiting.${RESET}"
  exit 1
fi

# ===[ Backend selection ]===
if $HAS_AWG; then
  WG_SHOW_CMD="awg show interfaces"
  WG_UP_CMD="awg-quick up"
  WG_DOWN_CMD="awg-quick down"
  BACKEND="AmneziaWG"
else
  WG_SHOW_CMD="wg show interfaces"
  WG_UP_CMD="wg-quick up"
  WG_DOWN_CMD="wg-quick down"
  BACKEND="WireGuard"
fi

# ===[ Banner ]===
echo ""
echo "${CYAN}===================[ ReBullet ${BACKEND} SWITCH ]====================${RESET}"

# ===[ Config directory ]===
CONFIG_DIR="/etc/amnezia/amneziawg"

# ===[ Check active interface ]===
ACTIVE_IFACE=$($WG_SHOW_CMD 2>/dev/null)

if [ -n "$ACTIVE_IFACE" ]; then
  echo ""
  echo "${BLUE}Active interface detected: ${BOLD}$ACTIVE_IFACE${RESET}"
  read -p "Do you want to deactivate it? (y/n): " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    $WG_DOWN_CMD "$ACTIVE_IFACE" &> /dev/null
    echo "${GREEN}Deactivated config: ${BOLD}$ACTIVE_IFACE${RESET}"
  else
    echo "${RED}Aborted. Exiting.${RESET}"
    exit 0
  fi
fi

# ===[ Show configs ]===
echo ""
echo "${CYAN}Available VPN configurations:${RESET}"
echo "  0) ${BOLD}Do not activate VPN${RESET}"

mapfile -t CONFIGS < <(ls "$CONFIG_DIR"/*.conf 2>/dev/null | xargs -n 1 basename | sed 's/\.conf$//')

if [ "${#CONFIGS[@]}" -eq 0 ]; then
  echo "${RED}No .conf files found in $CONFIG_DIR.${RESET}"
  exit 1
fi

for i in "${!CONFIGS[@]}"; do
  printf "  %d) %s\n" "$((i+1))" "${CONFIGS[$i]^}"
done

echo ""
read -p "Choose location by number: " choice

# ===[ Activate config ]===
if [[ "$choice" == "0" ]]; then
  echo ""
  echo "${BLUE}Skipping VPN activation.${RESET}"
else
  index=$((choice-1))
  if [ "$index" -ge 0 ] && [ "$index" -lt "${#CONFIGS[@]}" ]; then
    IFACE_NAME="${CONFIGS[$index]}"
    echo ""
    echo "${GREEN}Activating config: ${BOLD}$IFACE_NAME${RESET}"
    $WG_UP_CMD "$IFACE_NAME" &> /dev/null
  else
    echo "${RED}Invalid selection. Exiting.${RESET}"
    exit 1
  fi
fi

# ===[ IP Address Check ]===
echo ""
echo "${CYAN}IP Address Check:${RESET}"

IPV4=$(curl -4 -s ifconfig.me)
IPV6=$(curl -6 -s ifconfig.me)

[ -n "$IPV4" ] && echo "  IPv4: ${GREEN}$IPV4${RESET}" || echo "  IPv4: ${RED}Not available${RESET}"
[ -n "$IPV6" ] && echo "  IPv6: ${GREEN}$IPV6${RESET}" || echo "  IPv6: ${RED}Not available${RESET}"

# ===[ Service Country Check ]===
echo ""
echo "${CYAN}Service Country Check (IPv4 / IPv6):${RESET}"

get_service_country() {
  local name="$1"
  local v4="$2"
  local v6="$3"

  [ -n "$v4" ] && printf "  %-10s: ${GREEN}%-3s${RESET}" "$name" "$v4" || printf "  %-10s: ${RED}n/a${RESET}" "$name"
  [ -n "$v6" ] && printf "   ${GREEN}%-3s${RESET}\n" "$v6" || printf "   ${RED}n/a${RESET}\n"
}

# Cloudflare
CF_V4=$(curl -4 -s "https://www.cloudflare.com/cdn-cgi/trace" | grep loc | cut -d= -f2)
CF_V6=$(curl -6 -s "https://www.cloudflare.com/cdn-cgi/trace" | grep loc | cut -d= -f2)

# Netflix
NF_V4=$(curl -4 -sL https://www.netflix.com/ | grep -oP '"id":"\K[A-Z]{2}' | head -n1)
NF_V6=$(curl -6 -sL https://www.netflix.com/ | grep -oP '"id":"\K[A-Z]{2}' | head -n1)

# Steam
ST_V4=$(curl -4 -s https://store.steampowered.com/ | grep -o '"countrycode":"[^"]*"' | cut -d'"' -f4)
ST_V6=$(curl -6 -s https://store.steampowered.com/ | grep -o '"countrycode":"[^"]*"' | cut -d'"' -f4)

get_service_country "Cloudflare" "$CF_V4" "$CF_V6"
get_service_country "Netflix" "$NF_V4" "$NF_V6"
get_service_country "Steam" "$ST_V4" "$ST_V6"

# ===[ Ping Test ]===
echo ""
echo "${CYAN}Ping Test (5 times per host)${RESET}"

HOSTS=("1.1.1.1" "8.8.8.8" "77.88.8.8")
LABELS=("Cloudflare" "Google" "Yandex")

# Print header
printf "  %-12s %-10s %-10s %-10s\n" "Ping" "${LABELS[0]}" "${LABELS[1]}" "${LABELS[2]}"
echo "  ------------------------------------------"

# Run 5 pings
for i in {1..5}; do
  printf "  Attempt %-4s" "$i"
  for h in "${HOSTS[@]}"; do
    PING_RESULT=$(ping -c 1 -W 1 "$h" 2>/dev/null | grep "time=" | sed -E 's/.*time=([0-9.]+) ms.*/\1 ms/')
    printf " %-10s" "${PING_RESULT:-timeout}"
  done
  echo ""
done

echo ""
echo "${CYAN}=============================================================${RESET}"
