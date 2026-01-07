#!/bin/bash
export LANG=C.UTF-8
source /etc/default/sdrmapfeeder

version='4.2.1'
sysinfolastrun=0
radiosondelastrun=0


if [[ -z $username ]] || [[ -z $password ]] || [[ $username == "yourusername" ]] || [[ $password == "yourpassword" ]]; then
	echo "Please edit your credentials."
	exit 1
fi

while true; do
	if [[ "$sysinfo" == 'true' ]] && [[ $(($(date +"%s") - $sysinfolastrun)) -ge "$sysinfointerval" ]]; then
		sysinfolastrun=$(date +"%s")

		if [[ "$gps" == 'true' ]] && command -v gpspipe >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
			s=$(gpspipe -w -n 10|grep -m 1 lat)
			if [[ $? -eq 0 ]]; then
				gpsLat=$(echo $s|jq '.lat')
				gpsLon=$(echo $s|jq '.lon')
			fi
		fi

		echo "{\
			\"cpu\":{\
				\"model\":\"$(test -f /sys/firmware/devicetree/base/model && tr -d '\0' < /sys/firmware/devicetree/base/model || cat /proc/cpuinfo |grep 'model'|tail -n 1|cut -d ':' -f 2)\",\
				\"cores\":\"$(cat /proc/cpuinfo |grep -c -e '^processor')\",\
				\"load\":\"$(cat /proc/loadavg |cut -d ' ' -f 1)\",\
				\"temp\":\"$([[ $(ls /sys/class/thermal/thermal_zone* 2>/dev/null | grep -c -w temp) -gt 0 ]] && echo $(($(cat /sys/class/thermal/thermal_zone*/temp |sort -n|tail -n 1 2>/dev/null)/1000)))\",\
				\"throttled\":\"$(vcgencmd get_throttled 2>/dev/null |cut -d '=' -f 2 )\"\
			},\
			\"memory\":{\
				\"total\":\"$(cat /proc/meminfo |grep 'MemTotal:'|cut -d ':' -f 2|awk '{$1=$1};1')\",\
				\"free\":\"$(cat /proc/meminfo |grep 'MemFree:'|cut -d ':' -f 2|awk '{$1=$1};1')\",\
				\"available\":\"$(cat /proc/meminfo |grep 'MemAvailable:'|cut -d ':' -f 2|awk '{$1=$1};1')\"\
			},\
			\"devices\":{\
				\"rtlsdr\":\"$(lsusb | grep -c '0bda:283[28]')\",\
				\"airspy\":\"$(lsusb | grep -c '1d50:60a1')\"
			},\
			\"uptime\":\"$(cat /proc/uptime |cut -d ' ' -f 1)\",\
			\"os\":{\
				\"kernel\":\"$(uname -r)\",\
				\"version:\":\"$(hostnamectl |grep 'Operating System'|cut -d ':' -f 2|awk '{$1=$1};1')\",\
				\"arch\":\"$(hostnamectl |grep 'Architecture'|cut -d ':' -f 2|awk '{$1=$1};1')\"
			},\
			\"packages\":{\
				\"c2isrepo\":\"$(cat /etc/apt/sources.list.d/*|grep -c 'https://repo.chaos-consulting.de')\",\
   				\"sdrmaprepo\":\"$(cat /etc/apt/sources.list.d/*|grep -c 'https://repo.sdrmap.org')\",\
				\"mlat-client-c2is\":\"$(dpkg -s mlat-client-c2is 2>&1|grep 'Version:'|cut -d ' ' -f 2)\",\
   				\"mlat-client-sdrmap\":\"$(dpkg -s mlat-client-sdrmap 2>&1|grep 'Version:'|cut -d ' ' -f 2)\",\
				\"stunnel4\":\"$(dpkg -s stunnel4 2>&1|grep 'Version:'|cut -d ' ' -f 2)\",\
				\"dump1090-mutability\":\"$(dpkg -s dump1090-mutability 2>&1|grep 'Version:'|cut -d ' ' -f 2)\",\
				\"dump1090-fa\":\"$(dpkg -s dump1090-fa 2>&1|grep 'Version:'|cut -d ' ' -f 2)\",\
				\"ais-catcher\":\"$(dpkg -s ais-catcher 2>&1 |grep 'Version:'|cut -d ' ' -f 2)\",\
   				\"radiosondeautorx\":\"$(dpkg -s radiosondeautorx 2>&1 |grep 'Version:'|cut -d ' ' -f 2)\"\
			},\
			\"position\":{\
				\"enabled\":\"$position\",\
				\"lat\":\"$([[ $position = 'true' ]] && ([[ ! -z ${gpsLat+x} ]] && echo $gpsLat || echo $lat))\",\
				\"lon\":\"$([[ $position = 'true' ]] && ([[ ! -z ${gpsLon+x} ]] && echo $gpsLon || echo $lon))\"
			},\
			\"feeder\":{\
				\"version\":\"$version\",\
				\"interval\":\"$sysinfointerval\"
			}\
		}"| gzip -c |curl -s -u $username:$password -X POST -H "Content-type: application/json" -H "Content-encoding: gzip" --data-binary @- https://sys.feed.sdrmap.org/index.php
	fi;

	if [[ "$adsb" == 'true' ]]; then
			gzip -c $adsbpath | curl -s -u $username:$password -X POST -H "Content-type: application/json" -H "Content-encoding: gzip" --data-binary @- https://adsb.feed.sdrmap.org/index.php
	fi

	if [[ "$radiosonde" == 'true' ]] && [[ $(($(date +"%s") - $radiosondelastrun)) -ge "$radiosondeinterval" ]]; then
		radiosondelastrun=$(date +"%s")
		if [[ ! -d "$radiosondepath" ]]; then
			echo "The log directory '$radiosondepath' doesn't exist."
			exit 1
		fi
		for i in $(find $radiosondepath -mmin -0.1 -name "*sonde.log");
			do
			tail -n 1 $i | gzip | curl -s -u $username:$password -X POST -H "Content-type: application/json" -H "Content-encoding: gzip" --data-binary @- https://radiosonde.feed.sdrmap.org/index.php
		done
	fi

	sleep 1
done
