#!/bin/sh

echo "phpMyAdmin to be installed through custombuild";
exit 0;


#run this script AFTER the administrator account has been created

#VER=2.8.0.3
#VER=2.8.2.4
VER=2.11.11.3-all-languages
PMAFILE=/usr/local/directadmin/scripts/packages/phpMyAdmin-${VER}.tar.gz
PMADIR=/var/www/html/phpMyAdmin-${VER}
WEBFILE=http://files.directadmin.com/services/all/phpMyAdmin/phpMyAdmin-${VER}.tar.gz
DEST=/var/www/html
APPUSER=webapps

if [ ! -e ${PMAFILE} ]; then
	wget -O $PMAFILE $WEBFILE
fi

if [ ! -e ${PMAFILE} ]
then
	PMAFILE=/usr/local/directadmin/scripts/packages/phpMyAdmin-2.5.4-php.tar.gz
	PMADIR=/var/www/html/phpMyAdmin-2.5.4

	if [ ! -e ${PMAFILE} ]; then

		echo "The phpMyAdmin package cannot be found. Please ensure that the paths are correct";
		exit 0;
	fi
fi

tar xzf ${PMAFILE} -C /var/www/html;

cp -f /usr/local/directadmin/data/templates/config.inc.php ${PMADIR}

rm -f /var/www/html/phpMyAdmin >/dev/null 2>&1
ln -s phpMyAdmin-${VER} /var/www/html/phpMyAdmin
chown -h ${APPUSER}:${APPUSER} /var/www/html/phpMyAdmin

OS=`uname`;

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

chown -f -R ${APPUSER}:${APPUSER} ${PMADIR};
chmod -f 755 ${PMADIR};

HTF=/var/www/html/phpMyAdmin/.htaccess
if [ ! -e $HTF ]; then
	echo "Options -Indexes" > $HTF
fi

chmod 0 ${PMADIR}/scripts

exit 0;

