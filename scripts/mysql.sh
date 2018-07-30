#!/bin/bash

#Mysql installer script

#have to change the name of the startup script so that dataskq can find it
#(has to have same name as the process)

CMD_LINE=0;
if [ $# -gt 3 ]; then
	CMD_LINE=$4
fi

SYSTEMD=no
SYSTEMDDIR=/etc/systemd/system
if [ -d ${SYSTEMDDIR} ] && [ -e /usr/bin/systemctl ]; then
	SYSTEMD=yes
fi

CB_OPTIONS=${DA_PATH}/custombuild/options.conf
SERVER=http://files.directadmin.com/services
if [ -s "${CB_OPTIONS}" ]; then
	DL=`grep ^downloadserver= ${CB_OPTIONS} | cut -d= -f2`
	if [ "${DL}" != "" ]; then
		SERVER=http://${DL}/services
	fi
fi

FILE="/usr/local/directadmin/conf/mysql.conf"

setStartupScript() {
	if [ "${SYSTEMD}" = "yes" ]; then
		if [ ! -s /usr/libexec/mysql-wait-ready ]; then
			wget -O /usr/libexec/mysql-wait-ready ${SERVER}/custombuild/2.0/custombuild/configure/systemd/scripts/mysql-wait-ready
			chmod 755 /usr/libexec/mysql-wait-ready
		fi
		if [ ! -s /etc/systemd/system/mysqld.service ]; then
			wget -O /etc/systemd/system/mysqld.service ${SERVER}/custombuild/2.0/custombuild/configure/systemd/mysqld.service
			systemctl daemon-reload
			systemctl enable mysqld.service
		fi
		
		rm -f /etc/init.d/mysql
	else
		if [ -e /etc/rc.d/init.d/mysql ]
		then
			/sbin/chkconfig --del mysql
			mv -f /etc/rc.d/init.d/mysql /etc/rc.d/init.d/mysqld
			/sbin/chkconfig --add mysqld
		fi
	fi
}

setRootPass() {

	#/usr/bin/mysqladmin --user=root password $1 1> /dev/null 2> /dev/null

        /usr/bin/mysqladmin --user=root password $1 1> /dev/null 2> /dev/null
        echo "UPDATE mysql.user SET password=PASSWORD('${1}') WHERE user='root';"> mysql.temp;
	echo "UPDATE mysql.user SET password=PASSWORD('${1}') WHERE password='';">> mysql.temp;
	echo "DROP DATABASE IF EXISTS test;" >> mysql.temp
        echo "FLUSH PRIVILEGES;" >> mysql.temp;
        /usr/bin/mysql mysql --user=root --password=${1} < mysql.temp;
        rm -f mysql.temp;
}

setDAuser() {
	echo "user=${2}" > $FILE
	echo "passwd=${3}" >> $FILE

	chown -f diradmin.diradmin $FILE;
	chmod -f 400 $FILE;

	#ok, now we'll create a temp file and run mysql that way.

	echo "GRANT CREATE, DROP ON *.* TO ${2}@localhost IDENTIFIED BY '${3}' WITH GRANT OPTION;" > mysql.temp;
	echo "GRANT ALL PRIVILEGES ON *.* TO ${2}@localhost IDENTIFIED BY '${3}' WITH GRANT OPTION;" >> mysql.temp;

	#echo "Enter the password for the root user of MySQL: ";

	/usr/bin/mysql --user=root --password=${1} < mysql.temp;

	rm -f mysql.temp;
}

drop_test_db() {

	echo "DROP DATABASE test;" > mysql.temp
	echo "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" >> mysql.temp
	echo "DELETE FROM mysql.user WHERE User='';" >> mysql.temp
	echo "DELETE FROM mysql.user WHERE User='root' AND Host!='localhost';" >> mysql.temp
	echo "FLUSH PRIVILEGES;" >> mysql.temp
	
	/usr/bin/mysql --user=root --password=${1} < mysql.temp;

	rm -f mysql.temp;
}

if [ $# -lt "3" ]
then
	echo "Usage: $0 mysqlrootpass da_dbuser da_pass";
	echo "*** do not use spaces in your passwords ***";
	exit 1;
fi

#stop taskq from trying
SERVICES=/usr/local/directadmin/data/admin/services.status
if [ -e $SERVICES ]
then
	/usr/bin/perl -pi -e 's/mysqld=ON/mysqld=OFF/' ${SERVICES};
fi

/sbin/service mysqld stop 2> /dev/null 1> /dev/null
/sbin/service mysql stop 2> /dev/null 1> /dev/null
/usr/bin/killall mysqld 2> /dev/null 1> /dev/null

if [ -e /root/.my.cnf ]; then
	echo "Moving /root/.my.cnf to .my.cnf.moved";
	mv -f /root/.my.cnf /root/.my.cnf.moved
fi

rpm -e --nodeps MySQL-Max 2> /dev/null 1> /dev/null
rpm -e --nodeps mysql-devel 2> /dev/null 1> /dev/null
rpm -e --nodeps mysql-client 2> /dev/null 1> /dev/null
rpm -e --nodeps mysql-libs 2> /dev/null 1> /dev/null
rpm -e --nodeps mysqlclient9 2> /dev/null 1> /dev/null
rpm -e --nodeps mysql-server 2> /dev/null 1> /dev/null
rpm -e --nodeps mysql 2> /dev/null 1> /dev/null
rpm -e --nodeps MySQL-shared 2> /dev/null 1> /dev/null  #added july 3 2006 for mysql 5 shared rpms
rpm -e --nodeps mysql-libs php-mysql 2> /dev/null 1> /dev/null #added Dec 5, 2007 for fedora 7.
rpm -e --nodeps mariadb-libs 2>/dev/null 1> /dev/null		#added july 8 for CentOS 7
rpm -e --nodeps Percona-Server-client 2>/dev/null 1> /dev/null
rpm -e --nodeps Percona-Server-shared 2>/dev/null 1> /dev/null
rpm -e --nodeps Percona-Server-server 2>/dev/null 1> /dev/null


#Added June 15th, 2011
if [ -e /usr/bin/mysql ]; then
	for i in `rpm -qa | grep -i "^mysql"`; do { rpm -ev $i --nodeps; }; done;
fi

SQLDIR=/var/lib/mysql
if [ -e ${SQLDIR} ]
then
	if [ $CMD_LINE -eq 1 ]; then
		mv ${SQLDIR} ${SQLDIR}.backup;
		rm -rf ${SQLDIR};
	else
	echo "";
	echo "*****************************************************";
	echo "*****************************************************";
	echo "";
	echo "It seems as though mysql has already been installed.";
	echo "The directory ${SQLDIR} has been found.  For the best results, its recommended that this be deleted.";
	echo "All database data will be lost if you delete it";
	echo "";
	echo -n "Do you want to delete it? (y is recommended)? (y,n) : ";
	read -n 1 yesno;
	echo "";
	if [ "$yesno" != "n" ]
	then
		mv ${SQLDIR} ${SQLDIR}.backup;
		rm -rf ${SQLDIR};
	fi
	fi
fi

mkdir -p ${SQLDIR}
chown mysql:mysql ${SQLDIR}


MY_CNF_RPMSAVE=/etc/my.cnf.rpmsave
CNF_RPMSAVE_EXISTS_BEFORE=0
if [ -s ${MY_CNF_RPMSAVE} ]; then
	CNF_RPMSAVE_EXISTS_BEFORE=1
fi


#july 10, 2008: changed ivh to Uvh.

MARIA_COUNT=`ls -la /usr/local/directadmin/scripts/packages | grep -c MariaDB`
if [ "${MARIA_COUNT}" -gt 0 ]; then
	echo "Installing MariaDB";
	rpm -Uvh --nodeps --force /usr/local/directadmin/scripts/packages/MariaDB-*-server.rpm
	rpm -Uvh --nodeps --force /usr/local/directadmin/scripts/packages/MariaDB-*-client.rpm
	rpm -Uvh --nodeps --force /usr/local/directadmin/scripts/packages/MariaDB-*-devel.rpm
	rpm -Uvh --nodeps --force /usr/local/directadmin/scripts/packages/MariaDB-*-shared.rpm
	rpm -Uvh --nodeps --force /usr/local/directadmin/scripts/packages/MariaDB-*-common.rpm
	rpm -Uvh --nodeps --force /usr/local/directadmin/scripts/packages/MariaDB-*-compat.rpm
else
	echo "Installing MySQL";
	rpm -Uvh --nodeps --force /usr/local/directadmin/scripts/packages/MySQL-server*.rpm
	rpm -Uvh --nodeps --force /usr/local/directadmin/scripts/packages/MySQL-client*.rpm
	rpm -Uvh --nodeps --force /usr/local/directadmin/scripts/packages/MySQL-devel*.rpm
	rpm -Uvh --nodeps --force /usr/local/directadmin/scripts/packages/MySQL-shared*.rpm >/dev/null 2>/dev/null
	#the shared rpm might not exist.  Shhh, it might want to throw errors, we'll hide them.
fi

MYSQL_COUNT=`ls ${SQLDIR}/mysql/ | wc -l`
if [ "${MYSQL_COUNT}" -eq 0 ]; then
	echo "Data needs to be created in ${SQLDIR}/mysql ...";
	/usr/bin/mysql_install_db
fi
chown -R mysql:mysql ${SQLDIR}
chmod 711 ${SQLDIR}

#because we can't really edit the rpms, we just change the shell after the fact.
/usr/sbin/usermod -s /bin/false mysql

if [ -s ${MY_CNF_RPMSAVE} ] && [ "${CNF_RPMSAVE_EXISTS_BEFORE}" -eq 0 ]; then
	#wasn't here before, so install created it.
	#move it back.
	mv ${MY_CNF_RPMSAVE} /etc/my.cnf
fi

setStartupScript

if [ "${SYSTEMD}" = "yes" ]; then
	/usr/bin/systemctl start mysqld.service
	/usr/bin/systemctl status mysqld.service
else
	/sbin/service mysqld start
fi

echo "Waiting for mysqld to start....";
sleep 7


echo "Setting MySQL Root Password...";
setRootPass $1;
echo "Setting DirectAdmin user and password...";
setDAuser $1 $2 $3;
echo "Securing installation..."
drop_test_db $1;

#echo "Updating privilege tables...";
#/usr/local/directadmin/scripts/fix_mysql_privs.sh

if [ -e /usr/lib64 ]; then
	if [ ! -e /usr/lib/mysql ]; then
		echo "Linking 64 bit mysql libraries: /usr/lib64/libmysqlclient -> /usr/lib/mysql/* ...";
		cd /usr/lib
		mkdir mysql
		cd mysql
		ln -s /usr/lib64/libmysqlclient* .
	fi
fi

exit 0;
