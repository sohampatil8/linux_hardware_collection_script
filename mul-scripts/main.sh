#!/usr/bin/env bash
# server_report_full_ssh.sh
# Collect full Linux inventory from multiple hosts via SSH
# Input  : hosts.txt (user@host per line)
# Output : linux_inventory2.csv

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUTFILE="$SCRIPT_DIR/linux_inventory.csv"
HOSTS_FILE="$SCRIPT_DIR/hosts.txt"

# ---------------- CSV HEADER ----------------
HEADER="HostName,Status,Remark,Domain,HypervisorPresent,Manufacturer,Model,NumberOfLogicalProcessors,NumberOfProcessors,PartOfDomain,SystemFamily,SystemSKUNumber,SystemType,TotalPhysicalMemory(GB),Primary_UserName,BootDevice,BuildNumber,Operating_System,OS_InstallDate,OS_Manufacturer,OS_Name,OSArchitecture,CPU,MaxClockSpeed(MHz),CurrentClockSpeed(MHz),Disks,Number_of_Drives,Drives,Size_of_Drives,Graphics_Card,Network_Adapters,MacAddress,IP_Address,Total_Sockets,Total_Cores,Cores_Per_Socket,Threads,CPU_Sockets,CPU_Cores,CPU_Threads,Cores_Per_Socket,Last_Scan_Time"

echo "$HEADER" > "$OUTFILE"

# ---------------- CSV QUOTE ----------------
csvq() {
  local v="${1:-}"
  v="${v//\"/\"\"}"
  printf "\"%s\"" "$v"
}

# ---------------- LOOP HOSTS ----------------
while IFS= read -r target || [[ -n "$target" ]]; do
  [[ -z "$target" || "$target" =~ ^# ]] && continue

  USER="${target%@*}"
  HOST="${target#*@}"

  echo "Scanning $HOST ..."

  SSH=(ssh -n -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 "$USER@$HOST")


  if ! "${SSH[@]}" "true" >/dev/null 2>&1; then
    echo "$(csvq "$HOST"),\"Offline\",\"SSH Failed\"" >> "$OUTFILE"
    continue
  fi

  HOSTNAME=$("${SSH[@]}" "hostname -s" 2>/dev/null)
  STATUS="Online"
  REMARK=""

  DOMAIN=$("${SSH[@]}" "hostname -d" 2>/dev/null || echo "")
  PART_OF_DOMAIN=$([ -n "$DOMAIN" ] && echo "True" || echo "False")

  HypervisorPresent=$("${SSH[@]}" "systemd-detect-virt >/dev/null 2>&1 && echo True || echo False")

  MANUFACTURER=$("${SSH[@]}" "sudo dmidecode -s system-manufacturer 2>/dev/null || echo N/A")
  MODEL=$("${SSH[@]}" "sudo dmidecode -s system-product-name 2>/dev/null || echo N/A")
  SYSTEM_FAMILY=$("${SSH[@]}" "sudo dmidecode -s system-family 2>/dev/null || echo N/A")
  SYSTEM_SKU=$("${SSH[@]}" "sudo dmidecode -s system-sku 2>/dev/null || echo N/A")

  SYSTEM_TYPE=$("${SSH[@]}" "uname -m")

  NUM_LOGICAL=$("${SSH[@]}" "nproc")
  TOTAL_SOCKETS=$("${SSH[@]}" "lscpu | awk -F: '/Socket\\(s\\)/ {print \$2}' | xargs")
  CORES_PER_SOCKET=$("${SSH[@]}" "lscpu | awk -F: '/Core\\(s\\) per socket/ {print \$2}' | xargs")
  #TOTAL_CORES=$("${SSH[@]}" "lscpu | awk -F: '/CPU\\(s\\)/ {print \$2}' | xargs")
  TOTAL_CORES=$(( TOTAL_SOCKETS * CORES_PER_SOCKET ))

  TOTAL_MEM_GB=$("${SSH[@]}" "awk '/MemTotal/ {printf \"%.2f\", \$2/1024/1024}' /proc/meminfo")

  PRIMARY_USER=$("${SSH[@]}" "logname 2>/dev/null || whoami")
  BOOT_DEVICE=$("${SSH[@]}" "findmnt -n -o SOURCE /")
  BUILD_NUMBER=$("${SSH[@]}" "uname -r")

  OS_FULL=$("${SSH[@]}" "grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"'")
  OS_NAME=$("${SSH[@]}" "grep '^NAME=' /etc/os-release | cut -d= -f2 | tr -d '\"'")
  OS_MANUFACTURER=$("${SSH[@]}" "grep '^ID=' /etc/os-release | cut -d= -f2")
  OS_ARCH=$("${SSH[@]}" "uname -m")

  OS_INSTALL_DATE=$("${SSH[@]}" "stat -c %y / | cut -d'.' -f1")

  CPU_MODEL=$("${SSH[@]}" "lscpu | awk -F: '/Model name/ {print \$2}' | xargs")
  CUR_CLOCK=$("${SSH[@]}" "lscpu | awk -F: '/CPU MHz/ {print \$2; exit}' | xargs")
  MAX_CLOCK="$CUR_CLOCK"

  DISKS=$("${SSH[@]}" "lsblk -dn -o NAME,MODEL | tr '\n' ';'")
  NUM_DRIVES=$("${SSH[@]}" "lsblk -dn -o TYPE | grep -c disk")
  DRIVES=$("${SSH[@]}" "lsblk -o NAME,SIZE,MOUNTPOINT -P | tr '\n' '|'")
  SIZE_OF_DRIVES=$("${SSH[@]}" "lsblk -dn -o NAME,SIZE | tr '\n' ';'")

  GRAPHICS=$("${SSH[@]}" "lspci | grep -Ei 'VGA|3D|Display' | cut -d: -f3 | tr '\n' ';'")

  NET_ADAPTERS=$("${SSH[@]}" "ip -o link show | awk -F': ' '{print \$2}' | tr '\n' ';'")
  IP_ADDRESS=$("${SSH[@]}" "ip -o -4 addr show | awk '{print \$4}' | cut -d/ -f1 | tr '\n' ';'")
  MAC_ADDRESS=$("${SSH[@]}" "ip link | awk '/ether/ {print \$2}' | tr '\n' ';'")
# ================= CPU (ORACLE STYLE) =================
THREADS=$("${SSH[@]}" "nproc")

  CPU_Sockets=$("${SSH[@]}" "lscpu | awk -F: '/Socket\\(s\\)/ {gsub(/ /,\"\",\$2); print \$2}'")
  Cores_Per_Socket=$("${SSH[@]}" "lscpu | awk -F: '/Core\\(s\\) per socket/ {gsub(/ /,\"\",\$2); print \$2}'")
  Threads_Per_Core=$("${SSH[@]}" "lscpu | awk -F: '/Thread\\(s\\) per core/ {gsub(/ /,\"\",\$2); print \$2}'")
  CPU_Threads=$("${SSH[@]}" "lscpu | awk -F: '/^CPU\\(s\\)/ {gsub(/ /,\"\",\$2); print \$2}'")
else
  CPU_Sockets=1
  Cores_Per_Socket="$THREADS"
  Threads_Per_Core=1
  CPU_Threads="$THREADS"
fi

CPU_Cores=$(( CPU_Sockets * Cores_Per_Socket ))

HyperThreading=$(
  [ "$Threads_Per_Core" -gt 1 ] && echo "YES" || echo "NO"
)

CPU_Model=$("${SSH[@]}" "awk -F: '/model name/ {print \$2; exit}' /proc/cpuinfo | sed 's/^ *//'")
CurrentClockSpeed=$("${SSH[@]}" "awk -F: '/cpu MHz/ {print int(\$2); exit}' /proc/cpuinfo")
MaxClockSpeed=$("${SSH[@]}" "awk -F: '/cpu MHz/ {if(\$2>m)m=\$2} END{print int(m)}' /proc/cpuinfo")
#
  LAST_SCAN_TIME=$(date -u +"%Y-%m-%d %H:%M:%SZ")

  VALUES=(
    "$HOSTNAME" "$STATUS" "$REMARK" "$DOMAIN" "$HypervisorPresent"
    "$MANUFACTURER" "$MODEL" "$NUM_LOGICAL" "$TOTAL_SOCKETS"
    "$PART_OF_DOMAIN" "$SYSTEM_FAMILY" "$SYSTEM_SKU" "$SYSTEM_TYPE"
    "$TOTAL_MEM_GB" "$PRIMARY_USER" "$BOOT_DEVICE" "$BUILD_NUMBER"
    "$OS_FULL" "$OS_INSTALL_DATE" "$OS_MANUFACTURER" "$OS_NAME"
    "$OS_ARCH" "$CPU_MODEL" "$MAX_CLOCK" "$CUR_CLOCK"
    "$DISKS" "$NUM_DRIVES" "$DRIVES" "$SIZE_OF_DRIVES"
    "$GRAPHICS" "$NET_ADAPTERS" "$MAC_ADDRESS" "$IP_ADDRESS"
    "$TOTAL_SOCKETS" "$TOTAL_CORES" "$CORES_PER_SOCKET" "$THREADS"
    "$CPU_Sockets" "$CPU_Cores" "$CPU_Threads" "$Cores_Per_Socket" 
    "$LAST_SCAN_TIME"
  )

  CSV_LINE=""
  first=1
  for v in "${VALUES[@]}"; do
    v="${v//$'\n'/ }"
    if [ $first -eq 1 ]; then
      CSV_LINE="$(csvq "$v")"
      first=0
    else
      CSV_LINE="$CSV_LINE,$(csvq "$v")"
    fi
  done

  echo "$CSV_LINE" >> "$OUTFILE"

done < "$HOSTS_FILE"

echo "Inventory completed → $OUTFILE"
