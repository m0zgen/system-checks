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
	    DISTR="CentOS"
	elif [ -e /etc/fedora-release ]; then
	    DISTR="Fedora"
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
Info "Distro:\t\t\t" $DISTR
Info "IP:\t\t\t" $SERVER_IP

isRoot
isSELinux

Info "Kernel:\t\t\t" `uname -r`
Info "Architecture:\t\t" `arch`
Info "Active User:\t\t" `w | cut -d ' ' -f1 | grep -v USER | xargs -n1`

Splash "\n\n-------------------------------\t\tCPU/Memory Usage\t------------------------------"
Info "Memory Usage:\t\t" `free | awk '/Mem/{printf("%.2f%"), $3/$2*100}'`
Info "Swap Usage:\t\t" `free | awk '/Swap/{printf("%.2f%"), $3/$2*100}'`
Info "CPU Usage:\t\t" `cat /proc/stat | awk '/cpu/{printf("%.2f%\n"), ($2+$4)*100/($2+$4+$5)}' |  awk '{print $0}' | head -1`
echo ""

Splash "\n\n-------------------------------\t\tBoot Information\t------------------------------"
Info "Active User:\t\t" `w | cut -d ' ' -f1 | grep -v USER | xargs -n1`
echo -en "Last Reboot:\t\t${green}$(who -b | awk '{print $3,$4,$5}')${nc}"
echo -en "\nUptime:\t\t\t>${green}$(uptime)${nc}"

Splash "\n\n-------------------------------\t\tLast 3 Reboot Info\t------------------------------"
last reboot | head -3

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

Splash "\n\n-------------------------------\t\tRead-only mounted\t------------------------------"
echo "$MOUNT"|grep -w \(ro\) && Info "\n.....Read Only file system[s] found"|| Info "No read-only file system[s] found. "

Splash "\n\n-------------------------------\t\tCurren average\t\t------------------------------"
echo -en "Current Load Average:\t ${green}$(uptime|grep -o "load average.*"|awk '{print $3" " $4" " $5}')${nc}"

Splash "\n\n-------------------------------\t\tTop 5 memory usage\t------------------------------"
ps -eo pmem,pcpu,pid,ppid,user,stat,args | sort -k 1 -r | head -6

Splash "\n\n-------------------------------\t\tTop 5 CPU usage\t\t------------------------------"
ps -eo pcpu,pmem,pid,ppid,user,stat,args | sort -k 1 -r | head -6

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



