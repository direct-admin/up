#!/bin/sh

#script to add an email account to DirectAdmin via command line.

MYUID=`/usr/bin/id -u`
if [ "$MYUID" != 0 ]; then
	echo "You require Root Access to run this script";
	exit 1;
fi

if [ "$#" -lt 4 ]; then
	echo "Usage:";
	echo "   $0 <user> <domain> '<cryptedpass>' <plaintext> <quota>";
	echo "";
	echo "Where the cryptedpass can either be an MD5/DES password";
	echo "If plaintext is set to 1, then it can be a raw password";
	echo "Else, set plaintext to 0 to use the provided crypted pass."
	echo "quota, in bytes. Use 0 for unlimited";
	echo "";
	echo "The domain must already exist under a DA account";
	exit 2;
fi

EMAIL=$1
DOMAIN=$2
PASS=$3
PLAIN=$4
QUOTAVAL=$5

DAUSER=`grep "^${DOMAIN}:" /etc/virtual/domainowners | awk '{print $2;}'`
UHOME=`grep "^${DAUSER}:" /etc/passwd | cut -d: -f6`

DOMAINCONF=/usr/local/directadmin/data/users/${DAUSER}/domains/${DOMAIN}.conf
if [ ! -e ${DOMAINCONF} ]; then
	echo "Cannot find ${DOMAINCONF}";
	echo "Make sure the domain exists and is set in the /etc/virtual/domainowners file";
	exit 3;
fi

PASSWD=/etc/virtual/${DOMAIN}/passwd
QUOTA=/etc/virtual/${DOMAIN}/quota
if [ ! -e ${PASSWD} ]; then
	echo "Cannot find ${PASSWD}. Make sure the domain exists";
	exit 4;
fi

DOVECOT=`/usr/local/directadmin/directadmin c | grep ^dovecot= | cut -d= -f2`
if [ "${DOVECOT}" != 0 ]; then
	DOVECOT=1;
fi

COUNT=`grep -c "^${EMAIL}:" ${PASSWD}`
if [ "${COUNT}" = 0 ]; then
	PASSVALUE=$PASS
	if [ ${PLAIN} = 1 ]; then
		#encode the password.
		PASSVALUE=`echo "$PASS" | /usr/bin/openssl passwd -1 -stdin`
	fi

	if [ "${DOVECOT}" = 1 ]; then
		UUID=`id -u ${DAUSER}`
		MGID=`id -g mail`
		

		echo "${EMAIL}:${PASSVALUE}:${UUID}:${MGID}::${UHOME}/imap/${DOMAIN}/${EMAIL}:/bin/false" >> ${PASSWD}
	else
		echo "${EMAIL}:${PASSVALUE}" >> ${PASSWD}
	fi
	
	echo "Added ${EMAIL} to ${PASSWD}";
else
	echo "${EMAIL} already exists in ${PASSWD}. Not adding it to passwd.";
fi

#quota
if [ -e ${QUOTA} ]; then
	COUNT=`grep -c "^${EMAIL}:" ${QUOTA}`
	if [ "${COUNT}" = 0 ]; then
		echo "${EMAIL}:${QUOTAVAL}" >> ${QUOTA}
	fi
fi

#ensure path exists for it.
if [ "${DOVECOT}" = 1 ]; then
	USERDIR=${UHOME}/imap/${DOMAIN}/${EMAIL}
	
	mkdir --mode=770 -p $USERDIR/Maildir/new
	mkdir --mode=770 -p $USERDIR/Maildir/cur
	
	chown -R ${DAUSER}:mail ${USERDIR}
	chmod 770 ${USERDIR} ${USERDIR}/Maildir
fi

exit 0;
