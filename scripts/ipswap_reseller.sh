#!/bin/sh
#Version: 0.1 ALPHA (use at your own risk!)
#Script is used to change the IP of all Users owned by Reseller on a DA server (including the Reseller himself).
#Written by DirectAdmin and Martynas Bendorius (smtalk)
#Usage: $0 <oldip> <newip> <reseller>

LOG=/var/log/directadmin/ipswap_reseller.log

MYUID=`/usr/bin/id -u`
if [ "$MYUID" != 0 ]; then
	echo "You require Root Access to run this script";
	exit 1;
fi

if [ $# != 2 ] && [ $# != 3 ] && [ $# != 4 ]; then
	echo "Usage:";
	echo "$0 <oldip> <newip> <reseller>";
	echo "you gave #$#: $0 $1 $2 $3";
	echo "";
	echo "New IP must exist and be set as shared.";
	exit 2;
fi

OLD_IP=$1
NEW_IP=$2
RESELLER=$3

HAVE_HTTPD=1
HAVE_NGINX=0
if [ -s ${DIRECTADMIN} ]; then
	if [ "`${DIRECTADMIN} c | grep ^nginx= | cut -d= -f2`" -eq 1 ]; then
		HAVE_HTTPD=0
		HAVE_NGINX=1
	fi
	if [ "`${DIRECTADMIN} c | grep ^nginx_proxy= | cut -d= -f2`" -eq 1 ]; then
		HAVE_HTTPD=1
		HAVE_NGINX=1
	fi
fi


log()
{
	echo -e "$1";
	echo -e "$1" >> $LOG;
}

swapfile()
{
	if [ ! -e $1 ]; then
		log "Cannot Find $1 to change the IPs. Skipping...";
		return;
	fi
	
	TEMP="perl -pi -e 's/(^|[\s.=\/:])${OLD_IP}([\s.>:])/\${1}${NEW_IP}\${2}/g' $1"
        eval $TEMP;

	log "$1\t: $OLD_IP -> $NEW_IP";
}

IPFILE_OLD=/usr/local/directadmin/data/admin/ips/$OLD_IP
IPFILE_NEW=/usr/local/directadmin/data/admin/ips/$NEW_IP
if [ ! -e $IPFILE_NEW ]; then
	echo -n "$IPFILE_NEW does not exist.  Exiting... ";
	exit 3;
fi
IP_STATUS=`grep status ${IPFILE_NEW} | cut -d= -f2`
if [ "${IP_STATUS}" != "shared" ]; then
    echo "Please make the IP (${NEW_IP}) shared on reseller level."
	exit 4;
fi

ULDDU=/usr/local/directadmin/data/users
if [ ! -e ${ULDDU}/${RESELLER}/users.list ]; then
	echo "Reseller ${RESELLER} does not exist.  Exiting... ";
	exit 5;
fi

IP_LIST=${ULDDU}/${RESELLER}/ip.list
COUNT_IP=`grep -c ${NEW_IP} ${IP_LIST}`
if [ ${COUNT_IP} -eq 0 ]; then
	echo "${NEW_IP} does not belong to ${RESELLER}. Please assign it to reseller and start the script again. Exiting."
	exit 6;
fi

OS=`uname`
if [ $OS = "FreeBSD" ]; then
	DB_PATH=/etc/namedb
else
	if [ -e /etc/debian_version ]; then
		DB_PATH=/etc/bind
	else
		DB_PATH=/var/named
	fi
fi

for i in `cat ${ULDDU}/${RESELLER}/users.list && echo "${RESELLER}"`; do
{
	if [ ! -d $ULDDU/$i ]; then
		continue;
	fi
	
	swapfile $ULDDU/$i/user.conf
	if [ "${HAVE_HTTPD}" -eq 1 ]; then
		swapfile $ULDDU/$i/httpd.conf
	fi
	if [ "${HAVE_NGINX}" -eq 1 ]; then
		swapfile $ULDDU/$i/nginx.conf
	fi
	
	if [ -e $ULDDU/$i/ip.list ]; then
		swapfile $ULDDU/$i/ip.list
	fi

	swapfile $ULDDU/$i/user_ip.list	

	for j in `ls $ULDDU/$i/domains/*.conf; ls $ULDDU/$i/domains/*.ftp; ls $ULDDU/$i/domains/*.ip_list`; do
	{
		swapfile $j
	};
	done;
	
	for d in `cat ${ULDDU}/$i/domains.list`; do
	{
		swapfile ${DB_PATH}/$d.db
		echo "action=rewrite&value=named&domain=$d" >> /usr/local/directadmin/data/task.queue

		for p in `cat ${ULDDU}/$i/domains/$d.pointers | cut -d= -f1 2>/dev/null`; do
		{
			swapfile ${DB_PATH}/$p.db
			echo "action=rewrite&value=named&domain=$p" >> /usr/local/directadmin/data/task.queue
		}
		done;
	};
	done;
};
done;

echo "action=rewrite&value=ipcount" >> /usr/local/directadmin/data/task.queue
echo "action=rewrite&value=ips" >> /usr/local/directadmin/data/task.queue
echo "action=cache&value=showallusers" >> /usr/local/directadmin/data/task.queue
echo "action=rewrite&value=httpd" >> /usr/local/directadmin/data/task.queue
echo "Runing dataskq..."
/usr/local/directadmin/dataskq d

log "\n*** Done swapping $OLD_IP to $NEW_IP ***\n";
exit 0;
