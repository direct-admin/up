#!/bin/sh
VERSION=1.4.21

DA_SCRIPTS=/usr/local/directadmin/scripts
TARFILE=${DA_SCRIPTS}/packages/squirrelmail-${VERSION}.tar.gz
WWWPATH=/var/www/html
DEST=/var/www/html
REALPATH=${WWWPATH}/squirrelmail-$VERSION
ALIASPATH=${WWWPATH}/squirrelmail
HTTPDCONF=/etc/httpd/conf/httpd.conf
CONFIG=${REALPATH}/config/config.php
DA_HOSTNAME=`hostname`

OS=`uname`

APPUSER=webapps

if [ "$OS" = "FreeBSD" ]; then
	WGET=/usr/local/bin/wget
	TAR=/usr/bin/tar
	CHOWN=/usr/sbin/chown
	ROOTGRP=wheel
else
	WGET=/usr/bin/wget
	TAR=/bin/tar
	CHOWN=/bin/chown
	ROOTGRP=root
fi

if [ ! -e $TARFILE ]; then
	$WGET -O $TARFILE http://files.directadmin.com/services/all/squirrelmail-${VERSION}.tar.gz
fi

#Extract the file
$TAR xzf $TARFILE -C $WWWPATH

#this bit is to copy all of the preious setup to the new setup
if [ -e $ALIASPATH ]; then
	#cp -f $ALIASPATH/data/* $REALPATH/data/
	#cd $ALIASPATH/data && find . -print | cpio -pdmvu $REALPATH/data
	cp -fR $ALIASPATH/data $REALPATH
fi

#link it from a fake path:
/bin/rm -f $ALIASPATH
/bin/ln -sf squirrelmail-$VERSION $ALIASPATH
${CHOWN} -h ${APPUSER}:${APPUSER} ${ALIASPATH}

#install the proper config:
if [ ! -e $CONFIG ]; then
	/bin/cp -f ${REALPATH}/config/config_default.php $CONFIG

	/usr/bin/perl -pi -e 's/\$force_username_lowercase = false/\$force_username_lowercase = true/' $CONFIG
	/usr/bin/perl -pi -e "s/\'example.com\';/\\$\_SERVER\[\'HTTP_HOST\'\];\nwhile \(sizeof\(explode\(\'\.\', \\$\domain\)\) \> 2) {\n\t\\$\domain = substr(\\$\domain, strpos\(\\$\domain, \'\.\'\) \+ 1\);\n\}/" $CONFIG
	/usr/bin/perl -pi -e 's/\$show_contain_subfolders_option = false/\$show_contain_subfolders_option = true/' $CONFIG

	/usr/bin/perl -pi -e 's#/var/local/squirrelmail/data/#/var/www/html/squirrelmail/data/#' $CONFIG
	/usr/bin/perl -pi -e 's#/var/local/squirrelmail/attach/#/var/www/html/squirrelmail/data/#' $CONFIG

	#we want it to use port 587 and use smtp auth.
	/usr/bin/perl -pi -e 's/\$smtpPort = 25/\$smtpPort = 587/' $CONFIG
	/usr/bin/perl -pi -e "s#\$smtp_auth_mech = \'none\'#\$smtp_auth_mech = \'login\'#" $CONFIG

	#STR="/usr/bin/perl -pi -e 's/example.com/$DA_HOSTNAME/' $CONFIG"
	#eval $STR;

	#enable the pluguins
	/usr/bin/perl -pi -e "s/Add list of enabled plugins here/Add list of enabled plugins here\n\\$\plugins\[0\] = \'spamcop\';\n\\$\plugins\[1\] = \'filters\';\n\\$\plugins\[2\] = \'squirrelspell\';/" $CONFIG
fi

/usr/bin/perl -pi -e 's/\$allow_charset_search = true;/\$allow_charset_search = false;/' $CONFIG

if [ `grep -c -e "^${APPUSER}:" /etc/passwd` = "0" ]; then
        if [ "$OS" = "FreeBSD" ]; then
                /usr/sbin/pw groupadd $APPUSER 2> /dev/null
                /usr/sbin/pw useradd -g $APPUSER -n $APPUSER -b $DEST -s /sbin/nologin 2> /dev/null
        elif [ -e /etc/debian_version ]; then
		/usr/sbin/adduser --system --group --firstuid 100 --home $DEST --no-create-home --disabled-login --force-badname $APPUSER
        else
                /usr/sbin/useradd -d $DEST -s /bin/false $APPUSER 2> /dev/null
        fi
fi

#set the permissions:
/bin/chmod -R 755 $REALPATH
$CHOWN -R ${APPUSER}:${APPUSER} $REALPATH

/bin/chmod -R 770 $REALPATH/data
$CHOWN -R apache:${APPUSER} $REALPATH/data
