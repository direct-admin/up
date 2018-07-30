#!/bin/bash
#Script to setup the base file for proftpd

IP=`cat ./setup.txt | grep ip= | cut -d= -f2`;
VH="/etc/proftpd.vhosts.conf"

SYSTEMD=no
SYSTEMDDIR=/etc/systemd/system
if [ -d ${SYSTEMDDIR} ] && [ -e /usr/bin/systemctl ]; then
	SYSTEMD=yes
fi

#Get out of here! We don't want any of this (wu-ftpd)!
rpm -e --nodeps wu-ftp 2> /dev/null
rpm -e --nodeps wu-ftpd 2> /dev/null
rpm -e --nodeps anonftp 2> /dev/null
rpm -e --nodeps pure-ftpd 2> /dev/null
rpm -e --nodeps vsftpd 2> /dev/null
rpm -e --nodeps psa-proftpd 2> /dev/null
rpm -e --nodeps psa-proftpd-xinetd 2> /dev/null
rpm -e --nodeps psa-proftpd-start 2> /dev/null
rm -f /etc/xinetd.d/proftpd
rm -f /etc/xinetd.d/wu-ftpd.rpmsave
rm -f /etc/xinetd.d/wu-ftpd
rm -f /etc/xinetd.d/ftp_psa
rm -f /etc/xinetd.d/gssftp
rm -f /etc/xinetd.d/xproftpd
killall -9 pure-ftpd 2> /dev/null > /dev/null
rm -f /usr/local/sbin/pure-ftpd 2> /dev/null > /dev/null

#while we're doing it, lets get rid of pop stuff too
rm -f /etc/xinetd.d/pop*

#in case they it still holds port 21
if [ -s /etc/init.d/xinetd ] && [ "${SYSTEMD}" = "no" ]; then
	/sbin/service xinetd restart
fi
if [ -s /usr/lib/systemd/system/xinetd.service ] && [ "${SYSTEMD}" = "yes" ]; then
	systemctl restart xinetd.service
fi

touch ${VH}
touch /etc/proftpd.passwd
chown -f root.ftp /etc/proftpd.passwd;
chmod -f 640 /etc/proftpd.passwd
chmod -f 644 ${VH}
mkdir /var/log/proftpd
mkdir -p /var/run/proftpd

CB_OPTIONS=/usr/local/directadmin/custombuild/options.conf
if [ -s ${CB_OPTIONS} ]; then
	#regardless of yes or no in the options.conf, it's going to handle it.
	echo "Ftp server to be managed by custombuild.  Not going to install the default packages";
	exit 0;
fi

cd /usr/local/directadmin/scripts/packages
rpm -ivh proftpd-1.*.rpm
rpm -ivh proftpd-standalone-*.rpm

#Ok, hostname cannot resolve to IP with this in the /etc/proftpd.vhosts.conf
#or else proftpd won't start. Since 'hostname' resolves to 127.0.0.1 by
#default, there really isn't any issue.

#echo "<VirtualHost ${IP}>" >> ${VH};
#echo -e "\tServerName 		\"ProFTPd\"" >> ${VH};
#echo -e "\tExtendedLog		/var/log/proftpd/${IP}.bytes WRITE,READ userlog" >> ${VH};
#echo -e "\tAuthuserFile		/etc/proftpd.passwd" >> ${VH};
#echo "</VirtualHost>" >> ${VH};


#fix the /etc/logrotate.d/proftpd file

FILE=/etc/logrotate.d/proftpd
echo "/var/log/proftpd/access.log /var/log/proftpd/auth.log /var/log/proftpd/xferlog.legacy {" > $FILE
echo -e "\tmissingok" >> $FILE;
echo -e "\tnotifempty" >> $FILE;
echo -e "\tpostrotate" >> $FILE;
echo -e "\t\t/usr/bin/kill -HUP \`cat /var/run/proftpd/proftpd.pid 2>/dev/null\` 2>/dev/null || true" >> $FILE;
echo -e "\tendscript" >> $FILE;
echo "}" >> $FILE;


exit 0;
