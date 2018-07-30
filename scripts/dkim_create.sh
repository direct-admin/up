#!/bin/sh
#dkim script to create keys in /etc/virtual/domain.com
#will ensure they exist and create them if missing.
#will also dump a task.queue entry to get DA to add the newly created key to the dns.

if [ $# != 1 ] && [ $# != 2 ]; then
        echo "Usage:";
        echo "$0 <domain> (nodns)";
        echo "you gave #$#: $0 $1 $2";
        exit 1;
fi

DOMAIN=$1
DOMAIN_OWNERS=/etc/virtual/domainowners
VD=/etc/virtual/$DOMAIN
PRIV_KEY=${VD}/dkim.private.key
PUB_KEY=${VD}/dkim.public.key

OS="`uname`"
if [ "${OS}" = "FreeBSD" ]; then
        CHOWN=/usr/sbin/chown
else
	CHOWN=/bin/chown
fi

if [ ! -e $CHOWN ]; then
	echo "Cannot find chown at $CHOWN";
	exit 2;
fi

DKIM_ON=`/usr/local/directadmin/directadmin c | grep dkim= | cut -d= -f2`
if [ "$DKIM_ON" -eq 0 ]; then
	echo "DKIM is not enabled. Add dkim=1 to the directadmin.conf";
	exit 3;
fi

if [ ! -d ${VD} ]; then
	echo "Unable to find ${VD}";
	exit 2;
fi


COUNT=`grep -c ^${DOMAIN}: ${DOMAIN_OWNERS}`
if [ "${COUNT}" -gt 0 ]; then
	#lets see if they've set dkim=0 in their user.conf or domains/domain.com.conf
	#https://www.directadmin.com/features.php?id=1937
	D_USER=`grep ^${DOMAIN}: ${DOMAIN_OWNERS} | cut -d\  -f2`
	USER_CONF=/usr/local/directadmin/data/users/${D_USER}/user.conf
	if [ -s ${USER_CONF} ]; then
		COUNT=`grep -c dkim=0 ${USER_CONF}`
		if [ "${COUNT}" -gt 0 ]; then
			echo "User ${D_USER} has dkim=0 set in ${USER_CONF}. Not setting dkim."
			exit 4;
		fi

		DOMAIN_CONF=/usr/local/directadmin/data/users/${D_USER}/domains/${DOMAIN}.conf
		if [ -s ${DOMAIN_CONF} ]; then
			COUNT=`grep -c dkim=0 ${DOMAIN_CONF}`
			if [ "${COUNT}" -gt 0 ]; then
				echo "Domain ${DOMAIN} has dkim=0 set in ${DOMAIN_CONF}. Not setting dkim."
				exit 5;
			fi
		fi	
	fi
fi

if [ ! -e ${PRIV_KEY} ] || [ ! -e ${PUB_KEY} ]; then
	openssl genrsa -out ${PRIV_KEY} 2048 2>&1
	openssl rsa -in ${PRIV_KEY} -out ${PUB_KEY} -pubout -outform PEM 2>&1
	chmod 600 ${PRIV_KEY} ${PUB_KEY}
	$CHOWN mail:mail ${PRIV_KEY} ${PUB_KEY}
fi

ADD_DNS=1
if [ $# = 2 ] && [ "$2" = "nodns" ]; then
	ADD_DNS=0
fi

if [ "$ADD_DNS" -eq 1 ]; then
	echo "action=rewrite&value=dkim&domain=${DOMAIN}&dns=yes" >> /usr/local/directadmin/data/task.queue
fi

exit 0;
