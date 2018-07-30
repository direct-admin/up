#!/bin/sh
# This script is written by Martynas Bendorius and DirectAdmin
# It is used to move domain from one user to another
# Official DirectAdmin webpage: http://www.directadmin.com
# Usage:
# ./move_domain.sh <domain> <olduser> <newuser>

VERSION=0.3

OS=`uname`

MYUID=`/usr/bin/id -u`
if [ "$MYUID" != 0 ]; then
        echo "You require Root Access to run this script.";
        exit 0;
fi

if [ $# != 3 ]; then
	echo "Move Domain to User - v. $VERSION";
	echo "";
        echo "Usage:";
        echo "$0 <domain> <olduser> <newuser>";
        echo "you gave #$#: $0 $1 $2 $3";
        exit 0;
fi

DOMAIN=$1
OLD_USER=$2
NEW_USER=$3

TEMP="grep -e '^$OLD_USER:' /etc/passwd | cut -d: -f6"
OLD_HOME=`eval $TEMP`
TEMP="grep -e '^$NEW_USER:' /etc/passwd | cut -d: -f6"
NEW_HOME=`eval $TEMP`

OLD_DOMAIN_DIR=${OLD_HOME}/domains/${DOMAIN}
NEW_DOMAIN_DIR=${NEW_HOME}/domains/${DOMAIN}

DATA_USER_OLD=/usr/local/directadmin/data/users/${OLD_USER}/
DATA_USER_NEW=/usr/local/directadmin/data/users/${NEW_USER}/
USER_OLD=${DATA_USER_OLD}domains.list
USER_NEW=${DATA_USER_NEW}domains.list

APACHE_PUBLIC_HTML=`/usr/local/directadmin/directadmin c | grep apache_public_html | cut -d= -f2`

PERL=/usr/bin/perl

IP_SWAP=/usr/local/directadmin/scripts/ipswap.sh

ROOT_GROUP=root
if [ "${OS}" = "FreeBSD" ]; then
	ROOT_GROUP=wheel
fi

update_email_domain_dir()
{
	#/etc/virtual/domain.com
	DMNDIR=/etc/virtual/${DOMAIN}
	if [ ! -e ${DMNDIR} ] && [ -e ${DMNDIR}_off ]; then
		DMNDIR=${DMNDIR}_off
		echo "domain ${DOMAIN} is suspended using ${DMNDIR}";
	fi
	if [ ! -e ${DMNDIR} ]; then
		echo "Cannot find ${DMNDIR}, aborting swap of ${DMNDIR}."
		return;
	fi
	
	#passwd (doveoct)
	#aliases
	#filter (home path)
	#usage.cache
	#majordomo/list.aliases:	$OLD_USER@$DOMAIN
	#majordomo/lists/*:  		$OLD_USER@$DOMAIN
	
	
	#TEMP="$PERL -pi -e 's#${OLD_HOME}#${NEW_HOME}#' ${DMNDIR}/passwd"
	#eval $TEMP;
	
	OLD_GID=`/usr/bin/id -g mail`
	OLD_UID=`/usr/bin/id -u $OLD_USER`
	NEW_GID=`/usr/bin/id -g mail`
	NEW_UID=`/usr/bin/id -u $NEW_USER`

	#Firt find the uid/gid swap them.
	TEMP="perl -pi -e 's#:${OLD_UID}:${OLD_GID}::${OLD_HOME}/#:${NEW_UID}:${NEW_GID}::${NEW_HOME}/#' ${DMNDIR}/passwd"
	eval $TEMP;
	
	#/etc/virtual/domain.com/aliases
	
	TEMP="$PERL -pi -e 's/(^|\s|:)${OLD_USER}(:|\$|,)/\${1}${NEW_USER}\${2}/g' ${DMNDIR}/aliases"
	eval $TEMP;
	eval $TEMP; #for the case of admin:admin where there is no white space.  Needs to be run twice.

	TEMP="$PERL -pi -e 's#${OLD_HOME}#${NEW_HOME}#' ${DMNDIR}/filter"
	eval $TEMP;

	if [ -e ${DMNDIR}/usage.cache ]; then
		TEMP="$PERL -pi -e 's/^${OLD_USER}:/${NEW_USER}/' ${DMNDIR}/usage.cache"
		eval $TEMP;
	fi

	OLD_EMAIL=${OLD_USER}@${DOMAIN}
	NEW_EMAIL=${NEW_USER}@${DOMAIN}

	if [ -e ${DMNDIR}/majordomo ]; then
		TEMP="$PERL -pi -e 's/${OLD_EMAIL}/${NEW_EMAIL}/' ${DMNDIR}/majordomo/list.aliases";
		eval $TEMP
		TEMP="$PERL -pi -e 's/${OLD_EMAIL}/${NEW_EMAIL}/' ${DMNDIR}/majordomo/lists/*";
		eval $TEMP
	fi
}

update_email_settings()
{
	echo "Updating email settings."
	
	#/etc/virtual/domainowners
	#/etc/virtual/domain.com(_off) (this will be large)
	#/home/username/.spamassassin/user_spam/user@domain.com
	#/home/username/imap/domain.com
	#/var/spool/virtual/domain.com (permissions only)
	#/etc/dovecot/conf/sni/domain.com.conf
	
	#domainowners
	TEMP="$PERL -pi -e 's/^${DOMAIN}: ${OLD_USER}\$/${DOMAIN}: ${NEW_USER}/' /etc/virtual/domainowners"
	eval $TEMP

	#repeat for domain pointers too.
	#at this stage, the domain.com.pointers file has already been moved.
	for p in `cat /usr/local/directadmin/data/users/${NEW_USER}/domains/${DOMAIN}.pointers | cut -d= -f1`; do
	{
		TEMP="$PERL -pi -e 's/^${p}: ${OLD_USER}\$/${p}: ${NEW_USER}/' /etc/virtual/domainowners"
		eval $TEMP
	};
	done;
	
	#/etc/virtual/domain.com
	update_email_domain_dir
	
	#/home/username/.spamassassin/user_spam/user@domain.com
	OLD_SADIR=${OLD_HOME}/.spamassassin/user_spam
	NEW_SADIR=${NEW_HOME}/.spamassassin/user_spam
	#if it doesnt exist, dont bother
	if [ -e ${OLD_SADIR} ]; then
		mkdir -p $NEW_SADIR
		mv ${OLD_SADIR}/*@${DOMAIN} ${NEW_SADIR}/
		chown -R ${NEW_USER}:mail ${NEW_SADIR}
		chmod 771 ${NEW_SADIR}
		chmod 660 ${NEW_SADIR}/*		
	fi
	
	#/home/username/imap/domain.com
	OLD_IMAP=${OLD_HOME}/imap/${DOMAIN}
	NEW_IMAP=${NEW_HOME}/imap/${DOMAIN}
	if [ -e ${OLD_IMAP} ]; then
		if [ -e ${NEW_IMAP} ]; then
			echo "$NEW_IMAP already exists.. merging as best we can.";
			mv -f ${OLD_IMAP}/* ${NEW_IMAP}/
		else
			if [ ! -e "${NEW_HOME}/imap" ]; then
				mkdir -p ${NEW_HOME}/imap
				chown ${NEW_USER}:mail ${NEW_HOME}/imap
				chmod 770 ${NEW_HOME}/imap
			fi
			mv -f ${OLD_IMAP} ${NEW_IMAP}
		fi
		
		chown -R ${NEW_USER}:mail ${NEW_IMAP}
		chmod -R 770 ${NEW_IMAP}
	fi

	#symlinks for domain pointers
	for p in `cat /usr/local/directadmin/data/users/${NEW_USER}/domains/${DOMAIN}.pointers | cut -d= -f1`; do
	{
		ALIAS=${NEW_HOME}/imap/$p
		ln -s ${DOMAIN} ${ALIAS}
		chown -h ${NEW_USER}:mail ${ALIAS}
	};
	done;

	#/var/spool/virtual/domain.com (permissions only)
	VPV=/var/spool/virtual/${DOMAIN}
	if [ -e ${VPV} ]; then
		chown -R ${NEW_USER}:mail $VPV
	fi
	
	#/etc/dovecot/conf/sni/domain.com.conf
	SNI_CONF=/etc/dovecot/conf/sni/${DOMAIN}.conf
	if [ -s ${SNI_CONF} ]; then
		TEMP="/usr/bin/perl -pi -e 's#${DATA_USER_OLD}#${DATA_USER_NEW}#g' ${SNI_CONF}"
		eval $TEMP;
	fi
}

update_ftp_settings()
{
	echo "Updating ftp settings."

	#/etc/proftpd.passwd
	#/usr/local/directadmin/data/users/user/ftp.passwd
	#/etc/proftpd.vhosts.conf	
	
	#for the password files, we only chagne the user@domain.com accounts.
	#the system account isn't touched.
	
	OLD_GID=`/usr/bin/id -g $OLD_USER`
	OLD_UID=`/usr/bin/id -u $OLD_USER`
	NEW_GID=`/usr/bin/id -g $NEW_USER`
	NEW_UID=`/usr/bin/id -u $NEW_USER`

	#proftpd.passwd.  Firt find the uid/gid and homedir matchup and swap them.
	TEMP="perl -pi -e 's#:${OLD_UID}:${OLD_GID}:(domain|user|custom):${OLD_DOMAIN_DIR}#:${NEW_UID}:${NEW_GID}:\${1}:${NEW_DOMAIN_DIR}#' /etc/proftpd.passwd"
	eval $TEMP;
	
	#proftpd.passwd ... then whatever is leftover (eg, anonymous)
	TEMP="$PERL -pi -e 's#:${OLD_DOMAIN_DIR}#:${NEW_DOMAIN_DIR}#' /etc/proftpd.passwd"
	eval $TEMP
	
	
	
	#ftp.passwd ... this one is messier..
	#take all accounts with /home/user/domain/doamin.com in them, and move them to the new ftp.passwd, with the new home.
	
	OLD_FTP=/usr/local/directadmin/data/users/${OLD_USER}/ftp.passwd
	NEW_FTP=/usr/local/directadmin/data/users/${NEW_USER}/ftp.passwd
	TEMP_FTP=/usr/local/directadmin/data/users/${OLD_USER}/ftp.passwd.temp
	
	grep ":$OLD_DOMAIN_DIR" $OLD_FTP > $TEMP_FTP
	TEMP="$PERL -pi -e 's#:${OLD_DOMAIN_DIR}#:${NEW_DOMAIN_DIR}#' $TEMP_FTP"
	eval $TEMP
	
	cat $TEMP_FTP >> $NEW_FTP
	
	#now, take out the old paths
	grep -v ":$OLD_DOMAIN_DIR" $OLD_FTP > $TEMP_FTP
	mv -f $TEMP_FTP $OLD_FTP
	chown root:ftp $OLD_FTP
}

update_da_settings()
{
	echo "Moving domain data to the ${NEW_USER} user."
	mv -f ${OLD_DOMAIN_DIR} ${NEW_DOMAIN_DIR}
	mv -f /usr/local/directadmin/data/users/${OLD_USER}/domains/${DOMAIN}.* /usr/local/directadmin/data/users/${NEW_USER}/domains/

	echo "Setting ownership for ${DOMAIN} domain."
	chown -R ${NEW_USER}:${NEW_USER} ${NEW_DOMAIN_DIR}

	if [ "$APACHE_PUBLIC_HTML" -eq 1 ]; then
		echo "apache_public_html=1 is set, updating public_html and private_html in ${NEW_DOMAIN_DIR}";
		chmod 750 ${NEW_DOMAIN_DIR}/public_html ${NEW_DOMAIN_DIR}/private_html
		chgrp apache ${NEW_DOMAIN_DIR}/public_html ${NEW_DOMAIN_DIR}/private_html
	fi

	if [ -e ${NEW_DOMAIN_DIR}/stats ]; then
		echo "Setting stats directory ownership for ${DOMAIN} domain.";
		chown -R root:${ROOT_GROUP} ${NEW_DOMAIN_DIR}/stats
	fi

	echo "Removing domain from ${OLD_USER} user."
	$PERL -pi -e "s#^${DOMAIN}\n##g" ${USER_OLD}

	echo "Adding domain to ${NEW_USER} user."
	echo "${DOMAIN}" >> ${USER_NEW}
	$PERL -pi -e "s#/usr/local/directadmin/data/users/${OLD_USER}/#/usr/local/directadmin/data/users/${NEW_USER}/#g" /usr/local/directadmin/data/users/${NEW_USER}/domains/${DOMAIN}.*
	$PERL -pi -e "s#${OLD_HOME}/#${NEW_HOME}/#g" /usr/local/directadmin/data/users/${NEW_USER}/domains/${DOMAIN}.*

	#ensure the user.conf doesn't have the old domain. No need for new User, as they'd already have a default.
	USER_CONF=${DATA_USER_OLD}/user.conf
	C=`grep -c "^domain=${DOMAIN}\$" $USER_CONF`
	if [ "${C}" -gt 0 ]; then
		#figure out a new default domain.. 
		DEFAULT_DOMAIN=`cat ${USER_OLD} | head -n1`
		#may be filled.. may be empty.
		perl -pi -e "s/^domain=${DOMAIN}\$/domain=${DEFAULT_DOMAIN}/" ${USER_CONF}
		
		#if the new default domain exists, reset the ~/public_html link.
		PUB_LINK=${OLD_HOME}/public_html
		NEW_DEF_DOMAIN_DIR=${OLD_HOME}/domains/${DEFAULT_DOMAIN}/public_html
		NEW_DEF_DOMAIN_DIR_RELATIVE=./domains/${DEFAULT_DOMAIN}/public_html
		if [ -h "${PUB_LINK}" ] && [ "${DEFAULT_DOMAIN}" != "" ] && [ -d "${NEW_DEF_DOMAIN_DIR}" ]; then
			rm -f ${PUB_LINK}
			ln -s ${NEW_DEF_DOMAIN_DIR_RELATIVE} ${PUB_LINK}
			chown -h ${OLD_USER}:${OLD_USER} ${PUB_LINK}
		fi
		
	fi
	
	echo "Changing domain owner."
	for i in `ls /usr/local/directadmin/data/users/${NEW_USER}/domains/${DOMAIN}.conf`; do { $PERL -pi -e "s/username=${OLD_USER}/username=${NEW_USER}/g" $i; }; done;


	#ip swapping, if needed.
	#empty the domain.ip_list, except 1 IP.
	USER_PATH=/usr/local/directadmin/data/users/${NEW_USER}
	OLD_IP=`grep "^ip=" ${USER_PATH}/domains/${DOMAIN}.conf | cut -d= -f2`
	NEW_IP=`grep "^ip=" ${USER_PATH}/user.conf | cut -d= -f2`
	if [ "${OLD_IP}" != "${NEW_IP}" ]; then
		echo "The old IP (${OLD_IP}) does not match the new IP (${NEW_IP}). Swapping...";
		#./ipswap.sh <oldip> <newip> [<file>]
		$IP_SWAP $OLD_IP $NEW_IP ${USER_PATH}/domains/${DOMAIN}.conf
		$IP_SWAP $OLD_IP $NEW_IP ${USER_PATH}/domains/${DOMAIN}.ftp

		if [ "${OS}" = "FreeBSD" ]; then
			$IP_SWAP $OLD_IP $NEW_IP /etc/namedb/${DOMAIN}.db
		else
		if [ -e /etc/debian_version ]; then
			$IP_SWAP $OLD_IP $NEW_IP /etc/bind/${DOMAIN}.db
		else
			$IP_SWAP $OLD_IP $NEW_IP /var/named/${DOMAIN}.db
		fi
		fi

		echo "${NEW_IP}" > ${USER_PATH}/domains/${DOMAIN}.ip_list

		#update the serial:
		echo "action=rewrite&value=named&domain=${DOMAIN}" >> /usr/local/directadmin/data/task.queue
	fi

	#Update .htaccess files in case there is a protected password directory.
	PROTECTED_LIST=${NEW_DOMAIN_DIR}/.htpasswd/.protected.list
	if [ -s "${PROTECTED_LIST}" ]; then
		echo "Updating protected directories via ${PROTECTED_LIST}";
		for i in `cat ${PROTECTED_LIST}`; do
		{
			D=$NEW_HOME/$i
			if [ ! -d ${D} ]; then
				echo "Cannot find a directory at ${D}";
				continue;
			fi
			
			HTA=${D}/.htaccess
			if [ ! -s ${HTA} ]; then
				echo "${HTA} appears to be empty.";
				continue;
			fi
	
			$PERL -pi -e "s#AuthUserFile ${OLD_HOME}/#AuthUserFile ${NEW_HOME}/#" ${HTA}
		};
		done;
	fi

	#complex bug: if multi-ip was used, should go into the zone and surgically remove the old ips from the zone, leaving only the NEW_IP.


	#this is needed to update "show all users" cache.
	echo "action=cache&value=showallusers" >> /usr/local/directadmin/data/task.queue
	#this is needed to rewrite /usr/local/directadmin/data/users/USERS/httpd.conf
	echo "action=rewrite&value=httpd" >> /usr/local/directadmin/data/task.queue
	/usr/local/directadmin/dataskq d

}

update_awstats()
{
	TEMP="/usr/bin/perl -pi -e 's#/home/${OLD_USER}/#/home/${NEW_USER}/#g' /home/${NEW_USER}/domains/${DOMAIN}/awstats/.data/*.conf"
	eval $TEMP;

	TEMP="/usr/bin/perl -pi -e 's#/home/${OLD_USER}/#/home/${NEW_USER}/#g' /home/${NEW_USER}/domains/${DOMAIN}/awstats/awstats.pl"
	eval $TEMP;

	#And for subdomains:
	TEMP="/usr/bin/perl -pi -e 's#/home/${OLD_USER}/#/home/${NEW_USER}/#g' /home/${NEW_USER}/domains/${DOMAIN}/awstats/*/.data/*.conf"
	eval $TEMP;

	TEMP="/usr/bin/perl -pi -e 's#/home/${OLD_USER}/#/home/${NEW_USER}/#g' /home/${NEW_USER}/domains/${DOMAIN}/awstats/*/awstats.pl"
	eval $TEMP;
}

doChecks()
{
	if [ ! -e ${USER_OLD} ]; then
		echo "File ${USER_OLD} does not exist. Can not continue."
		exit 1;
	fi
	
	if [ "${DOMAIN}" = "" ]; then
		echo "The domain is blank";
		exit 1;
	fi
	
	if [ "${OLD_HOME}" = "" ]; then
		echo "the old home is blank";
		exit 1;
	fi
	
	if [ "${NEW_HOME}" = "" ]; then
		echo "the new home is blank";
		exit 1;
	fi 

	if [ ! -e ${USER_NEW} ]; then
		echo "File ${USER_NEW} does not exist. Can not continue."
		exit 1;
	fi

	if [ "`grep -wc ${DOMAIN} $USER_OLD`" = "0" ]; then
		echo "Domain ${DOMAIN} is not owned by ${OLD_USER} user."
		exit 1;
	fi

	if [ ! -d ${OLD_DOMAIN_DIR} ]; then
		echo "Direcory ${OLD_DOMAIN_DIR} does not exist. Can not continue."
		exit 1;
	fi

	if [ -d ${NEW_DOMAIN_DIR} ]; then
		echo "Direcory ${NEW_DOMAIN_DIR} exists. Can not continue."
		exit 1;
	fi

	if [ ! -e $PERL ]; then
		echo "$PERL does not exist.";
		exit 1;
	fi
}

doChecks
update_da_settings
update_email_settings
update_ftp_settings
update_awstats

echo "Domain has been moved to ${NEW_USER} user."

exit 0;
