#!/bin/sh

OS=`uname`;

GET="/usr/bin/wget -O "
if [ "$OS" = "FreeBSD" ]; then
	GET="/usr/bin/fetch -o ";
fi


CBFILE=/root/.custombuild
if [ -e $CBFILE ]; then

	echo "************************************************************************";
	echo "*";
	echo "* Found $CBFILE. Using custombuild `cat /root/.custombuild` instead of customapache ";
	echo "*";
	echo "************************************************************************";
	echo "";
	echo "Related pages:";
	echo "      http://www.directadmin.com/forum/forumdisplay.php?f=61";
	echo "      http://files.directadmin.com/services/custombuild/";
	echo "";

	sleep 3;

	/usr/local/directadmin/scripts/custombuild.sh
	exit 0;
fi

DIR=/usr/local/directadmin/customapache
mkdir -p $DIR;
cd $DIR;

$GET build http://files.directadmin.com/services/customapache/build
if [ $? -ne 0 ]
then
	$GET build http://files4.directadmin.com/services/customapache/build
	if [ $? -ne 0 ]
	then
		echo "*** There was an error downloading the customapache build script. ***";
        	exit 1;
	fi
fi

chmod 755 build

./build update

./build all d


exit 0;
