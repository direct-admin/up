#!/bin/sh

#script to tell up2date which packages not to touch/update overtop of.
#July 13, 2008: removed bind* from the skips.

YUMCONF=/etc/yum.conf
if [ -e $YUMCONF ]; then
	COUNT=`grep -c exclude $YUMCONF`
	if [ $COUNT -eq 0 ]; then
		echo "exclude=apache* httpd* mod_* mysql* MySQL* mariadb* da_* *ftp* exim* sendmail* php* bind-chroot*" >> $YUMCONF
	fi
fi



CONF=/etc/sysconfig/rhn/up2date

if [ ! -e $CONF ]
then
	echo "Cannot find $CONF... up2date may break things.";
	exit 1;
fi;

/usr/bin/perl -pi -e 's/^pkgSkipList\=.*;$/pkgSkipList=kernel\*;apache\*;httpd\*;mod_\*;mysql\*;MySQL\*;da_\*;\*ftp\*;exim\*;sendmail\*;php\*;bind-chroot\*;/' $CONF;
/usr/bin/perl -pi -e 's/^removeSkipList\=.*;$/removeSkipList=kernel\*;apache\*;httpd\*;mod_\*;mysql\*;MySQL\*;da_\*;\*ftp\*;exim\*;sendmail\*;php\*;webalizer*;bind-chroot\*;/' $CONF;

AUDIT=/etc/audit/audit.conf
if [ -e /etc/audit/audit.conf ]; then
	perl -pi -e 's#notify=.*#notify=/bin/true#' $AUDIT
fi

exit 0;
