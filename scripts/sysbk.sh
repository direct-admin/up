#!/bin/sh

CWD=`pwd`

NAME=sysbk
PRIMARY=http://files.directadmin.com/services
SECONDARY=http://files3.directadmin.com/services
SAVE=/usr/local/directadmin/scripts/packages
FILE=${NAME}.tar.gz
DIR=/usr/local

OS=`uname`

if [ "$OS" = "FreeBSD" ]; then
	WGET=/usr/local/bin/wget
else
	WGET=/usr/bin/wget
fi

if [ ! -e $SAVE/$FILE ]; then
	$WGET -O $SAVE/$FILE $PRIMARY/$FILE
fi
if [ ! -e $SAVE/$FILE ]; then
        $WGET -O $SAVE/$FILE $SECONDARY/$FILE
fi
if [ ! -e $SAVE/$FILE ]; then
	echo "Unable to get $SAVE/$FILE"
	exit 1;
fi

cd $DIR

tar xzf $SAVE/$FILE

#swap out linux files for freebsd file:
if [ "$OS" = "FreeBSD" ]; then

	FILES=$DIR/$NAME/mod/custom.files
	perl -pi -e 's#/etc/shadow#/etc/master.passwd#' $FILES

	DIRS=$DIR/$NAME/mod/custom.dirs
	perl -pi -e 's#/var/spool/mail#/var/mail#' $DIRS
	perl -pi -e 's#/var/spool/cron#/var/cron#' $DIRS
fi


KEY=/root/.ssh/id_dsa
if [ ! -e $KEY ]; then
	/usr/bin/ssh-keygen -t dsa -N '' -q -f $KEY
fi

cd /usr/local/directadmin/scripts

#if [ ! -e "/usr/bin/ncftpput" ]; then
#	./ncftp.sh
#fi


cd $CWD;
