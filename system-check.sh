#!/bin/bash
# Author: Yevgeniy Goncharov aka xck, http://sys-adm.in
# Collect & Check Linux server status

# Sys env / paths / etc
# -------------------------------------------------------------------------------------------\
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
SCRIPT_PATH=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)

# Initial variables
# ---------------------------------------------------\
HOSTNAME=`hostname`
SERVER_IP=`hostname -I`
MOUNT=$(mount|egrep -iw "ext4|ext3|xfs|gfs|gfs2|btrfs"|grep -v "loop"|sort -u -t' ' -k1,2)
FS_USAGE=$(df -PTh|egrep -iw "ext4|ext3|xfs|gfs|gfs2|btrfs"|grep -v "loop"|sort -k6n|awk '!seen[$1]++')
SERVICES="$SCRIPT_PATH/services-list.txt"
TESTFILE="$SCRIPT_PATH/tempfile"
TOTALMEM=$(free -m | awk '$1=="Mem:" {print $2}')
DEBUG=false

# Colored styles
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

# Help information
usage() {

	Info "" "\nParameters:\n"
	echo -e "-sn - Skip speedtest\n
-sd - Skip disk test\n
-ss - Show all running services\n
-e - Extra info (Bash users, Who logged, All running services, Listen ports, UnOwned files, User list from processes)
	"

	Info "" "Usage:"
	echo -e "You can use this script with several parameters:"
	echo -e "./system-check.sh -sn -sd -e"
	echo -e "./system-check.sh -ss"
	exit 1

}

# Checks arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -sn|--skip-network) SKIPNET=1; ;;
		-ss|--skip-services) SKIPSERVICES=1; ;;
        -sd|--skip-disk) SKIPDISK=1 ;;
		-e|--extra) EXTRA=1 ;;
		-h|--help) usage ;;	
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Functions
# ------------------------------------------------------------------------------------------------------\

## Service functions

# Yes / No confirmation
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

# Check is current user is root
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

# Checks supporting distros
checkDistro() {
	# Checking distro
	if [ -e /etc/centos-release ]; then
	    DISTRO=`cat /etc/redhat-release | awk '{print $1,$4}'`
	    RPM=1
	elif [ -e /etc/fedora-release ]; then
	    DISTRO=`cat /etc/fedora-release | awk '{print ($1,$3~/^[0-9]/?$3:$4)}'`
	    RPM=1
	elif [ -e /etc/os-release ]; then
		DISTRO=`lsb_release -d | awk -F"\t" '{print $2}'`
		RPM=0
	else
	    Error "Your distribution is not supported (yet)"
	    exit 1
	fi
}

# get Actual date
getDate() {
	date '+%d-%m-%Y_%H-%M-%S'
}

# SELinux status
isSELinux() {

	if [[ "$RPM" -eq "1" ]]; then
		selinuxenabled
		if [ $? -ne 0 ]
		then
		    Error "SELinux:\t\t" "DISABLED"
		else
		    Info "SELinux:\t\t" "ENABLED"
		fi
	fi

}

# If file exist true / false
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

# Unit services status
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

## Functional / Test functions

# Collect CPU information
cpu_info() {
	echo -en "Model name:\t\t${green}$(lscpu | grep -oP 'Model name:\s*\K.+')${nc}\n"
	echo -en "Vendor ID:\t\t${green}$(lscpu | grep -oP 'Vendor ID:\s*\K.+')${nc}\n"
	Info "CPU Cores\t\t" `awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo`
	Info "CPU MHz:\t\t" `lscpu | grep -oP 'CPU MHz:\s*\K.+'`
	Info "Hypervisor vendor:\t" `lscpu | grep -oP 'Hypervisor vendor:\s*\K.+'`
	Info "Virtualization:\t\t" `lscpu | grep -oP 'Virtualization:\s*\K.+'`
	Info "CPU Usage:\t\t" `cat /proc/stat | awk '/cpu/{printf("%.2f%\n"), ($2+$4)*100/($2+$4+$5)}' |  awk '{print $0}' | head -1`
}

# Test HDD
test_disk() {

	if [[ "$SKIPDISK" -eq "1" ]]; then
		Info "" "Disk test was skipped"
	else
		echo -en "Write (1st):\t\t${green}$(dd if=/dev/zero of=$TESTFILE bs=1M count=1024 |& awk '/copied/ {print $0}' | sed 's:.*,::')${nc}\n"
		echo -en "Write (2nd):\t\t${green}$(dd if=/dev/zero of=$TESTFILE bs=1M count=1024 |& awk '/copied/ {print $0}' | sed 's:.*,::')${nc}\n"
		echo -en "Write (3nd):\t\t${green}$(dd if=/dev/zero of=$TESTFILE bs=1M count=1024 |& awk '/copied/ {print $0}' | sed 's:.*,::')${nc}\n"
		echo ""
		echo -en "Read (1st):\t\t${green}$(dd if=$TESTFILE of=/dev/null bs=1M count=1024 |& awk '/copied/ {print $0}' | sed 's:.*,::')${nc}\n"
		echo -en "Read (2nd):\t\t${green}$(dd if=$TESTFILE of=/dev/null bs=1M count=1024 |& awk '/copied/ {print $0}' | sed 's:.*,::')${nc}\n"
		echo -en "Read (3nd):\t\t${green}$(dd if=$TESTFILE of=/dev/null bs=1M count=1024 |& awk '/copied/ {print $0}' | sed 's:.*,::')${nc}\n"
		rm -rf $TESTFILE
	fi

}

# HDD usage
disk_usage() {
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

	# https://unix.stackexchange.com/questions/43875/sending-the-output-from-dd-to-awk-sed-grep
	# https://www.shellhacks.com/disk-speed-test-read-write-hdd-ssd-perfomance-linux/
}

# IPv4 speed tests
speedtest_v4() {
	local res=$(wget -4O /dev/null -T200 $1 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}')
	local region=$2
	echo -en "$2\t\t${green}$res${nc}\n"
}

test_v4() {

	if [[ "$SKIPNET" -eq "1" ]]; then
		Info "" "Network test was skipped"
	else
		Info "Status\t\t\t" "Started..."
		speedtest_v4 "http://speedtest.wdc01.softlayer.com/downloads/test10.zip" "Washington, D.C. (east)\t"
		speedtest_v4 "http://speedtest.sjc01.softlayer.com/downloads/test10.zip" "San Jose, California (west)"
		speedtest_v4 "http://speedtest.frankfurt.linode.com/100MB-frankfurt.bin" "Frankfurt, DE, JP\t"
	fi
}

# General system information
system_info() {
	checkDistro
	Info "Hostname:\t\t" $HOSTNAME
	Info "Distro:\t\t\t" "${DISTRO}"
	Info "IP:\t\t\t" $SERVER_IP
	Info "External IP:\t\t" $(curl -s ifconfig.co)

	isRoot
	isSELinux

	Info "Kernel:\t\t\t" `uname -r`
	Info "Architecture:\t\t" `arch`
	Info "Active User:\t\t" `w | cut -d ' ' -f1 | grep -v USER | xargs -n1`
	echo -en "Current Load Average:\t${green}$(uptime|grep -o "load average.*"|awk '{print $3" " $4" " $5}')${nc}"
}

# Memory info
mem_info() {
	Info "Total memory:\t\t" "${TOTALMEM}Mb"
	Info "Memory Usage:\t\t" `free | awk '/Mem/{printf("%.2f%"), $3/$2*100}'`
	space
	if free | awk '/^Swap:/ {exit !$2}'; then
		TOTALSWAP=$(free -m | awk '$1=="Swap:" {print $2}')
		Info "Total swap:\t\t" "${TOTALSWAP}Mb"
	    Info "Swap Usage:\t\t" `free | awk '/Swap/{printf("%.2f%"), $3/$2*100}'`
	else
	    Error "Swap Usage:\t\t" "swap does not exist"
	fi
}

# Boot info
boot_info() {
	Info "Active User:\t\t" `w | cut -d ' ' -f1 | grep -v USER | xargs -n1`
	echo -en "Last Reboot:\t\t${green}$(who -b | awk '{print $3,$4,$5}')${nc}"
	echo -en "\nUptime:\t\t\t${green}`awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60} {printf("%d days, %d hour %d min\n",a,b,c)}' /proc/uptime`${nc}"
}

# Actions
# ------------------------------------------------------------------------------------------------------\

space
Splash "-------------------------------\t\tSystem Information\t----------------------------"

system_info

Splash "\n\n-------------------------------\t\tCPU Information\t\t------------------------------"

cpu_info

Splash "\n\n-------------------------------\t\tMemory Information\t\t------------------------------"

mem_info

Splash "\n\n-------------------------------\t\tBoot Information\t------------------------------"

boot_info

Splash "\n\n-------------------------------\t\tLast 3 Reboot Info\t------------------------------"
last reboot | head -3

Splash "\n\n-------------------------------\t\tLast info\t------------------------------"
last | head -9

Splash "\n\n-------------------------------\t\tMount Information\t------------------------------"
echo -en "$MOUNT"|column -t

Splash "\n\n-------------------------------\t\tDisk usage\t\t------------------------------"

disk_usage

Splash "\n\n-------------------------------\t\tTest disk IO\t------------------------------"

test_disk

Splash "\n\n-------------------------------\t\tRead-only mounted\t------------------------------"
echo "$MOUNT"|grep -w \(ro\) && Info "\n.....Read Only file system[s] found"|| Info "No read-only file system[s] found. "

Splash "\n\n-------------------------------\t\tTop 5 memory usage\t------------------------------"
ps -eo pmem,pcpu,pid,ppid,user,stat,args | sort -k 1 -r | head -6

Splash "\n\n-------------------------------\t\tTop 5 CPU usage\t\t------------------------------"
ps -eo pcpu,pmem,pid,ppid,user,stat,args | sort -k 1 -r | head -6


Splash "\n\n-------------------------------\t\tSpeedtest\t------------------------------"
# Debug clean
if ( ! $DEBUG ); then
    test_v4
else
	echo "Debug is enabled!"
fi


if [[ -f $SERVICES ]]; then

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
	
fi

if [[ "$SKIPSERVICES" -eq "1" ]]; then
	if confirm "List all running services? (y/n or enter)"; then
		Splash "\n\n-------------------------------Running services------------------------------"
		space
		systemctl list-units | grep running
	fi
fi



if [[ "$EXTRA" -eq "1" ]]; then
	
	Splash "\n\n-------------------------------\t\tBash users\t------------------------------"
	space
	cat /etc/passwd | grep bash | awk -F: '{ print $1}'

	Splash "\n\n-------------------------------\t\tUsers from processes\t------------------------------"
	space
	ps -ef | awk '{print $1}' | sort | uniq | grep -v 'UID'

	Splash "\n\n-------------------------------\t\tLogged users\t------------------------------"
	space
	w -h

	Splash "\n\n-------------------------------\t\tListen ports\t------------------------------"
	space
	if ! command -v netstat &> /dev/null
	then
	    Warn "" "NETSTAT could not be found"
	else
		netstat -tulpn | grep 'LISTEN'
	fi

	Splash "\n\n-------------------------------\t\tAll running services\t----------------------"
	space
	systemctl list-units | grep running

	Splash "\n\n-------------------------------\t\tAll running processes\t----------------------"
	space
	# ps -A | awk '{print $4}' | grep -v 'CMD' | uniq | sort
	# as tree
	# ps -ejH
	ps axjf

	Splash "\n\n-------------------------------\t\tUnowned files\t----------------------"
	space
	Info "Status\t\t\t" "Find..."
	# find / -nouser -o -nogroup -exec ls -l {} \;
	find / -xdev -nouser -o -nogroup -exec ls {} \; > /tmp/find_res.log

	if [ -s /tmp/find_res.log ]
	then
	     cat /tmp/find_res.log | grep -v '/' -A 1
	else
	     Info "Status:\t\t\t" "OK. Not found."
	fi

fi



