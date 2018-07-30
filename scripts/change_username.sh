#!/bin/sh
#VERSION=2.0
#
# Script used to change the name of a user
#
# Usage: change_username.sh

VERBOSE=1

MAX_LENGTH=10
DA_BIN=/usr/local/directadmin/directadmin
if [ -s "$DA_BIN" ]; then
	VAL=`/usr/local/directadmin/directadmin c |grep '^max_username_length=' | cut -d= -f2`
	if [ "$VAL" != "" ]; then
		if [ "$VAL" -gt 0 ]; then
			MAX_LENGTH=$VAL
		fi
	fi
fi

SYSTEMD=no
SYSTEMDDIR=/etc/systemd/system
if [ -d ${SYSTEMDDIR} ] && [ -e /usr/bin/systemctl ]; then
	SYSTEMD=yes
fi

show_help()
{
	echo "DirectAdmin username changing script (Beta)";
	echo "";
	echo "Usage: $0 oldusername newusername";
	echo "";
}

OS=`uname`;

HOME_PATH=/home

str_len()
{
	echo ${#1}
}

ensure_user()
{
	/usr/bin/id $1 1>/dev/null 2>/dev/null
	if [ $? != 0 ]; then
		echo "Cannot find user $1";
		exit 2;
	fi
}

prevent_user()
{
        /usr/bin/id $1 1>/dev/null 2>/dev/null
        if [ $? = 0 ]; then
                echo "User $1 already exists";
                exit 4;
        fi

	LEN=`str_len $1`
	if [ "$LEN" != "" ]; then
		if [ "$LEN" -gt "$MAX_LENGTH" ]; then
			echo "User $1 is $LEN characters long.";
			echo "The current max is:";
			echo "max_username_length=$MAX_LENGTH";
			exit 5;
		fi
	fi
}

#rename cron files and spool files else they'll be removed
#when account is removed.
#redhat does /var/spool/mail/user for us
move_spool_cron()
{
	if [ "$OS" = "FreeBSD" ]; then
		mv -f /var/mail/$1 /var/mail/$2 2>/dev/null
		mv -f /var/cron/tabs/$1 /var/cron/tabs/$2 2>/dev/null
	else
		mv -f /var/spool/cron/$1 /var/spool/cron/$2 2>/dev/null
	fi
}

system_swap()
{
	OHOME=`grep -e "^${1}:" /etc/passwd | cut -d: -f6`

	echo "Killing User processes:"
	/usr/bin/killall -s SIGKILL -u "$1"
	
	if [ "$OS" = "FreeBSD" ]; then
		#have to add a new user to the same id, then remove the other user
		OUID=`grep -e "^${1}:" /etc/passwd | cut -d: -f3`
		OGID=`grep -e "^${1}:" /etc/passwd | cut -d: -f4`
		OPASS=`grep -e "^${1}:" /etc/master.passwd | cut -d: -f2`
		OSHELL=`grep -e "^${1}:" /etc/passwd | cut -d: -f7`
		
		#some FreeBSD's don't support -H
		#echo $OPASS | /usr/sbin/pw useradd -n $2 -s $OSHELL -o -w no -u $OUID -g $OGID -H 0

		/usr/sbin/pw useradd -n $2 -s $OSHELL -o -w no -u $OUID -g $OGID
		chpass -p $OPASS $2

		#now do the group
		pw groupmod $1 -l $2 -q

	else
		/usr/sbin/usermod -l $2 -d $HOME_PATH/$2 $1

		#now do the group
		/usr/sbin/groupmod -n $2 $1
	fi

	ensure_user $2

	move_spool_cron $1 $2

	if [ "$OS" = "FreeBSD" ]; then
		pw userdel $1
	fi

	NHOME=`grep -e "^${2}:" /etc/passwd | cut -d: -f6`

	mv -f $OHOME $NHOME

	#update sshd_config if user exists:
	TEMP="/usr/bin/perl -pi -e 's/AllowUsers ${1}\$/AllowUsers ${2}/' /etc/ssh/sshd_config"
	eval $TEMP;
}

security_check()
{
	if [ "$1" = "root" ]; then
		echo "Are you mad? we don't play with root here. He's not nice.";
		exit 5;
	fi

	for i in all action value domain email type root mail jail creator diradmin majordomo start stop reload restart demo_user demo_reseller demo_admin demo type backup log www apache mysql tmp test; do
	{
		if [ "$1" = "$i" ]; then
			echo "$1 is a reserved username, please choose another";
			exit 5;
		fi
	};
	done;

	if [ "$1" = "" ]; then
		echo "blank user..make sure you've passed 2 usernames";
		exit 6;
	fi
	
	if [ ! -e /usr/bin/perl ]; then
		echo "/usr/bin/perl does not exist";
		exit 7;
	fi
}

generic_swap()
{
	TEMP="/usr/bin/perl -pi -e 's/(^|[\s=\/:])${1}([\s\/:]|\$)/\${1}${2}\${2}/g' $3"
	eval $TEMP;
}

mailing_list_swap()
{
	TEMP="/usr/bin/perl -pi -e 's/([\s:])${1}([\s@]|\$)/\${1}${2}\${2}/g' $3"
	eval $TEMP;
}

ftp_pass_swap()
{
        TEMP="/usr/bin/perl -pi -e 's/(^)${1}([:])/\${1}${2}\${2}/g' $3"
        eval $TEMP;
        TEMP="/usr/bin/perl -pi -e 's#/home/${1}([:\/])#/home/${2}\${1}#g' $3"
        eval $TEMP;
}

awstats_swap()
{
	#its called after system_swap, so we do it on user $2.
	TEMP="/usr/bin/perl -pi -e 's#/home/${1}/#/home/${2}/#g' /home/${2}/domains/*/awstats/.data/*.conf"
        eval $TEMP;

	TEMP="/usr/bin/perl -pi -e 's#/home/${1}/#/home/${2}/#g' /home/${2}/domains/*/awstats/awstats.pl"
	eval $TEMP;
}

email_swap()
{
	#/etc/virtual/domainowners
	#/etc/virtual/

	DATA_USER_OLD=/usr/local/directadmin/data/users/${1}/
	DATA_USER_NEW=/usr/local/directadmin/data/users/${2}/
	
	generic_swap $1 $2 /etc/virtual/domainowners
	
	for i in `cat /usr/local/directadmin/data/users/$1/domains.list`; do
	{
		#check for suspended domains
		if [ ! -e /etc/virtual/$i ]; then
			if [ -e /etc/virtual/${i}_off ]; then
				i=${i}_off
			fi
		fi
	
		generic_swap $1 $2 /etc/virtual/$i/aliases
		generic_swap $1 $2 /etc/virtual/$i/autoresponder.conf
		generic_swap $1 $2 /etc/virtual/$i/filter
		generic_swap $1 $2 /etc/virtual/$i/vacation.conf

		#the dovecot passwd file uses the same format as the ftp.passwd file.
		ftp_pass_swap $1 $2 /etc/virtual/$i/passwd
		
		if [ -e /etc/virtual/$i/reply/$1.msg ]; then
			mv -f /etc/virtual/$i/reply/$1.msg /etc/virtual/$i/reply/$2.msg
		fi
		if [ -e /etc/virtual/$i/reply/$1.msg_off ]; then
			mv -f /etc/virtual/$i/reply/$1.msg_off /etc/virtual/$i/reply/$2.msg_off
		fi
		if [ -e /etc/virtual/$i/majordomo ]; then
			mailing_list_swap $1 $2 /etc/virtual/$i/majordomo/list.aliases
			mailing_list_swap $1 $2 /etc/virtual/$i/majordomo/private.aliases
		fi
		
		#/etc/dovecot/conf/sni/domain.com.conf
		SNI_CONF=/etc/dovecot/conf/sni/${i}.conf
		if [ -s ${SNI_CONF} ]; then
			TEMP="/usr/bin/perl -pi -e 's#${DATA_USER_OLD}#${DATA_USER_NEW}/#g' ${SNI_CONF}"
			eval $TEMP;
		fi
	};
	done;
}

ftp_path_swap()
{
	TEMP="/usr/bin/perl -pi -e 's#users/${1}/ftp.passwd#users/${2}/ftp.passwd#g' $3"
	eval $TEMP;
}

ftp_swap()
{
	#/etc/proftpd.passwd
	#/etc/proftpd.vhosts.conf
	ftp_path_swap $1 $2 /etc/proftpd.vhosts.conf
	ftp_pass_swap $1 $2 /etc/proftpd.passwd
	ftp_pass_swap $1 $2 /usr/local/directadmin/data/users/$1/ftp.passwd

	TEMP="/usr/bin/perl -pi -e 's#users/${1}/#users/${2}/#g' /usr/local/directadmin/data/users/$1/domains/*.ftp";
	eval $TEMP;

	TEMP="/usr/bin/perl -pi -e 's#/home/${1}/#/home/${2}/#g' /usr/local/directadmin/data/users/$1/domains/*.ftp";
	eval $TEMP;

}

httpd_swap()
{
	#/etc/httpd/conf/httpd.conf
	#/etc/httpd/conf/ips.conf
	#/usr/local/directadmin/data/users/$1/httpd.conf
	
	if [ ! -s /etc/httpd/conf/httpd.conf ]; then
		return;
	fi

	TEMP="/usr/bin/perl -pi -e 's#users/${1}/httpd.conf#users/${2}/httpd.conf#g' /etc/httpd/conf/httpd.conf";
	eval $TEMP;
	TEMP="/usr/bin/perl -pi -e 's#users/${1}/httpd.conf#users/${2}/httpd.conf#g' /etc/httpd/conf/extra/directadmin-vhosts.conf";
	eval $TEMP;

	#maybe it's nginx
	if [ -s /etc/nginx/directadmin-vhosts.conf ]; then
		TEMP="/usr/bin/perl -pi -e 's#users/${1}/nginx.conf#users/${2}/nginx.conf#g' /etc/nginx/directadmin-vhosts.conf";
		eval $TEMP;		
	fi
	
	#I thought about doing the ips.conf and the users httpd.conf file.
	#but figured it would be far safer to just issue a rewrite.
	
	TEMP="/usr/bin/perl -pi -e 's#=${1}\$#=${2}#g' /usr/local/directadmin/data/users/$1/domains/*.conf";
	eval $TEMP;
	
	TEMP="/usr/bin/perl -pi -e 's#users/${1}/#users/${2}/#g' /usr/local/directadmin/data/users/$1/domains/*.conf";
	eval $TEMP;
}

nginx_swap()
{
	if [ ! -s /etc/nginx/directadmin-vhosts.conf ]; then
		return;
	fi

	#/etc/nginx/directadmin-vhosts.conf
	TEMP="/usr/bin/perl -pi -e 's#users/${1}/nginx.conf#users/${2}/nginx.conf#g' /etc/nginx/nginx.conf";
}

mysql_swap()
{
	#well, im going to say it outright.. this might not be so easy.
	#have to rename all the databases and all users from username_something to newuser_something.
	#1) stop mysql.  Do this by killing the pid.  Remember to set it to OFF in the services.status file.
	#2) rename the database directory
	#3) start up mysql again
	
	
	#use the change_database_username.sh script.
	MYSQL_CONF=/usr/local/directadmin/conf/mysql.conf
	MYSQL_USER=`cat $MYSQL_CONF | grep user | cut -d= -f2`
	MYSQL_PASS=`cat $MYSQL_CONF | grep passwd | cut -d= -f2`
	DBHOST=localhost
	if [ `grep -c ^host= $MYSQL_CONF` -gt 0 ]; then
		DBHOST=`cat $MYSQL_CONF | grep ^host= | cut -d= -f2`
	fi
	VERBOSE=$VERBOSE DBUSER="$MYSQL_USER" DBPASS="$MYSQL_PASS" DBHOST="$DBHOST" USERNAME="$1" NEWUSERNAME="$2" /usr/local/bin/php -c /usr/local/directadmin/scripts/php_clean.ini /usr/local/directadmin/scripts/change_database_username.php
}

da_swap()
{
	#email
	#ftp
	#httpd
	#./data/users/reseller/users.list
	#./data/users/client/user.conf->creator=$1 -> $2
	#./data/users/username and *

	email_swap $1 $2
	ftp_swap $1 $2
	httpd_swap $1 $2
	nginx_swap $1 $2
	mysql_swap $1 $2
	awstats_swap $1 $2

	CREATOR=`grep creator= /usr/local/directadmin/data/users/$1/user.conf | cut -d= -f2`
	generic_swap $1 $2 /usr/local/directadmin/data/users/$CREATOR/users.list
	
	if [ -e /usr/local/directadmin/data/users/$1/reseller.conf ]; then
		generic_swap $1 $2 /usr/local/directadmin/data/admin/reseller.list
		TEMP="/usr/bin/perl -pi -e 's#reseller=${1}\$#reseller=${2}#g' /usr/local/directadmin/data/admin/ips/*";
		eval $TEMP;
		
		#change the creator for all accounts we've made.
		for i in `cat /usr/local/directadmin/data/users/$1/users.list`; do
		{
			TEMP="/usr/bin/perl -pi -e 's#creator=${1}\$#creator=${2}#g' /usr/local/directadmin/data/users/$i/user.conf";
			eval $TEMP;
		};
		done;
		
		#now check to see if we are an admin too.  If so, change any resellers/admins who have us as their creator.
		TYPE=`grep usertype= /usr/local/directadmin/data/users/$1/user.conf | cut -d= -f2`
		if [ "$TYPE" = "admin" ]; then
			for i in `cat /usr/local/directadmin/data/admin/reseller.list; cat /usr/local/directadmin/data/admin/admin.list`; do
			{
				TEMP="/usr/bin/perl -pi -e 's#creator=${1}\$#creator=${2}#g' /usr/local/directadmin/data/users/$i/user.conf";
				eval $TEMP;
			};
			done;
			
			generic_swap $1 $2 /usr/local/directadmin/data/admin/admin.list			
		fi

		#to be safe, rewrite the whole pile with the updated creator, in case anyone is suspended.
		echo "action=rewrite&value=httpd" >> /usr/local/directadmin/data/task.queue
	fi
	TEMP="/usr/bin/perl -pi -e 's#value=${1}\$#value=${2}#g' /usr/local/directadmin/data/admin/ips/*";
	eval $TEMP;

	TEMP="/usr/bin/perl -pi -e 's#username=${1}\$#username=${2}#g' /usr/local/directadmin/data/users/$1/user.conf";
	eval $TEMP;

	mv -f /usr/local/directadmin/data/users/$1 /usr/local/directadmin/data/users/$2

	#once done, rewrite the ips.conf and users httpd.conf using $2
	#show all users cache. Total rewrite.
	
	echo "action=rewrite&value=httpd&user=$2" >> /usr/local/directadmin/data/task.queue	
	echo "action=rewrite&value=ips" >> /usr/local/directadmin/data/task.queue
	echo "action=cache&value=showallusers" >> /usr/local/directadmin/data/task.queue

}

change_name()
{
	security_check $1;
	security_check $2;
	ensure_user $1;
	prevent_user $2;

	system_swap $1 $2
	da_swap $1 $2

}

if [ $# -eq 2 ]; then
	change_name $1 $2
	exit 0;
else
	show_help;
	exit 1;
fi




