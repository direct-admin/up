#!/bin/sh
# This script is written by Martynas Bendorius and DirectAdmin
# It is used to install Atmail webmail into DirectAdmin servers
# Official Atmail webmail page: http://www.atmail.org

VERSION=1.02

DA_SCRIPTS=/usr/local/directadmin/scripts
DA_MYSQL=/usr/local/directadmin/conf/mysql.conf
TARFILE=${DA_SCRIPTS}/packages/atmailopen-${VERSION}.tgz
WWWPATH=/var/www/html
REALPATH=${WWWPATH}/atmail-${VERSION}
ALIASPATH=${WWWPATH}/atmail
if [ -e /etc/httpd/conf/extra/httpd-alias.conf ]; then
	HTTPDCONF=/etc/httpd/conf/extra/httpd-alias.conf
else
	HTTPDCONF=/etc/httpd/conf/httpd.conf
fi
CONFIG=${REALPATH}/config/main.inc.php
DA_HOSTNAME="`hostname`"
HTTPPATH=http://files.directadmin.com/services/all/atmail
ADMIN_EMAIL1="`cat /usr/local/directadmin/data/users/admin/ticket.conf | grep email  | cut -d= -f2 | cut -d@ -f1`"
ADMIN_EMAIL2="`cat /usr/local/directadmin/data/users/admin/ticket.conf | grep email  | cut -d@ -f2`"

OS="`uname`"

# variables for the database:
ATMAIL_DB=da_atmail
ATMAIL_DB_USER=da_atmail
ATMAIL_DB_PASS="`perl -le'print map+(A..Z,a..z,0..9)[rand 62],0..7'`";
DB_CONFIG=${REALPATH}/config/db.inc.php
MYSQLUSER="`grep "^user=" ${DA_MYSQL} | cut -d= -f2`"
MYSQLPASSWORD="`grep "^passwd=" ${DA_MYSQL} | cut -d= -f2`"

if [ "${OS}" = "FreeBSD" ]; then
	WGET=/usr/local/bin/wget
	TAR=/usr/bin/tar
	CHOWN=/usr/sbin/chown
	MYSQL_DATA=/home/mysql
else
	WGET=/usr/bin/wget
	TAR=/bin/tar
	CHOWN=/bin/chown
	if [ -e /etc/debian_version ]; then
		MYSQL_DATA=/home/mysql
	else
		MYSQL_DATA=/var/lib/mysql
	fi
fi 

if [ ! -e ${TARFILE} ]; then
	${WGET} -O ${TARFILE} ${HTTPPATH}/atmailopen-${VERSION}.tgz
fi

if [ ! -e ${TARFILE} ]; then
	echo "Can not download ${TARFILE}"
	exit 1
fi

#Extract the file
${TAR} xzf ${TARFILE} -C ${WWWPATH}
if [ -d ${WWWPATH}/atmail-${VERSION} ]; then
	rm -rf ${WWWPATH}/atmail-${VERSION}
fi
mv ${WWWPATH}/atmailopen ${WWWPATH}/atmail-${VERSION}

if [ ! -e ${REALPATH} ]; then
	echo "Directory ${REALPATH} does not exist"
	exit 1
fi

mkdir -p ${REALPATH}/logs

if [ -e ${ALIASPATH} ]; then
	if [ -d ${ALIASPATH}/logs ]; then
		cp -fR ${ALIASPATH}/logs/* ${REALPATH}/logs
	fi
		if [ -d ${ALIASPATH}/tmp ]; then
		cp -fR ${ALIASPATH}/tmp/* ${REALPATH}/tmp
	fi
fi

#link it from a fake path:
/bin/rm -f ${ALIASPATH}
/bin/ln -sf atmail-${VERSION} ${ALIASPATH}
cd ${REALPATH}

#insert data to mysql and create database/user for atmail:
if [ ! -d $MYSQL_DATA/${ATMAIL_DB} ]; then
	if [ -d install ]; then
		echo "Inserting data to mysql and creating database/user for atmail..."
		mysql -e "CREATE DATABASE ${ATMAIL_DB};" --user=${MYSQLUSER} --password=${MYSQLPASSWORD}
		mysql -e "GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,DROP,ALTER,INDEX ON ${ATMAIL_DB}.* TO '${ATMAIL_DB_USER}'@'localhost' IDENTIFIED BY '${ATMAIL_DB_PASS}';" --user=${MYSQLUSER} --password=${MYSQLPASSWORD}
		mysql -e "use ${ATMAIL_DB}; source install/atmail.mysql;" --user=${ATMAIL_DB_USER} --password=${ATMAIL_DB_PASS}
		echo "Database created, ${ATMAIL_DB_USER} password is ${ATMAIL_DB_PASS}"
	else
		echo "Can not find install directory in atmail-${VERSION}"
		exit 1
	fi
else
	mysql -e "SET PASSWORD FOR '${ATMAIL_DB_USER}'@'localhost' = PASSWORD('${ATMAIL_DB_PASS}');" --user=${MYSQLUSER} --password=${MYSQLPASSWORD}
fi

#install the proper config:
if [ -d ../atmail ]; then
	#edit configuration file
	echo "Editing atmail configuration..."
	cd ${REALPATH}/libs/Atmail
    cp -f Config.php.default Config.php
	
	/usr/bin/perl -pi -e "s|'installed' => 0|'installed' => 1|" Config.php > /dev/null
	/usr/bin/perl -pi -e "s| 'decode_tnef' => 1| 'decode_tnef' => 0|" Config.php > /dev/null
	/usr/bin/perl -pi -e "s|'sql_user' => 'root'|'sql_user' => '${ATMAIL_DB_USER}'|" Config.php > /dev/null
	/usr/bin/perl -pi -e "s|'allow_Signup' => '1'|'allow_Signup' => '0'|" Config.php > /dev/null
	/usr/bin/perl -pi -e "s|'smtphost' => 'mail.iinet.net.au'|'smtphost' => 'localhost'|" Config.php > /dev/null
	/usr/bin/perl -pi -e "s|'install_dir' => ''|'install_dir' => '${REALPATH}'|" Config.php > /dev/null
	/usr/bin/perl -pi -e "s|'user_dir' => '/var/www/html/atmailopen'|'user_dir' => '${REALPATH}'|" Config.php > /dev/null
	/usr/bin/perl -pi -e "s|'sql_table' => 'atmail'|'sql_table' => '${ATMAIL_DB}'|" Config.php > /dev/null
	/usr/bin/perl -pi -e "s|'sql_pass' => ''|'sql_pass' => '${ATMAIL_DB_PASS}'|" Config.php > /dev/null
	/usr/bin/perl -pi -e "s|'install_type' => 'server'|'install_type' => 'standalone'|" Config.php > /dev/null
	/usr/bin/perl -pi -e "s|'gpg_path' => ''|'gpg_path' => '/usr/bin/gpg'|" Config.php > /dev/null
	/usr/bin/perl -pi -e "s|'admin_email' => ''|'admin_email' => '${ADMIN_EMAIL1}\@${ADMIN_EMAIL2}'|" Config.php > /dev/null
	/usr/bin/perl -pi -e "s|'error_log' => '/usr/local/atmail/logs/error_log'|'error_log' => '${REALPATH}/logs/error_log'|" Config.php > /dev/null
	
	#edit skin
	cd ${REALPATH}/html
	perl -pi -e 's|<td align="left"><input name="MailServer" type="text" class="logininput" id="MailServer"></td>|<td align="left"><select name="MailServer" class="loginselect"><option value="localhost" selected>localhost</option></select></td>|' login-light.html
	
	echo "Atmail has been installed successfully."
fi

#set the permissions:
${CHOWN} -R webapps:webapps ${REALPATH}
${CHOWN} -R apache ${REALPATH}/logs ${REALPATH}/tmp
/bin/chmod -R 770 ${REALPATH}/logs
/bin/chmod -R 770 ${REALPATH}/tmp

#cleanup:
rm -rf ${ALIASPATH}/install

#writing alias to httpd.conf
COUNTALIAS=`grep -c -e "Alias /atmail" ${HTTPDCONF}`
if [ "${COUNTALIAS}" = "0" ]; then
   echo "Adding atmail alias to ${HTTPDCONF}"
   echo "" >> ${HTTPDCONF}
   echo "# Alias for Atmail webmail" >> ${HTTPDCONF}
   echo "Alias /atmail ${ALIASPATH}/" >> ${HTTPDCONF}
   echo "" >> ${HTTPDCONF}
   echo "You need to restart the httpd service if you want alias to work."
fi
