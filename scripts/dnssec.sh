#!/bin/sh

#This is not finished.
#Do not use

OS=`uname`

DA=/usr/local/directadmin/directadmin
if [ ! -s ${DA} ]; then
	echo "Cannot find DirectAdmin binary:";
	echo "  ${DA}";
	exit 1;
fi

DA_CONF=/usr/local/directadmin/conf/directadmin.conf
if [ ! -s ${DA_CONF} ]; then
	echo "Cannot find DirectAdmin Config File:";
	echo "  ${DA_CONF}";
	exit 2;
fi

TASK_Q=`${DA} c | grep ^taskqueuecb= | cut -d= -f2`
if [ "${TASK_Q}" = "" ]; then
	echo "Cannot task.queue.cb from:";
	echo "${DA} c | grep ^taskqueuecb=";
	exit 3;
fi
DATASKQ="/usr/local/directadmin/dataskq --custombuild"

BIND_PATH=/etc
NAMED_BIN=/usr/sbin/named
DNSSEC_KEYGEN=/usr/sbin/dnssec-keygen
DNSSEC_SIGNZONE=/usr/sbin/dnssec-signzone

if [ "${OS}" = "FreeBSD" ]; then
	BIND_PATH=/etc/namedb
	NAMED_BIN=/usr/local/sbin/named
	DNSSEC_KEYGEN=/usr/local/sbin/dnssec-keygen
	DNSSEC_SIGNZONE=/usr/local/sbin/dnssec-signzone
elif [ -e /etc/debian_version ]; then
	BIND_PATH=/etc/bind
fi

NAMED_PATH=`${DA} c | grep ^nameddir= | cut -d= -f2 2>/dev/null`
if [ "${NAMED_PATH}" = "" ]; then
	echo "Cannot find nameddir from:";
	echo "${DA} c | grep ^nameddir=";
	exit 3;
fi
DNSSEC_KEYS_PATH=${NAMED_PATH}

NAMED_CONF=${BIND_PATH}/named.conf
NAMED_CONF=`${DA} c | grep namedconfig= | cut -d= -f2`

if [ -e /etc/debian_version ] && [ -e /etc/bind/named.conf.options ]; then
	 NAMED_CONF=/etc/bind/named.conf.options
fi

if [ ! -s ${NAMED_BIN} ]; then
	echo "Cannot find ${NAMED_BIN}";
	exit 4;
fi

NAMED_VER=`${NAMED_BIN} -v | cut -d\  -f2 | cut -d- -f1 | cut -d. -f1,2`

BIND_KEYS_FILE=${BIND_PATH}/named.iscdlv.key

if [ ! -x ${DNSSEC_KEYGEN} ]; then
	echo "Cannot find ${DNSSEC_KEYGEN}. Please install dnssec tools";
	exit 12;
fi

ENC_TYPE=RSASHA1
if [ `$DNSSEC_KEYGEN -h 2>&1 | grep -c RSASHA256` -gt 0 ]; then
	ENC_TYPE=RSASHA256
fi

if [ ! -s ${DNSSEC_SIGNZONE} ]; then
	echo "Cannot find ${DNSSEC_SIGNZONE}. Please install dnssec tools";
	exit 13;
fi
HAS_SOA_FORMAT=0
SF=`${DNSSEC_SIGNZONE} -h 2>&1 | grep -c '\-N format:'`
if [ "${SF}" -gt 0 ]; then
	HAS_SOA_FORMAT=1
fi

SATZ=skip-add-to-zone
show_help()
{
	echo "Usage:";
	echo "  $0 install";
	echo "  $0 keygen <domain>"; # [${SATZ}]";
	echo "  $0 sign <domain>";
	echo "";
	echo "The ${SATZ} option will create the keys, but will not trigger the dataskq to add the keys to the zone.";
	echo "";
	exit 1;
}

if [ $# = 0 ]; then
	show_help;
fi

##################################################################################################################################################
#
# Installer code
#

ensure_bind_key()
{
	#http://ftp.isc.org/isc/bind9/keys/9.7/bind.keys.v9_7
	#http://ftp.isc.org/isc/bind9/keys/9.6/bind.keys.v9_6
	#http://ftp.isc.org/isc/bind9/keys/9.8/bind.keys.v9_8

	SERVER=http://ftp.isc.org/isc/bind9/keys
	BIND_KEYS_PATH=9.7/bind.keys.v9_7
	case "${NAMED_VER}" in
		9.2|9.3|9.4|9.5|9.6)	BIND_KEYS_PATH=9.6/bind.keys.v9_6
					;;
		9.7)			BIND_KEYS_PATH=9.7/bind.keys.v9_7
					;;
		9.8|9.9)		BIND_KEYS_PATH=9.8/bind.keys.v9_8
	esac

	BIND_KEYS_URL=${SERVER}/${BIND_KEYS_PATH}

	DL=0
	if [ ! -s ${BIND_KEYS_FILE} ]; then
		DL=1
	elif [ "`grep -c trusted-keys ${BIND_KEYS_FILE}`" -eq 0 ] && [ "`grep -c managed-keys ${BIND_KEYS_FILE}`" -eq 0 ]; then
		DL=1
	fi

	if [ "${DL}" -eq 1 ]; then
		wget -O ${BIND_KEYS_FILE} ${BIND_KEYS_URL}
	fi
}

ensure_named_conf()
{
	if [ ! -s "${NAMED_CONF}" ] || [ "${NAMED_CONF}" = "" ]; then
		echo "Cannot find ${NAMED_CONF}";
		exit 1;
	fi

	ADD_TO_NC=""

	if [ "`grep -c 'dnssec-enable yes' ${NAMED_CONF}`" -eq 0 ]; then
		ADD_TO_NC="${ADD_TO_NC}	dnssec-enable yes;
"
	fi

	if [ "`grep -c 'dnssec-validation yes' ${NAMED_CONF}`" -eq 0 ]; then
		ADD_TO_NC="${ADD_TO_NC}	dnssec-validation yes;
"
	fi

	if [ "`grep -c 'dnssec-lookaside auto' ${NAMED_CONF}`" -eq 0 ]; then
		ADD_TO_NC="${ADD_TO_NC}	dnssec-lookaside auto;
"
	fi

	if [ "`grep -c ${BIND_KEYS_FILE} ${NAMED_CONF}`" -eq 0 ]; then
		ADD_TO_NC="${ADD_TO_NC}	bindkeys-file \"${BIND_KEYS_FILE}\";
"
	fi

	if [ "${ADD_TO_NC}" = "" ]; then
		return;
	fi

	echo "Please add the following to the 'options { .... }' section of your ${NAMED_CONF}:";

	echo "${ADD_TO_NC}";
}


ensure_directadmin_conf()
{
	C=`grep -c ^dnssec= ${DA_CONF}`
	
	if [ "${C}" -gt 0 ]; then
		perl -pi -e 's/^dnssec=.*/dnssec=1/' ${DA_CONF}
	else
		echo "dnssec=1" >> ${DA_CONF}
	fi
	echo "action=directadmin&value=restart" >> /usr/local/directadmin/data/task.queue
}

do_install()
{
	ensure_bind_key;
	ensure_named_conf;
	ensure_directadmin_conf;
}

#
# End Installer Code
#
##################################################################################################################################################
#
# Key Gen Code
#

ensure_domain()
{
	DOMAIN=$1
	
	if [ "${DOMAIN}" = "" ]; then
		echo "Missing Domain";
		show_help;
	fi
	
	#check for valid domain
	DB_FILE=${NAMED_PATH}/${DOMAIN}.db
	if [ ! -s "${DB_FILE}" ]; then
		echo "Cannot find valid zone at ${DB_FILE}";
		exit 10;
	fi
}

ensure_keys_path()
{
	if [ ! -d ${DNSSEC_KEYS_PATH} ]; then
		mkdir ${DNSSEC_KEYS_PATH};
	fi
	
	if [ ! -d ${DNSSEC_KEYS_PATH} ]; then
		echo "Cannot find directory ${DNSSEC_KEYS_PATH}";
		exit 11;
	fi
}

do_keygen()
{
	DOMAIN=$1;
	
	ensure_domain "${DOMAIN}";
	ensure_keys_path;
	DB_FILE=${NAMED_PATH}/${DOMAIN}.db

	echo "Starting keygen process for $DOMAIN";

	cd ${DNSSEC_KEYS_PATH};

	#ZSK
	KEY_STR=`${DNSSEC_KEYGEN} -r /dev/urandom -a $ENC_TYPE -b 1024 -n ZONE ${DOMAIN}`
	
	K=${KEY_STR}.key
	P=${KEY_STR}.private
	if [ ! -s $K ] || [ ! -s $P ]; then
		echo "Cannot find ${DNSSEC_KEYS_PATH}/${K} or ${DNSSEC_KEYS_PATH}/${P}";
		exit 14;
	fi
	mv -f $K ${DOMAIN}.zsk.key
	mv -f $P ${DOMAIN}.zsk.private

	
	#KSK	
	KEY_STR=`${DNSSEC_KEYGEN} -r /dev/urandom -a $ENC_TYPE -b 2048 -n ZONE -f KSK ${DOMAIN}`
	RET=$?
	
	K=${KEY_STR}.key
	P=${KEY_STR}.private
	if [ ! -s $K ] || [ ! -s $P ]; then
		echo "Cannot find ${DNSSEC_KEYS_PATH}/${K} or ${DNSSEC_KEYS_PATH}/${P}";
		exit 15;
	fi
	mv -f $K ${DOMAIN}.ksk.key
	mv -f $P ${DOMAIN}.ksk.private

	echo "${DOMAIN} now has keys.";
	
	exit $RET;
}

#
# End Key Gen Code
#
##################################################################################################################################################
#
# Signing Code
#

do_sign()
{
	DOMAIN=$1;
	
	ensure_domain "${DOMAIN}";
	ensure_keys_path;
	DB_FILE=${NAMED_PATH}/${DOMAIN}.db

	echo "Starting signing process for $DOMAIN";
	
	cd ${DNSSEC_KEYS_PATH};

	ZSK=${DOMAIN}.zsk.key
	KSK=${DOMAIN}.ksk.key
	
	if [ ! -s ${ZSK} ] || [ ! -s ${KSK} ]; then
		echo "Cannot find ${ZSK} or ${KSK}";
		exit 16;
	fi

	#first, create a copy of the zone to work with.
	T=${DB_FILE}.dnssec_temp
	cat ${DB_FILE} > ${T}
	
	#add the key includes
	echo "\$include ${DNSSEC_KEYS_PATH}/${DOMAIN}.zsk.key;" >> ${T};
	echo "\$include ${DNSSEC_KEYS_PATH}/${DOMAIN}.ksk.key;" >> ${T};

	N_INC="-N INCREMENT"
	if [ "${HAS_SOA_FORMAT}" -eq 0 ]; then
		N_INC=""
	fi

	${DNSSEC_SIGNZONE} -l dlv.isc.org -r /dev/urandom -e +3024000 ${N_INC} -o ${DOMAIN} -k ${KSK} ${T} ${ZSK}
	RET=$?
	
	rm -f ${T}
	if [ -s ${T}.signed ]; then
		mv -f ${T}.signed ${DB_FILE}.signed
	else
		if [ "$RET" -eq 0 ]; then
			echo "cannot find ${T}.signed to rename to ${DB_FILE}.signed";
		fi
	fi
	
	exit $RET;
}

#
# End Signing Code
#
##################################################################################################################################################





case "$1" in
	install)	do_install;
			;;
	keygen)		do_keygen "$2" "$3";
			;;
	sign)		do_sign "$2";
			;;
	*)		show_help;
			;;
esac

exit 1;

