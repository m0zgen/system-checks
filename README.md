## System Checker script

Works on this time only CentOS / Fedora

* System info
  * Hostname
  * Distributive
  * Lical IP
  * External IP
  * SELinux status
  * Kernel / Architecture
  * Load average
  * Active user
* CPU
  * Model name
  * Vendor
  * Cores / MHz
  * Hypervizor vendor
  * CPU usage
* Memory usage
  * Total / Usage
  * Swap total / Usage
* Boot information
  * Last boot
  * Uptime
  * Active user
  * Last 3 reboot
  * Last logons info
* Disk Usage
  * Mount information
  * Disk utilization
  * Disc IO speed (Read / Write)
  * Show read-only mounted devices
* Average information
  * Top 5 memory usage processes
  * Top 5 CPU usage processes
* Speedtest
  * Washington, D.C. (east)
  * San Jose, California (west)
  * Frankfurt, DE, JP
* Checking systemd services status
  * You can define services list
  * Show information form default list (nginx, mongo, rsyslog and etc)
* Bash users
* Who logged
* Listen ports
* Unowned files
* User list from processes

## Parameters

* `-sn` - Skip speedtest
* `-sd` - Skip disk test
* `-ss` - Show all running services
* `-e` - Extra info (Bash users, Who logged, All running services, Listen ports, UnOwned files, User list from processes)

## Usage
You can use this script with several parameters:
```
./system-check.sh -sn -sd -e
```
```
./system-check.sh -ss
```

## Run directly
```bash
wget -O - https://raw.githubusercontent.com/m0zgen/system-checks/master/system-check.sh | bash
```

## Description

* https://sys-adm.in/sections/os-nix/881-bash-sbor-informatsii-o-sisteme.html

## Thanks

* https://github.com/SimplyLinuxFAQ/health-check-script