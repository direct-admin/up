#!/bin/sh
# This script is written by Martynas Bendorius and DirectAdmin
# It is used to install UebiMiau webmail into DirectAdmin servers
# Official UebiMiau 3.x webmail page: http://www.manvel.net

VER=3.11

REMOTE_FILE=http://files.directadmin.com/services/all/webmail-${VER}.tar.gz
FILE=/usr/local/directadmin/scripts/packages/webmail-${VER}.tar.gz;
DEST=/var/www/html;
TMPDIR=${DEST}/webmail/tmp

OS=`uname`
TAR=/bin/tar
MKDIR=/bin/mkdir
CHMOD=/bin/chmod
CHOWN=/bin/chown

APPUSER=webapps

if [ "$OS" = "FreeBSD" ]; then
        TAR=/usr/bin/tar
        CHOWN=/usr/sbin/chown
fi

if [ ! -e ${FILE} ]; then
        wget -O $FILE $REMOTE_FILE
fi

if [ ! -e ${FILE} ]; then
        echo "Unable to find ${FILE}, make sure it exists.";
        exit -1;
fi

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


$TAR xzf ${FILE} -C ${DEST}
$MKDIR -p $TMPDIR
$CHMOD -f -R 770 $TMPDIR;
$CHOWN -f -R $APPUSER:$APPUSER $DEST/webmail
$CHOWN -f -R apache:${APPUSER} $TMPDIR;

if [ ! -e $TMPDIR/.htaccess ]; then
        echo "Deny from All" >> $TMPDIR/.htaccess
fi

#increase the timeout from 10 minutes to 24
perl -pi -e 's/idle_timeout = 10/idle_timeout = 24/' ${DEST}/webmail/inc/config.security.php

perl -pi -e 's#\$temporary_directory = "./database/";#\$temporary_directory = "./tmp/";#' ${DEST}/webmail/inc/config.php
perl -pi -e 's/= "ONE-FOR-EACH";/= "ONE-FOR-ALL";/' ${DEST}/webmail/inc/config.php
perl -pi -e 's#\$smtp_server = "SMTP.DOMAIN.COM";#\$smtp_server = "localhost";#' ${DEST}/webmail/inc/config.php
#perl -pi -e 's#\$default_mail_server = "POP3.DOMAIN.COM";#\$default_mail_server = "localhost";#' ${DEST}/webmail/inc/config.php
perl -pi -e 's/POP3.DOMAIN.COM/localhost/' ${DEST}/webmail/inc/config.php

rm -rf ${DEST}/webmail/install
