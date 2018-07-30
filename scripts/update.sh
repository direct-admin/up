#!/bin/bash

DA_PATH=/usr/local/directadmin
DA_SCRIPTS=${DA_PATH}/scripts
DA_TQ=${DA_PATH}/data/task.queue

#added new options to templates
#echo 'action=rewrite&value=httpd' >> $DA_TQ

echo "action=cache&value=showallusers" >> /usr/local/directadmin/data/task.queue
echo "action=cache&value=safemode" >> $DA_TQ
echo "action=convert&value=cronbackups" >> $DA_TQ
echo "action=convert&value=suspendedmysql" >> $DA_TQ
echo "action=syscheck" >> $DA_TQ

#get rid of the old mysql 3 to 4.0 conversion script: (it breaks 4.1+ systems)
FILE=$DA_SCRIPTS/mysql_fix_privilege_tables
if [ -e $FILE ]; then
	rm -f $FILE;
fi

if [ ! -d /usr/local/sysbk ]; then
	cd $DA_SCRIPTS
	./sysbk.sh
fi

#https://www.directadmin.com/features.php?id=1930
echo "action=da-popb4smtp&value=restart" >> $DA_TQ

#grep -H "usertype=reseller" /usr/local/directadmin/data/users/*/user.conf | cut -d/ -f7 > /usr/local/directadmin/data/admin/reseller.list
#chown diradmin:diradmin /usr/local/directadmin/data/admin/reseller.list
#chmod 600 /usr/local/directadmin/data/admin/reseller.list

echo "action=addoptions" >> $DA_TQ
rm -f /usr/local/directadmin/data/skins/*/ssi_test.html 2>/dev/null
perl -pi -e 's/trusted_users = mail:majordomo:apache$/trusted_users = mail:majordomo:apache:diradmin/' /etc/exim.conf

if [ -e /etc/logrotate.d ]; then
	if [ ! -e /etc/logrotate.d/directadmin ] && [ -e $DA_SCRIPTS/directadmin.rotate ]; then
		cp $DA_SCRIPTS/directadmin.rotate /etc/logrotate.d/directadmin
	fi

	if [ -e /etc/logrotate.d/directadmin ]; then
		C=`grep -c login.log /etc/logrotate.d/directadmin`
		if [ "$C" -eq 0 ]; then
			cp $DA_SCRIPTS/directadmin.rotate /etc/logrotate.d/directadmin
		fi
	fi	
fi

chmod 750 /etc/virtual/majordomo

${DA_SCRIPTS}/cron_deny.sh

if [ -s /etc/proftpd.conf ]; then
	perl -pi -e "s/userlog \"%u %b\"/userlog \"%u %b %m\"/" /etc/proftpd.conf
	perl -pi -e "s/userlog \"%u %b %m\"/userlog \"%u %b %m %a\"/" /etc/proftpd.conf
	
	#dont restart proftpd if it not on.
	HAS_PUREFTPD=`${DA_PATH}/directadmin c | grep ^pureftp= | cut -d= -f2`
	if [ "${HAS_PUREFTPD}" != "1" ]; then
		echo "action=proftpd&value=restart" >> /usr/local/directadmin/data/task.queue
	fi
fi

if [ -e /usr/share/spamassassin/72_active.cf ]; then
	perl -pi -e 's#header   FH_DATE_PAST_20XX.*#header   FH_DATE_PAST_20XX      Date =~ /20[2-9][0-9]/ [if-unset: 2006]#' /usr/share/spamassassin/72_active.cf
fi

if [ -e /etc/exim.key ]; then
        chown mail:mail /etc/exim.key
        chmod 600 /etc/exim.key
fi

UKN=/etc/virtual/limit_unknown
if [ ! -e $UKN ]; then
	echo 0 > $UKN;
	chown mail:mail $UKN
	chown mail:mail /etc/virtual/limit
fi
UL=/etc/virtual/user_limit
if [ ! -s ${UL} ]; then
	echo "0" > ${UL}
	chown mail:mail ${UL}
	chmod 644 ${UL}
fi

#debian if MySQL 5.5.11+
#april 21, 2011
if [ -e /etc/debian_version ]; then
			if [ -e /usr/local/directadmin/directadmin ]; then
				COUNT=`ldd /usr/local/directadmin/directadmin | grep -c libmysqlclient.so.16`
				if [ "${COUNT}" -eq 1 ]; then
					if [ ! -e /usr/local/mysql/lib/libmysqlclient.so.16 ] && [ -e /usr/local/mysql/lib/libmysqlclient.so.18 ]; then
						echo "*** Linking libmysqlclient.so.16 to libmysqlclient.so.18";
						ln -s libmysqlclient.so.18 /usr/local/mysql/lib/libmysqlclient.so.16
						ldconfig
					fi
				fi
				COUNT=`ldd /usr/local/directadmin/directadmin | grep -c libmysqlclient.so.18`
				if [ "${COUNT}" -eq 1 ]; then
					if [ ! -e /usr/local/mysql/lib/libmysqlclient.so.18 ] && [ -e /usr/local/mysql/lib/libmysqlclient.so.16 ]; then
						echo "*** Linking libmysqlclient.so.18 to libmysqlclient.so.16";
						ln -s libmysqlclient.so.16 /usr/local/mysql/lib/libmysqlclient.so.18
						ldconfig
					fi
				fi
			fi
fi

#DA 1.43.1
#http://www.directadmin.com/features.php?id=1453
echo "action=rewrite&value=filter" >> /usr/local/directadmin/data/task.queue


exit 0;
