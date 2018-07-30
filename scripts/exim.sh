#!/bin/bash

#script to install exim and friends (majordomo)

SYSTEMD=no
SYSTEMDDIR=/etc/systemd/system
if [ -d ${SYSTEMDDIR} ] && [ -e /usr/bin/systemctl ]; then
	SYSTEMD=yes
fi

CB_OPTIONS=${DA_PATH}/custombuild/options.conf
CB_BUILD=/usr/local/directadmin/custombuild/build

SERVER=http://files.directadmin.com/services
if [ -s "${CB_OPTIONS}" ]; then
	DL=`grep ^downloadserver= ${CB_OPTIONS} | cut -d= -f2`
	if [ "${DL}" != "" ]; then
		SERVER=http://${DL}/services
	fi
fi

if [ -e /etc/exim.conf ]; then
	COUNT=`grep -c cPanel /etc/exim.conf`
	if [ "$COUNT" -gt 0 ]; then
		mv -f /etc/exim.conf /etc/exim.conf.cpanel
	fi
fi

if [ -s /etc/init.d/postfix ]; then
	/etc/init.d/postfix stop
	killall -9 master 2> /dev/null
fi

cd /usr/local/directadmin/scripts/packages
rpm -e --nodeps sendmail 2> /dev/null
rpm -e --nodeps postfix 2> /dev/null
rpm -e --nodeps dovecot 2> /dev/null
rm -f /etc/xinetd.d/smtp_psa 2> /dev/null
rm -f /etc/xinetd.d/smtps_psa 2> /dev/null
rm -f /etc/xinetd.d/popa3d 2> /dev/null
rm -f /etc/xinetd.d/popa3ds 2> /dev/null

if [ -e /etc/init.d/qmail ]; then
	/etc/init.d/qmail stop
	/sbin/chkconfig qmail off
	chmod 0 /etc/init.d/qmail
fi

if [ -e /etc/init.d/courier-imap ]; then
	/etc/init.d/courier-imap stop
	/sbin/chkconfig courier-imap off
	chmod 0 /etc/init.d/courier-imap
fi
rpm -e courier-imap 2> /dev/null

#our is /usr/sbin/dovecot
if [ -e /usr/local/sbin/dovecot ]; then
	chmod 0 /usr/local/sbin/dovecot
	mv /usr/local/sbin/dovecot /usr/local/sbin/dovecot.moved

	#this will only happen once, if it exists, since the dovecot binary is moved.
	if [ -e /etc/init.d/dovecot ]; then
		rm -f /etc/init.d/dovecot
	fi
fi

rpm -ivh --force --nodeps da_exim-*.rpm
COUNT=`rpm -q da_exim | grep -c da_exim`;
if [ $COUNT = 0 ]
then
	echo "*** exim not installed: aborting. ***";
        exit 1;
fi

#ensure permissions:
SPOOL=/var/spool/exim
if [ -e "$SPOOL" ]; then
	chown -R mail:mail $SPOOL
fi
LRE=/etc/logrotate.d/exim
if [ -s $LRE ]; then
	chmod 644 $LRE
fi


DOVECOT=0
CUSTOMBUILD=0
if [ -e /root/.custombuild ]; then
	CUSTOMBUILD=1

	OP=/usr/local/directadmin/custombuild/options.conf

	if [ -e $OP ]; then
		TDOVECOT=`grep -c dovecot=yes $OP`
	else
		TDOVECOT=1
	fi

	if [ "$TDOVECOT" -eq 1 ]; then
		DOVECOT=1
	fi
fi


#added August 24, 2010
#we're going to update the exim.conf files.
#patch if dovecot is on.  the 1=1 is so we can turn it off easily.
if [ "1" = "1" ]; then

        EC=/etc/exim.conf
        EP=/etc/exim.pl

        wget -O ${EC}.temp http://files.directadmin.com/services/exim.conf
        wget -O ${EP}.temp http://files.directadmin.com/services/exim.pl

        if [ -s ${EC}.temp ]; then
                cp -f ${EC}.temp ${EC}
                
		#this file may not exist yet.
		P=/usr/local/directadmin/custombuild/exim.conf.dovecot.patch
		if [ ! -s ${P} ]; then
			wget -O ${P} http://files.directadmin.com/services/exim.conf.dovecot.patch
		fi
		
		if [ "$DOVECOT" -eq 1 ] && [ -s ${P} ]; then
			echo "exim.sh: Patching ${EC} to maildir";
			patch -d/ -p0 < ${P}
		fi

		echo "";
		echo "*** Your /etc/exim.conf has been updated to the latest version ***";
		echo "";
        fi

        if [ -s ${EP}.temp ]; then
                cp -f ${EP}.temp ${EP}
                chmod 755 ${EP}
        fi
fi




if [ "$DOVECOT" -eq 0 ]; then
	rpm -ivh da_vm-pop3d-*.rpm
fi

tar xzf majordomo-*.tar.gz
cd ..
./majordomo.sh

if [ -e /etc/exim.key ]; then
	chown mail:mail /etc/exim.key
	chmod 600 /etc/exim.key
fi

#pop before smtp
if [ "${SYSTEMD}" = "yes" ]; then
	cp -f /usr/local/directadmin/scripts/da-popb4smtp.service ${SYSTEMDDIR}/
	systemctl daemon-reload
	systemctl enable da-popb4smtp.service
	systemctl start da-popb4smtp.service
	
	if [ ! -s /etc/systemd/system/exim.service ]; then
		wget -O /etc/systemd/system/exim.service ${SERVER}/custombuild/2.0/custombuild/configure/systemd/exim.service
		systemctl daemon-reload
		systemctl enable exim.service
	fi

	chkconfig exim off
	rm -f /etc/init.d/exim
else
	cp -f /usr/local/directadmin/data/templates/da-popb4smtp /etc/rc.d/init.d
	chmod 755 /etc/rc.d/init.d/da-popb4smtp
	/sbin/chkconfig da-popb4smtp reset
	/sbin/service da-popb4smtp start
fi

#ensure exim isn't broken or in need of compile.
EXIM_BIN=/usr/sbin/exim
EXIM_BROKEN=0
if [ ! -x ${EXIM_BIN} ]; then
	echo "Cannot find ${EXIM_BIN}.  Telling CB to compile exim."
	EXIM_BROKEN=1
fi
echo "Testing that exim is running correctly:"
${EXIM_BIN} -bV
RET=$?
if [ "${RET}" != 0 ]; then
	echo "Exim seems to be broken with return code ${RET}.  Telling CB to compile exim."
	EXIM_BROKEN=1
fi
if [ "${EXIM_BROKEN}" = "1" ] && [ ! -s ${CB_OPTIONS} ]; then
	echo ""
	echo "********************************************************"
	echo " Exim is broken, but we cannot find ${CB_OPTIONS} to set exim=yes.  Do this later to compile exim."
	echo "********************************************************"
	echo ""
	
fi
if [ "${EXIM_BROKEN}" = "1" ] && [ -s ${CB_OPTIONS} ]; then
	if [ -s ${CB_BUILD} ]; then
		echo "Exim is broken.  Setting CustomBuild to exim=yes so it gets compiled."
		${CB_BUILD} set exim yes
	fi
fi


SCRIPTPATH=/usr/local/directadmin/scripts

if [ "$DOVECOT" -eq 0 ]; then
	${SCRIPTPATH}/imapd.sh
fi

if [ "$CUSTOMBUILD" -eq 0 ]; then

	#Removed Nov 30, 2009
	#${SCRIPTPATH}/webmail.sh

	${SCRIPTPATH}/squirrelmail.sh

	wget -O ${SCRIPTPATH}/roundcube.sh http://files.directadmin.com/services/all/roundcube.sh
	chmod 755 ${SCRIPTPATH}/roundcube.sh
	${SCRIPTPATH}/roundcube.sh
fi

#${SCRIPTPATH}/spam.sh

