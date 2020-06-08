#!/bin/bash
# Author: Yevgeniy Goncharov aka xck, http://sys-adm.in
# Collect & Check Linux server status

# Sys env / paths / etc
# -------------------------------------------------------------------------------------------\
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
SCRIPT_PATH=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)

# Notify in colors
# ---------------------------------------------------\
HOSTNAME=`hostname`
SERVER_IP=`hostname -I`
MOUNT=$(mount|egrep -iw "ext4|ext3|xfs|gfs|gfs2|btrfs"|grep -v "loop"|sort -u -t' ' -k1,2)
FS_USAGE=$(df -PTh|egrep -iw "ext4|ext3|xfs|gfs|gfs2|btrfs"|grep -v "loop"|sort -k6n|awk '!seen[$1]++')
SERVICES="$SCRIPT_PATH/services-list.txt"
TESTFILE="$SCRIPT_PATH/tempfile"

on_success="DONE"
on_fail="FAIL"
white="\e[1;37m"
green="\e[1;32m"
red="\e[1;31m"
purple="\033[1;35m"
nc="\e[0m"

SuccessMark="\e[47;32m ------ OK \e[0m"
WarningMark="\e[43;31m ------ WARNING \e[0m"
CriticalMark="\e[47;31m ------ CRITICAL \e[0m"
d="-------------------------------------"

Info() {
	echo -en "${1}${green}${2}${nc}\n"
}

Warn() {
        echo -en "${1}${purple}${2}${nc}\n"
}

Success() {
	echo -en "${1}${green}${2}${nc}\n"
}

Error () {
	echo -en "${1}${red}${2}${nc}\n"
}

Splash() {
	echo -en "${white}${1}${nc}\n"
}

space() { 
	echo -e ""
}

# Functions
# ---------------------------------------------------\
isRoot() {
	if [ $(id -u) -ne 0 ]; then
		Error "You must be root user to continue"
		exit 1
	fi
	RID=$(id -u root 2>/dev/null)
	if [ $? -ne 0 ]; then
		Error "User root no found. You should create it to continue"
		exit 1
	fi
	if [ $RID -ne 0 ]; then
		Error "User root UID not equals 0. User root must have UID 0"
		exit 1
	fi
}

checkDistro() {
	# Checking distro
	if [ -e /etc/centos-release ]; then
	    DISTRO=`cat /etc/redhat-release | awk '{print $1,$4}'`
	elif [ -e /etc/fedora-release ]; then
	    DISTRO=`cat /etc/fedora-release | awk '{print ($1,$3~/^[0-9]/?$3:$4)}'`
	else
	    Error "Your distribution is not supported (yet)"
	    exit 1
	fi
}

# get Actual date
getDate() {
	date '+%d-%m-%Y_%H-%M-%S'
}

isSELinux() {
	selinuxenabled
	if [ $? -ne 0 ]
	then
	    Error "SELinux:\t\t" "DISABLED"
	else
	    Info "SELinux:\t\t" "ENABLED"
	fi
}

chk_fileExist() {
	PASSED=$1

	if [[ -d $PASSED ]]; then
	    # echo "$PASSED is a directory"
	    return 1
	elif [[ -f $PASSED ]]; then
	    # echo "$PASSED is a file"
	    return 1
	else
	    # echo "$PASSED is not valid"
	    return 0

	fi
}

chk_SvsStatus() {
	systemctl is-active --quiet $1 && Info "$1: " "Running" || Error "$1: " "Stopped"
}

chk_SvcExist() {
    local n=$1
    if [[ $(systemctl list-units --all -t service --full --no-legend "$n.service" | cut -f1 -d' ') == $n.service ]]; then
        return 0
    else
        return 1
    fi
}

# https://unix.stackexchange.com/questions/43875/sending-the-output-from-dd-to-awk-sed-grep
# https://www.shellhacks.com/disk-speed-test-read-write-hdd-ssd-perfomance-linux/
chk_disk_write() {
	dd if=/dev/zero of=$TESTFILE bs=1M count=1024 |& awk '/copied/ {print $8 " "  $9}' 
	rm -f $TESTFILE
}

chk_disk_write

confirm() {
    # call with a prompt string or use a default
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            true
            ;;
        *)
            false
            ;;
    esac
}

# Actions
# ---------------------------------------------------\
space
Splash "-------------------------------\t\tSystem Information\t----------------------------"
checkDistro
Info "Hostname:\t\t" $HOSTNAME
Info "Distro:\t\t\t" "${DISTRO}"
Info "IP:\t\t\t" $SERVER_IP

isRoot
isSELinux

Info "Kernel:\t\t\t" `uname -r`
Info "Architecture:\t\t" `arch`
Info "Active User:\t\t" `w | cut -d ' ' -f1 | grep -v USER | xargs -n1`
echo -en "Current Load Average:\t${green}$(uptime|grep -o "load average.*"|awk '{print $3" " $4" " $5}')${nc}"

Splash "\n\n-------------------------------\t\tUsage of CPU/Memory\t------------------------------"
Info "Memory Usage:\t\t" `free | awk '/Mem/{printf("%.2f%"), $3/$2*100}'`
Info "Swap Usage:\t\t" `free | awk '/Swap/{printf("%.2f%"), $3/$2*100}'`
Info "CPU Usage:\t\t" `cat /proc/stat | awk '/cpu/{printf("%.2f%\n"), ($2+$4)*100/($2+$4+$5)}' |  awk '{print $0}' | head -1`

Splash "\n\n-------------------------------\t\tCPU Information\t\t------------------------------"
echo -en "Model name:\t\t${green}$(lscpu | grep -oP 'Model name:\s*\K.+')${nc}\n"
echo -en "Vendor ID:\t\t${green}$(lscpu | grep -oP 'Vendor ID:\s*\K.+')${nc}\n"
Info "CPU Cores\t\t" `awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo`
Info "CPU MHz:\t\t" `lscpu | grep -oP 'CPU MHz:\s*\K.+'`
Info "Hypervisor vendor:\t" `lscpu | grep -oP 'Hypervisor vendor:\s*\K.+'`
Info "Virtualization:\t\t" `lscpu | grep -oP 'Virtualization:\s*\K.+'`

Splash "\n\n-------------------------------\t\tBoot Information\t------------------------------"
Info "Active User:\t\t" `w | cut -d ' ' -f1 | grep -v USER | xargs -n1`
echo -en "Last Reboot:\t\t${green}$(who -b | awk '{print $3,$4,$5}')${nc}"
echo -en "\nUptime:\t\t\t${green}`awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60} {printf("%d days, %d hour %d min\n",a,b,c)}' /proc/uptime`${nc}"

Splash "\n\n-------------------------------\t\tLast 3 Reboot Info\t------------------------------"
last reboot | head -3

Splash "\n\n-------------------------------\t\tLast info\t------------------------------"
last | head -9

Splash "\n\n-------------------------------\t\tMount Information\t------------------------------"
echo -en "$MOUNT"|column -t

Splash "\n\n-------------------------------\t\tDisk usage\t\t------------------------------"
echo -e "( 0-90% = OK/HEALTHY, 90-95% = WARNING, 95-100% = CRITICAL )"
echo -e "$d$d"
echo -e "Mounted File System[s] Utilization (Percentage Used):\n"

COL1=$(echo "$FS_USAGE"|awk '{print $1 " "$7}')
COL2=$(echo "$FS_USAGE"|awk '{print $6}'|sed -e 's/%//g')

for i in $(echo "$COL2"); do
{
  if [ $i -ge 95 ]; then
    COL3="$(echo -e $i"% $CriticalMark\n$COL3")"
  elif [[ $i -ge 90 && $i -lt 95 ]]; then
    COL3="$(echo -e $i"% $WarningMark\n$COL3")"
  else
    COL3="$(echo -e $i"% $SuccessMark\n$COL3")"
  fi
}
done
COL3=$(echo "$COL3"|sort -k1n)
paste  <(echo "$COL1") <(echo "$COL3") -d' '|column -t

Splash "\n\n-------------------------------\t\tTest disk IO\t------------------------------"
echo -en "Write (1st):\t\t${green}$(dd if=/dev/zero of=$TESTFILE bs=1M count=1024 |& awk '/copied/ {print $8 " "  $9}')${nc}\n"
echo -en "Write (2nd):\t\t${green}$(dd if=/dev/zero of=$TESTFILE bs=1M count=1024 |& awk '/copied/ {print $8 " "  $9}')${nc}\n"
echo -en "Write (3nd):\t\t${green}$(dd if=/dev/zero of=$TESTFILE bs=1M count=1024 |& awk '/copied/ {print $8 " "  $9}')${nc}\n"
echo ""
echo -en "Read (1st):\t\t${green}$(dd if=$TESTFILE of=/dev/null bs=1M count=1024 |& awk '/copied/ {print $8 " "  $9}')${nc}\n"
echo -en "Read (2nd):\t\t${green}$(dd if=$TESTFILE of=/dev/null bs=1M count=1024 |& awk '/copied/ {print $8 " "  $9}')${nc}\n"
echo -en "Read (3nd):\t\t${green}$(dd if=$TESTFILE of=/dev/null bs=1M count=1024 |& awk '/copied/ {print $8 " "  $9}')${nc}\n"
rm -rf $TESTFILE

Splash "\n\n-------------------------------\t\tRead-only mounted\t------------------------------"
echo "$MOUNT"|grep -w \(ro\) && Info "\n.....Read Only file system[s] found"|| Info "No read-only file system[s] found. "

Splash "\n\n-------------------------------\t\tTop 5 memory usage\t------------------------------"
ps -eo pmem,pcpu,pid,ppid,user,stat,args | sort -k 1 -r | head -6

Splash "\n\n-------------------------------\t\tTop 5 CPU usage\t\t------------------------------"
ps -eo pcpu,pmem,pid,ppid,user,stat,args | sort -k 1 -r | head -6

Splash "\n\n-------------------------------\t\tSpeedtest\t------------------------------"
echo -en "Washington, D.C. (east):\t\t${green}$(wget --output-document=/dev/null http://speedtest.wdc01.softlayer.com/downloads/test10.zip 2>&1 | grep -o "[0-9.]\+ [KM]*B/s")${nc}\n"
echo -en "San Jose, California (west):\t\t${green}$(wget --output-document=/dev/null http://speedtest.sjc01.softlayer.com/downloads/test10.zip 2>&1 | grep -o "[0-9.]\+ [KM]*B/s")${nc}\n"
echo -en "Tokyo, JP:\t\t\t\t${green}$(wget --output-document=/dev/null http://speedtest.tokyo2.linode.com/100MB-tokyo2.bin 2>&1 | grep -o "[0-9.]\+ [KM]*B/s")${nc}\n"
echo -en "Frankfurt, DE, JP:\t\t\t${green}$(wget --output-document=/dev/null http://speedtest.frankfurt.linode.com/100MB-frankfurt.bin 2>&1 | grep -o "[0-9.]\+ [KM]*B/s")${nc}\n"

Splash "\n\n-------------------------------\t\tServices state\t\t------------------------------"

# Read data from list.txt
while read -r service; do

	# Cut comment lines
    if [[ -n "$service" && "$service" != [[:blank:]#]* ]]; then
    	if chk_SvcExist $service; then
			chk_SvsStatus $service
		else
			Warn "$service " "Not installed"
		fi
    fi

done < $SERVICES

space
if confirm "List all running services?"; then
	Splash "\n\n-------------------------------Running services------------------------------"
	systemctl list-units | grep running
fi
