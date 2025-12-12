ssh root@192.168.1.174 '
echo "===== BASIC INFO ====="
hostnamectl

echo
echo "===== CPU ====="
lscpu

echo
echo "===== MEMORY ====="
free -h
sudo dmidecode -t memory || echo "dmidecode memory failed"

echo
echo "===== DISKS ====="
lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT,TYPE
sudo fdisk -l 2>/dev/null || echo "fdisk failed or requires sudo"

echo
echo "===== SYSTEM / BASEBOARD ====="
sudo dmidecode -t system -t baseboard || echo "dmidecode system/baseboard failed"

echo
echo "===== PCI DEVICES ====="
lspci || echo "lspci not installed"

echo
echo "===== USB DEVICES ====="
lsusb || echo "lsusb not installed"

echo
echo "===== LSHW (SUMMARY) ====="
sudo lshw -short 2>/dev/null || echo "lshw failed or not installed"
' > hardware_report_$(date +%F)_192.168.1.174.txt

