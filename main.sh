#!/usr/bin/env bash
# server_report_full.sh
# Collect full inventory mapped from Windows-style fields and always write linux_inventory.csv
# Usage: just run the script (it will write linux_inventory.csv in same directory)

set -euo pipefail
IFS=$'\n\t'

# Output file in same dir as script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUTFILE="$SCRIPT_DIR/linux_inventory2.csv"

# CSV header (matches your requested list)
HEADER={
    "HostName,
    Status,
    Remark,
    Domain,
    HypervisorPresent,
    Manufactuter,
    Model,
    NumberOfLogicalProcessors,
    NumberOfProcessors,
    PartOfDomain,
    SystemFamily,
    SystemSKUNumber,
    SystemType,
    TotalPhysicalMemory (GB),
    Primary_UserName,
    BootDevice,
    BuildNumber,
    Operating_System,
    OS_InstallDate,
    OS_Manufacturer,
    OS_Name,
    OSArchitecture,
    CPU,
    MaxClockSpeed(MHz),
    CurrentClockSpeed(MHz),
    Disks,
    Number_of_Drives,
    Drives,
    Size_of_Drives,
    Graphics_Card,
    Network_Adapters,
    MacAddress,
    IP_Address,
    Total_Sockets,
    Total_Cores,
    Cores_Per_Socket,
    Last_Scan_Time"
    }
# helper to csv-quote values safely
csvq(){
  local v="${1:-}"
  v="${v//\"/\"\"}"
  printf "\"%s\"" "$v"
}

# helper: command exists
cmd_exists(){ command -v "$1" >/dev/null 2>&1; }

# gather values (best-effort; many fields require sudo/root for full info)
HOSTNAME=$(hostname -s 2>/dev/null || echo "")
STATUS="Online"
REMARK=""
DOMAIN=$(hostname -d 2>/dev/null || echo "")
if [ -z "$DOMAIN" ] && cmd_exists realm; then
  DOMAIN=$(realm list 2>/dev/null | awk '/^domain-name:/ {print $2; exit}' || echo "")
fi

# Hypervisor detection
if cmd_exists systemd-detect-virt; then
  VIRT=$(systemd-detect-virt -v 2>/dev/null || echo "none")
  HypervisorPresent=$([ "$VIRT" != "none" ] && echo "True" || echo "False")
else
  HypervisorPresent=$([ -d /proc/xen ] && echo "True" || echo "False")
fi

# dmidecode fields (may need sudo)
DMIDECODE="sudo dmidecode"
if [ "$(id -u)" -eq 0 ]; then DMIDECODE="dmidecode"; fi

MANUFACTURER=$($DMIDECODE -s system-manufacturer 2>/dev/null || echo "N/A")
MODEL=$($DMIDECODE -s system-product-name 2>/dev/null || echo "N/A")
SYSTEM_FAMILY=$($DMIDECODE -s system-family 2>/dev/null || echo "N/A")
SYSTEM_SKU=$($DMIDECODE -s system-sku 2>/dev/null || echo "N/A")
SYSTEM_TYPE=$(uname -m 2>/dev/null || echo "N/A")

# CPU and socket/core info
NUM_LOGICAL=$(nproc 2>/dev/null || echo "0")
if cmd_exists lscpu; then
  NUM_SOCKETS=$(lscpu 2>/dev/null | awk -F: '/Socket/ {gsub(/ /,"",$2); print $2; exit}' || echo "1")
  CORES_PER_SOCKET=$(lscpu 2>/dev/null | awk -F: '/Core\(s\) per socket/ {gsub(/ /,"",$2); print $2; exit}' || echo "")
  TOTAL_CORES=$(lscpu 2>/dev/null | awk -F: '/CPU\(s\)/ {gsub(/ /,"",$2); print $2; exit}' || echo "")
else
  NUM_SOCKETS=$(awk '/physical id/ {print $4}' /proc/cpuinfo 2>/dev/null | sort -u | wc -l || echo "1")
  TOTAL_CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "0")
  CORES_PER_SOCKET=$(awk -v t="$TOTAL_CORES" -v s="$NUM_SOCKETS" 'BEGIN{if(s>0) printf("%.2f",t/s); else print "0"}')
fi

# Memory
if [ -r /proc/meminfo ]; then
  MEM_KB=$(awk '/MemTotal/ {print $2; exit}' /proc/meminfo || echo 0)
  TOTAL_MEM_GB=$(awk -v m="$MEM_KB" 'BEGIN { printf "%.2f", m/1024/1024 }')
else
  TOTAL_MEM_GB="N/A"
fi

PRIMARY_USER=$(logname 2>/dev/null || echo "$(whoami)")

BOOT_DEVICE=$(findmnt -n -o SOURCE / 2>/dev/null || echo "N/A")
BUILD_NUMBER=$(uname -r 2>/dev/null || echo "N/A")

# OS info
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_NAME="$NAME"
  OS_VERSION="$VERSION"
  OS_FULL="$PRETTY_NAME"
  OS_MANUFACTURER="$ID"
else
  OS_NAME=$(uname -s)
  OS_VERSION=$(uname -r)
  OS_FULL="$OS_NAME $OS_VERSION"
  OS_MANUFACTURER="$OS_NAME"
fi

# OS install date best-effort
OS_INSTALL_DATE="N/A"
if [ -f /root/anaconda-ks.cfg ]; then
  OS_INSTALL_DATE=$(stat -c %y /root/anaconda-ks.cfg 2>/dev/null | cut -d'.' -f1 || echo "N/A")
else
  CREATION=$(stat -c %w / 2>/dev/null || echo "-")
  if [ "$CREATION" != "-" ]; then OS_INSTALL_DATE="$CREATION"; fi
fi

# License/Product key fields are Windows concepts — set N/A on Linux
# LICENSE_NAME="N/A"
# LICENSE_DESC="N/A"
# LICENSE_PRODUCT_KEY="N/A"
# PRODUCT_KEY="N/A"

OS_ARCH=$(uname -m 2>/dev/null || echo "N/A")
# REGISTERED_USER="N/A"
# WINDOWS_DIRECTORY="N/A"

# # Crypto provider info (not usually on Linux) -> N/A
# W32_CSP_NAME="N/A"
# W32_CSP_VENDOR="N/A"
# W32_CSP_VERSION="N/A"

# CPU model and clocks
CPU_MODEL=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' || echo "N/A")
CUR_CLOCK_MHZ=$(awk -F: '/cpu MHz/ {print $2; exit}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' || echo "")
MAX_CLOCK_MHZ=$(awk -F: '/cpu MHz/ {if($2>m) m=$2} END{if(m) printf("%.0f",m); else print ""}' /proc/cpuinfo 2>/dev/null || echo "$CUR_CLOCK_MHZ")
[ -z "$MAX_CLOCK_MHZ" ] && MAX_CLOCK_MHZ="$CUR_CLOCK_MHZ"

# Disks and sizes
if cmd_exists lsblk; then
  DISK_MODELS=$(lsblk -dn -o NAME,MODEL 2>/dev/null | awk '{ n=$1; $1=""; sub(/^ /,""); print n ":" $0 }' | tr '\n' ';' | sed 's/;$//')
  NUM_DRIVES=$(lsblk -dn -o NAME,TYPE 2>/dev/null | awk '$2=="disk"{count++}END{print count+0}')
  DRIVES_INFO=$(lsblk -o NAME,SIZE,MOUNTPOINT -P 2>/dev/null | tr '\n' '|' | sed 's/|$//')
  SIZE_OF_DRIVES=$(lsblk -dn -o NAME,SIZE 2>/dev/null | awk '{print $1 ":" $2}' | tr '\n' ';' | sed 's/;$//')
else
  DISK_MODELS="N/A"
  NUM_DRIVES="0"
  DRIVES_INFO="N/A"
  SIZE_OF_DRIVES="N/A"
fi

# Graphics
if cmd_exists lspci; then
  GRAPHICS=$(lspci 2>/dev/null | awk -F: '/VGA|3D controller|Display controller/ { $1=""; $2=""; print substr($0,3) }' | tr '\n' ';' | sed 's/;$//')
else
  GRAPHICS="N/A"
fi

# Network adapters, MACs, IPs
IP_ADDRS=$(ip -o -4 addr show 2>/dev/null | awk '{print $4}' | sed 's/\/.*//' | tr '\n' ';' | sed 's/;$//')
# MAC:IP pairs for interfaces with IPv4
MAC_IP_PAIRS=$(for line in $(ip -o -4 addr show 2>/dev/null); do
  iface=$(echo "$line" | awk '{print $2}')
  ip=$(echo "$line" | awk '{print $4}' | sed 's/\/.*//')
  mac=$(cat /sys/class/net/"$iface"/address 2>/dev/null || echo "")
  if [ -n "$mac" ]; then printf "%s:%s;" "$mac" "$ip"; fi
done | sed 's/;$//')
NET_ADAPTERS=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | tr '\n' ';' | sed 's/;$//')

# Sockets/cores (final fallback)
if cmd_exists lscpu; then
  TOTAL_SOCKETS=$(lscpu 2>/dev/null | awk -F: '/Socket/ {gsub(/ /,"",$2); print $2; exit}' || echo "$NUM_SOCKETS")
  if [ -z "$TOTAL_CORES" ] || [ "$TOTAL_CORES" = "" ]; then
    TOTAL_CORES=$(lscpu 2>/dev/null | awk -F: '/CPU\\(s\\)/ {gsub(/ /,"",$2); print $2; exit}' || echo "")
  fi
  if [ -z "$CORES_PER_SOCKET" ] || [ "$CORES_PER_SOCKET" = "" ]; then
    CORES_PER_SOCKET=$(lscpu 2>/dev/null | awk -F: '/Core\\(s\\) per socket/ {gsub(/ /,"",$2); print $2; exit}' || echo "")
  fi
else
  TOTAL_SOCKETS="${NUM_SOCKETS}"
  TOTAL_CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "0")
  CORES_PER_SOCKET=$(awk -v t="$TOTAL_CORES" -v s="$TOTAL_SOCKETS" 'BEGIN{if(s>0) printf("%.2f",t/s); else print "0"}')
fi

LAST_SCAN_TIME=$(date -u +"%Y-%m-%d %H:%M:%SZ")

# Build values array in same order as header
VALUES=(
  "$HOSTNAME"
  "$STATUS"
  "$REMARK"
  "$DOMAIN"
  "$HypervisorPresent"
  "$MANUFACTURER"
  "$MODEL"
  "$NUM_LOGICAL"
  "$NUM_SOCKETS"
  "$([ -n "$DOMAIN" ] && echo "True" || echo "False")"
  "$SYSTEM_FAMILY"
  "$SYSTEM_SKU"
  "$SYSTEM_TYPE"
  "$TOTAL_MEM_GB"
  "$PRIMARY_USER"
  "$BOOT_DEVICE"
  "$BUILD_NUMBER"
  "$OS_FULL"
  "$OS_INSTALL_DATE"
  "$OS_MANUFACTURER"
#   "$LICENSE_NAME"
#   "$LICENSE_DESC"
#   "$LICENSE_PRODUCT_KEY"
#   "$PRODUCT_KEY"
  "$OS_NAME"
  "$OS_ARCH"
#   "$REGISTERED_USER"
#   "$WINDOWS_DIRECTORY"
#   "$W32_CSP_NAME"
#   "$W32_CSP_VENDOR"
#   "$W32_CSP_VERSION"
  "$CPU_MODEL"
  "$MAX_CLOCK_MHZ"
  "$CUR_CLOCK_MHZ"
  "$DISK_MODELS"
  "$NUM_DRIVES"
  "$DRIVES_INFO"
  "$SIZE_OF_DRIVES"
  "$GRAPHICS"
  "$NET_ADAPTERS"
  "$MAC_IP_PAIRS"
  "$IP_ADDRS"
  "$TOTAL_SOCKETS"
  "$TOTAL_CORES"
  "$CORES_PER_SOCKET"
  "$LAST_SCAN_TIME"
)

# Compose CSV row safely
CSV_LINE=""
first=1
for v in "${VALUES[@]}"; do
  # sanitize newlines
  v="${v//$'\n'/ }"
  if [ $first -eq 1 ]; then
    CSV_LINE="$(csvq "$v")"
    first=0
  else
    CSV_LINE="$CSV_LINE,$(csvq "$v")"
  fi
done

# Write file (overwrite each run)
{
  printf "%s\n" "$HEADER"
  printf "%s\n" "$CSV_LINE"
} > "$OUTFILE"

echo "CSV generated: $OUTFILE"
