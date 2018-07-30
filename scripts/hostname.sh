#!/bin/bash

if [ $# -lt "1" ]
then
        echo "Usage: $0 <hostname> (<ip>)";
        exit 1;
fi
DIRECTADMIN_BIN=/usr/local/directadmin/directadmin
DIRECTADMIN_CONF=/usr/local/directadmin/conf/directadmin.conf
IP="127.0.0.1";
SETUP=/usr/local/directadmin/scripts/setup.txt
ETH_DEV=eth0
if [ -e $SETUP ]
then
	IP=`cat $SETUP | grep ip= | cut -d= -f2`;
else
	IP=`/sbin/ifconfig $ETH_DEV | grep 'inet addr:' | cut -d: -f2 | cut -d\  -f1`;
fi

if [ $# -gt "1" ]
then
	IP=$2;
fi

OLDHOST=`hostname --fqdn`

/bin/hostname $1;

if [ "${OLDHOST}" = "" ]; then
	OLDHOST=old.host.com
	echo "old hostname was blank. Setting placeholder value ${OLDHOST}"
fi

#remove any previous hostnames.
cat /etc/hosts | grep -Fv $1 | grep -Fv $OLDHOST | grep -v '#' > /etc/hosts.tmp

#start the file over
echo "# Do not remove the following line, or various programs" > /etc/hosts
echo "# that require network functionality will fail." >> /etc/hosts

COUNT=`cat /etc/hosts.tmp | grep -c localhost`
if [ $COUNT -lt "1" ]
then
	echo -e "127.0.0.1\t\tlocalhost localhost.localdomain" >> /etc/hosts
fi

cat /etc/hosts.tmp >> /etc/hosts



echo -e "${IP}\t\t${1}" >> /etc/hosts

chmod 644 /etc/hosts



if [ -e /etc/hostname ]; then
	echo $1 > /etc/hostname
fi

if [ ! -e /etc/debian_version ]; then
	STR="/usr/bin/perl -pi -e 's/HOSTNAME=(.*)/HOSTNAME=${1}/' /etc/sysconfig/network;";
	eval $STR;
	
	/usr/bin/hostnamectl set-hostname ${1}
fi


#for exim.
if [ -s /etc/virtual/domains ]
then
	perl -pi -e "s/^\Q$OLDHOST\E\$/$1/" /etc/virtual/domains

	#backup plan, in case there was no old hostname
	COUNT=`cat /etc/virtual/domains | grep -Fc $1`;
	if [ "$COUNT" -lt 1 ]
	then
		echo $1 >> /etc/virtual/domains;
	fi
fi

#this is for exim 4 as it wants the dir for the filters

V=/etc/virtual
if [ ! -e ${V} ]
then
	/bin/mkdir -p ${V}
	/bin/chown -f mail:mail ${V}
	/bin/chmod -f 755 ${V}
fi

NEW_DIR=/etc/virtual/${1}
OLD_DIR=/etc/virtual/${OLDHOST}

if [ -d ${OLD_DIR} ] && [ ! -d ${NEW_DIR} ]; then
	mv ${OLD_DIR} ${NEW_DIR}
else
	if [ ! -d ${NEW_DIR} ]; then
		/bin/mkdir -p ${NEW_DIR}
		/bin/chown -f mail:mail ${NEW_DIR}
		/bin/chmod -f 711 ${NEW_DIR}
	fi
fi

#dovecot
LMTP=/etc/dovecot/conf/lmtp.conf
if [ -s ${LMTP} ]; then
	perl -pi -e "s/\Q$OLDHOST\E/$1/" ${LMTP}
fi

SETUP=/usr/local/directadmin/scripts/setup.txt
if [ -s ${SETUP} ] && [ -s ${DIRECTADMIN_CONF} ]; then
	perl -pi -e "s/\Q$OLDHOST\E\$/$1/" ${SETUP}
fi

echo "action=rewrite&value=httpd" >> /usr/local/directadmin/data/task.queue

#mysql pid file.
PIDF=/var/lib/mysql/${OLDHOST}.pid
if [ -e $PIDF ]; then
	mv $PIDF /var/lib/mysql/${1}.pid
fi

PIDF=/home/mysql/${OLDHOST}.pid
if [ -e $PIDF ]; then
        mv $PIDF /home/mysql/${1}.pid
fi

#LetsEncrypt
SAN_CONFIG=/usr/local/directadmin/conf/ca.san_config
if [ -s ${SAN_CONFIG} ]; then
	perl -pi -e "s/\Q$OLDHOST\E\$/$1/" ${SAN_CONFIG}
fi

exit 0;
