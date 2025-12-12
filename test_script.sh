#!/bin/bash

OUTPUT="hardware_report1.csv"

# CSV Header
echo "Hostname,IP Address,CPU Model,Total RAM (MB),Disk Summary,OS Version" > $OUTPUT

while IFS= read -r target; do
    USER=$(echo $target | cut -d'@' -f1)
    HOST=$(echo $target | cut -d'@' -f2)

    CPU_MODEL=$(ssh -o StrictHostKeyChecking=no $USER@$HOST "lscpu | grep 'Model name:' | awk -F: '{print \$2}' | xargs")
    RAM_TOTAL=$(ssh $USER@$HOST "free -m | awk '/Mem:/ {print \$2}'")
    DISK_SUMMARY=$(ssh $USER@$HOST "lsblk -d -o NAME,SIZE | tail -n +2 | tr '\n' ' '")
    OS_VERSION=$(ssh $USER@$HOST "grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"'")
    HOSTNAME=$(ssh $USER@$HOST "hostname")

    echo "$HOSTNAME,$HOST,$CPU_MODEL,$RAM_TOTAL,\"$DISK_SUMMARY\",$OS_VERSION" >> $OUTPUT

done < hosts.txt
