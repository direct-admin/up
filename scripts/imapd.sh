#!/bin/sh

DA_PATH=/usr/local/directadmin
FILE=${DA_PATH}/scripts/packages/imapd
DEST=/usr/sbin/imapd
INET=${DA_PATH}/data/templates/imap

if [ ! -e $FILE ]; then
	echo "Unable to find: $FILE";
	exit 1;
fi

if [ ! -e $INET ]; then
	echo "Unable to find: $INET";
	exit 2;
fi

/bin/cp -f $FILE $DEST
/bin/chmod 755 $DEST
/bin/chown root:root $DEST

/bin/cp -f $INET /etc/xinetd.d/imap


#up the limit.

perl -pi -e 's/instances\s+= 60/instances               = 256/' /etc/xinetd.conf












/sbin/service xinetd restart

exit 0;
