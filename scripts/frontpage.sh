#!/bin/bash
#A script to create the we80.cnf file for frontpage if frontpage forgets

FPDIR="/usr/local/frontpage"
FPFILE="/usr/local/frontpage/we80.cnf"

if [ -e $FPDIR ]
then
if [ ! -e $FPFILE ]
then
	echo "vti_encoding:SR|utf8-nl" > $FPFILE;
	echo "frontpageroot:/usr/local/frontpage/version5.0" >> $FPFILE;
	echo "authoring:enabled" >> $FPFILE;
	echo "servertype:apache-fp" >> $FPFILE;
	echo "serverconfig:/etc/httpd/conf/httpd.conf" >> $FPFILE;
	echo "SMTPHost:127.0.0.1" >> $FPFILE;
	echo "SendmailCommand:/usr/sbin/sendmail" >> $FPFILE;
	echo "MailSender:webmaster@" >> $FPFILE;
fi
fi

exit 0;
