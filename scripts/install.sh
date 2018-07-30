#!/bin/sh

#This is the installer script. Run this and follow the directions


DA_SCRIPTS="/usr/local/directadmin/scripts"
CB_OPTIONS=/usr/local/directadmin/custombuild/options.conf
DA_CRON=${DA_SCRIPTS}"/directadmin_cron"
VIRTUAL="/etc/virtual"

CMD_LINE=$1

cd ${DA_SCRIPTS}

SYSTEMD=no
SYSTEMDDIR=/etc/systemd/system
if [ -d ${SYSTEMDDIR} ] && [ -e /usr/bin/systemctl ]; then
	SYSTEMD=yes
fi

#Create the diradmin user
createDAbase() {
	mkdir -p /usr/local/directadmin
	/usr/sbin/useradd -d /usr/local/directadmin -r -s /bin/false diradmin 2> /dev/null
	chmod -f 755 /usr/local/directadmin
	chown -f diradmin:diradmin /usr/local/directadmin;

	mkdir -p /var/log/directadmin
	mkdir -p /usr/local/directadmin/conf
	chown -f diradmin:diradmin /usr/local/directadmin/*;
	chown -f diradmin:diradmin /var/log/directadmin;
	chmod -f 700 /usr/local/directadmin/conf; chmod -f 700 /var/log/directadmin;
	if [ -e /etc/logrotate.d ]; then
		cp $DA_SCRIPTS/directadmin.rotate /etc/logrotate.d/directadmin
		chmod 644 /etc/logrotate.d/directadmin
	fi

	chown -f diradmin:diradmin /usr/local/directadmin/conf/* 2> /dev/null;
	chmod -f 600 /usr/local/directadmin/conf/* 2> /dev/null;

	mkdir -p /var/log/httpd/domains
	chmod 710 /var/log/httpd/domains
	chmod 710 /var/log/httpd

	mkdir -p /home/tmp
	chmod -f 1777 /home/tmp
	/bin/chmod 711 /home

	mkdir -p /var/www/html
	chmod 755 /var/www/html

	SSHROOT=`cat /etc/ssh/sshd_config | grep -c 'AllowUsers root'`;

	if [ $SSHROOT = 0 ]
	then
		echo "" >> /etc/ssh/sshd_config
		echo "AllowUsers root" >> /etc/ssh/sshd_config
		chmod 710 /etc/ssh
	fi
}

#After everything else copy the directadmin_cron to /etc/cron.d
copyCronFile() {
	if [ -s ${DA_CRON} ] ; then
		mkdir -p /etc/cron.d
		cp ${DA_CRON} /etc/cron.d/;
		chmod 600 /etc/cron.d/directadmin_cron
		chown root /etc/cron.d/directadmin_cron
	else
		echo "Could not find ${DA_CRON} or it is empty";
	fi
	
	CRON_BOOT=/etc/init.d/crond
	if [ -d /etc/systemd/system ]; then
		CRON_BOOT=/usr/lib/systemd/system/crond.service
	fi

	if [ ! -s ${CRON_BOOT} ]; then
		echo "";
		echo "****************************************************************************";
		echo "* Cannot find ${CRON_BOOT}.  Ensure you have cronie installed";
		echo "    yum install cronie";
		echo "****************************************************************************";
		echo "";
	else
		if [ -d /etc/systemd/system ]; then
			systemctl daemon-reload
			systemctl enable crond.service
			systemctl restart crond.service
		else
			${CRON_BOOT} restart
			/sbin/chkconfig crond on
		fi
	fi
}

#Copies the startup scripts over to the /etc/rc.d/init.d/ folder 
#and chkconfig's them to enable them on bootup
copyStartupScripts() {
	if [ "${SYSTEMD}" = "yes" ]; then
		cp -f directadmin.service ${SYSTEMDDIR}/
		cp -f startips.service ${SYSTEMDDIR}/
		
		systemctl daemon-reload

		systemctl enable directadmin.service
		systemctl enable startips.service
	else
		cp -f directadmin /etc/rc.d/init.d/
		cp -f startips /etc/rc.d/init.d/
		/sbin/chkconfig directadmin reset
		/sbin/chkconfig startips reset
	fi
}

#touch exim's file inside /etc/virtual
touchExim() {
	mkdir -p ${VIRTUAL};
	chown -f mail ${VIRTUAL};
	chgrp -f mail ${VIRTUAL};
	chmod 755 ${VIRTUAL};

	echo "`hostname`" >> ${VIRTUAL}/domains;

	if [ ! -s ${VIRTUAL}/limit ]; then
		echo "1000" > ${VIRTUAL}/limit
	fi
	if [ ! -s ${VIRTUAL}/limit_unknown ]; then
		echo "0" > ${VIRTUAL}/limit_unknown
	fi
	if [ ! -s ${VIRTUAL}/user_limit ]; then
		echo "200" > ${VIRTUAL}/user_limit
	fi

	chmod 755 ${VIRTUAL}/*

	mkdir ${VIRTUAL}/usage
	chmod 750 ${VIRTUAL}/usage

	for i in domains domainowners pophosts blacklist_domains whitelist_from use_rbl_domains bad_sender_hosts bad_sender_hosts_ip blacklist_senders whitelist_domains whitelist_hosts whitelist_hosts_ip whitelist_senders skip_av_domains skip_rbl_domains; do
        	touch ${VIRTUAL}/$i;
        	chmod 600 ${VIRTUAL}/$i;
	done

	chown -f mail:mail ${VIRTUAL}/*;	
}


#get setup data
doGetInfo() {
	if [ ! -e ./setup.txt ]
	then
		./getInfo.sh
	fi
}

getLicense() {
	userid=`cat ./setup.txt | grep uid= | cut -d= -f2`;
	liceid=`cat ./setup.txt | grep lid= | cut -d= -f2`;
	ip=`cat ./setup.txt | grep ip= | cut -d= -f2`;

	LAN=0
	if [ -s /root/.lan ]; then
        	LAN=`cat /root/.lan`
	fi

	if [ "$LAN" -eq 1 ]; then
		$DA_SCRIPTS/getLicense.sh ${userid} ${liceid}
	else
		$DA_SCRIPTS/getLicense.sh ${userid} ${liceid} ${ip}
	fi

	if [ $? -ne 0 ]; then
		exit 1;
	fi

#	wget https://www.directadmin.com/cgi-bin/licenseupdate?lid=${liceid}\&uid=${userid} -O /usr/local/directadmin/conf/license.key --bind-address=${ip} 2> /dev/null
#	if [ $? -ne 0 ]
#	then
#		echo "Error downloading the license file";
#		exit 1;
#	fi
#
#	COUNT=`cat /usr/local/directadmin/conf/license.key | grep -c "* You are not allowed to run this program *"`;
#
#	if [ $COUNT -ne 0 ]
#	then
#		echo "You are not authorized to download the license with that client id and license id. Please email sales@directadmin.com";
#		exit 1;
#	fi
}

doSetHostname() {
	HN=`cat ./setup.txt | grep hostname= | cut -d= -f2`;
	
	/usr/local/directadmin/scripts/hostname.sh ${HN}

	#/sbin/service network restart 
}

checkMD5()
{
	MD5SUM=/usr/bin/md5sum
	MD5_FILE=$1
	MD5_CHECK=${MD5_FILE}.md5

	if [ ! -s "${MD5SUM}" ]; then
		echo "Cannot find $MD5SUM to check $MD5_FILE";
		return;
	fi

	if [ ! -s "${MD5_FILE}" ]; then
		echo "Cannot find ${MD5_FILE} or it is empty";
		return;
	fi

	if [ ! -s "${MD5_CHECK}" ]; then
		echo "Cannot find ${MD5_CHECK} or it is empty";
		return;
	fi

	echo "";
	echo -n "Checking MD5sum on $MD5_FILE ... ";

	LOCAL_MD5=`${MD5SUM} ${MD5_FILE} | cut -d\  -f1`
	CHECK_MD5=`cat ${MD5_CHECK} | cut -d\  -f1`

	if [ "${LOCAL_MD5}" = "${CHECK_MD5}" ]; then
		echo "Pass";
	else
		echo "Failed.  Consider deleting $MD5_FILE and $MD5_CHECK then try again";

		echo "";
		echo "";

		sleep 5;
	fi
}

getServices() {
	SERVICES_FILE=${DA_SCRIPTS}/packages/services.tar.gz

	if [ -s "{$SERVICES_FILE}" ]; then
		if [ -s "${SERVICES_FILE}.md5" ]; then
			checkMD5 ${SERVICES_FILE}
		fi

		echo "Services file already exists.  Assuming its been extracted, skipping...";

		return;
	fi

	servfile=`cat ./setup.txt | grep services= | cut -d= -f2`;

	DL_SERVER=files.directadmin.com	
	if [ -e $CB_OPTIONS ]; then
		DLS=`grep downloadserver $CB_OPTIONS | cut -d= -f2`;
		if [ "${DLS}" != "" ]; then
			DL_SERVER=${DLS}
		fi
	fi

	#get the md5sum
	wget http://${DL_SERVER}/services/${servfile}.md5 -O ${SERVICES_FILE}.md5
	if [ ! -s ${SERVICES_FILE}.md5 ];
	then
		echo "";
		echo "failed to get md5 file: ${SERVICES_FILE}.md5";
		echo "";
		sleep 4;
	fi

	wget http://${DL_SERVER}/services/${servfile} -O $SERVICES_FILE
	if [ $? -ne 0 ]
	then
		echo "Error downloading the services file";
		exit 1;
	fi

	#we have md5, lets use it.
	if [ -s ${SERVICES_FILE}.md5 ]; then
		checkMD5 ${SERVICES_FILE}
	fi

	echo "Extracting services file...";

	tar xzf $SERVICES_FILE  -C ${DA_SCRIPTS}/packages
	if [ $? -ne 0 ]
	then
		echo "Error extracting services file";
		exit 1;
	fi
}

doMySQL() {
	rootpass=`cat ./setup.txt | grep mysql= | cut -d= -f2`;
	dbuser=`cat ./setup.txt | grep mysqluser= | cut -d= -f2`;
	userpass=`cat ./setup.txt | grep adminpass= | cut -d= -f2`;

	./mysql.sh $rootpass $dbuser $userpass $CMD_LINE;
}

./doChecks.sh;
if [ $? -ne 0 ]
then
	exit 1;
fi

doGetInfo
doSetHostname
createDAbase
copyStartupScripts
#copyCronFile #moved lower, after custombuild, march 7, 2011
touchExim

./fstab.sh
${DA_SCRIPTS}/cron_deny.sh

getLicense
getServices

if [ ! -e /usr/local/directadmin/custombuild/options.conf ] && [ -e /etc/redhat-release ] && [ ! -e /etc/init.d/xinetd ] && [ -e /usr/bin/yum ]; then
	yum -y install xinetd
	/sbin/chkconfig xinetd on
	/sbin/service xinetd start
fi

doMySQL

cd ${DA_SCRIPTS}
./phpMyAdmin.sh
cp -f ${DA_SCRIPTS}/redirect.php /var/www/html/redirect.php

${DA_SCRIPTS}/proftpd.sh
${DA_SCRIPTS}/exim.sh

${DA_SCRIPTS}/sysbk.sh
if [ ! -e "/usr/bin/ncftpput" ]; then
       ${DA_SCRIPTS}/ncftp.sh
fi

ADMINNAME=`cat ./setup.txt | grep adminname= | cut -d= -f2`;
/usr/sbin/userdel -r $ADMINNAME;
/bin/rm -rf /usr/local/directadmin/data/users/${ADMINNAME};

${DA_SCRIPTS}/customapache.sh
if [ $? -ne 0 ]
then
	copyCronFile
        exit 1;
fi

chown webapps:webapps /var/www/html/redirect.php

#moved here march 7, 2011
copyCronFile

if [ ! -e /usr/local/bin/php ]; then
        echo "*******************************************";
        echo "*******************************************";
        echo "";
        echo "Cannot find /usr/local/bin/php";
        echo "Please recompile php with custombuild, eg:";
        echo "cd /usr/local/directadmin/custombuild";
        echo "./build all d";
        echo "";
        echo "*******************************************";
        echo "*******************************************";

	exit 1;
fi


cd /usr/local/directadmin
./directadmin i

cd /usr/local/directadmin
./directadmin p



echo "";
echo "System Security Tips:";
echo "  http://help.directadmin.com/item.php?id=247";
echo "";

DACONF=/usr/local/directadmin/conf/directadmin.conf
if [ ! -s $DACONF ]; then
	echo "";
	echo "*********************************";
	echo "*";
	echo "* Cannot find $DACONF";
	echo "* Please see this guide:";
	echo "* http://help.directadmin.com/item.php?id=267";
	echo "*";
	echo "*********************************";
	exit 1;
fi

exit 0;
