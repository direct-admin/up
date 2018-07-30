#!/bin/sh


OS=`uname`;

GET="/usr/bin/wget -O "
if [ "$OS" = "FreeBSD" ]; then
        GET="/usr/bin/fetch -o ";
fi


DIR=/usr/local/directadmin
CB_OPTIONS=/usr/local/directadmin/custombuild/options.conf
DL_SERVER=files.directadmin.com
BACKUP_DL_SERVER=files6.directadmin.com

cd $DIR;

CBVERSION="`cat /root/.custombuild`"
if [ "${CBVERSION}" != "1.1" ] && [ "${CBVERSION}" != "1.2" ] && [ "${CBVERSION}" != "2.0" ]; then
	echo "Invalid CustomBuild version set in /root/.custombuild"
	exit 1
fi

if [ -e $CB_OPTIONS ]; then
	DLS=`grep downloadserver $CB_OPTIONS | cut -d= -f2`;
	if [ "${DLS}" != "" ]; then
		DL_SERVER=${DLS}
	fi
fi

$GET custombuild.tar.gz http://${DL_SERVER}/services/custombuild/${CBVERSION}/custombuild.tar.gz
if [ $? -ne 0 ]
then
        $GET custombuild.tar.gz http://${BACKUP_DL_SERVER}/services/custombuild/${CBVERSION}/custombuild.tar.gz
        if [ $? -ne 0 ]
        then
                echo "*** There was an error downloading the custombuild script. ***";
                exit 1;
        fi
fi

tar xzf custombuild.tar.gz

cd custombuild

chmod 755 build

./build update


#Sept 26, 2011
#for centos6 32 and 64, we need to disable curl.
#rely on yum or rpms for libcurl-devel.
if [ -e /etc/redhat-release ]; then
	#instead of fighting with deciphering the redhat-release file, rely on the files.sh, which should already exist.
	FILESH=${DIR}/scripts/files.sh
	if [ -s ${FILESH} ]; then
		DLPATH=`grep filesh_path ${FILESH} | cut -d= -f2`

		if [ "${DLPATH}" = "es_6.0" ] || [ "${DLPATH}" = "es_6.0_64" ] || [ "${DLPATH}" = "es_7.0" ] || [ "${DLPATH}" = "es_7.0_64" ]; then

			if [ ! -s /usr/include/curl/curl.h ]; then
				echo "***********************************************************";
				echo "*";
				echo "* So.. we're about to disable curl in custombuild but we cannot find /usr/include/curl/curl.h from rpms/yum (libcurl-devel)";
				echo "* It *should* have already been installed with: yum -y install libcurl-devel";
				echo "* If you can open a 2nd ssh window and install it really quickly, you may be able avoid php compile issuess";
				echo "*";
				echo "***********************************************************";
				sleep 5;
			fi

			echo "Found CentOS 6 or 7.  Disabling CURL in custombuild to prevent yum from breaking.";
			echo "Related: http://help.directadmin.com/item.php?id=385";

			BUILD=${DIR}/custombuild/build
			if [ -s ${BUILD} ]; then
				${DIR}/custombuild/build set curl no
			else
				echo "*** Cannot find ${BUILD}... weird ***";
				sleep 1;
			fi
		fi
	else
		echo "*** ${FILESH} seems to be missing or empty ***";
		sleep 5;
	fi
fi

./build all d


#die die die!!
if [ -s /usr/sbin/apache2 ]; then
	chmod 0 /usr/sbin/apache2
	/usr/bin/killall -9 apache2 2> /dev/null
fi

if [ -s /usr/lib/apache2/mpm-prefork/apache2 ]; then
	chmod 0 /usr/lib/apache2/mpm-prefork/apache2
	/usr/bin/killall -9 apache2 2> /dev/null
fi

if [ "${CBVERSION}" != "2.0" ]; then
	chgrp apache /usr/bin/perl
	chmod 705 /usr/bin/perl

	if [ -e /usr/bin/python ]; then
		chgrp apache /usr/bin/python
		chmod 505 /usr/bin/python
	fi
fi

exit 0; 

