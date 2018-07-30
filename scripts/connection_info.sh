#!/bin/sh

OS=`uname`
NETSTAT=/bin/netstat
SS=/usr/sbin/ss

if [ "$OS" = "FreeBSD" ]; then
	NETSTAT=/usr/bin/netstat
fi

freebsd_netstat()
{
	${NETSTAT} -n -p tcp
	${NETSTAT} -n -p udp
}

netstat_out()
{
	if [ "$OS" = "FreeBSD" ]; then
		freebsd_netstat | grep -v Address | grep -v Active | grep -v '*.*' | awk '{print $5}' | sed 's/\(.*\)\..*/\1/'
	else
		${NETSTAT} -ntu | grep -v Address | grep -v Active | grep -v '*.*' | awk '{print $5}' | sed 's/\(.*\):.*/\1/'
	fi
}

show_ip_info()
{
	I=$1
	
	echo ""
	echo "Connection info for '${I}':"
	
	if [ "$OS" = "FreeBSD" ]; then
		freebsd_netstat | grep $I
	else
		${NETSTAT} -ntu | grep $I
	fi
}

if [ -x ${NETSTAT} ]; then
	echo "Connection counts:"
	netstat_out | sort | uniq -c | sort -n | tail -n 100
	
	echo ""

	#now take the IP with top connection count and get more info.
	C_IP=`netstat_out | sort | uniq -c | sort -n | tail -n 1`
	C=`echo "$C_IP" | awk '{print $1}'`
	IP=`echo "$C_IP" | awk '{print $2}'`
	echo "IP '$IP' currently has '$C' connections"

	show_ip_info $IP
	
fi

if [ -x ${SS} ]; then
	echo ""
	echo "$SS output:"
	$SS -n
fi

CIP=/usr/local/directadmin/scripts/custom/connection_info_post.sh
if [ -x ${CIP} ]; then
	${CIP}
fi

exit 0;
