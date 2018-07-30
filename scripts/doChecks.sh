#!/bin/sh

#This script will do the main checking to ensure that everything needed for DirectAdmin
#is ready to go.

if [ -e /etc/debian_version ] && [ -e /usr/bin/dpkg ]; then
	echo "****";
	echo "";
	echo "It seems like this is a Debian OS, but this is not a Debian install package";
	echo "Please check the OS set in your license file and let us know (sales@directadmin.com) if you require a change";
	echo "";
	echo "http://help.directadmin.com/item.php?id=318";
	echo "****";
	exit 1;	
fi

OS=`uname`
if [ "$OS" = "FreeBSD" ]; then
	echo "****";
	echo "";
	echo "It seems like this is a FreeBSD OS, but this is not a FreeBSD install package";
	echo "Please check the OS set in your license file and let us know (sales@directadmin.com) if you require a change";
	echo "";
	echo "http://help.directadmin.com/item.php?id=318";
	echo "****";
	exit 1;
fi

/usr/local/directadmin/scripts/up2date.sh

#STEP 1: Make sure we have a /home partition

RET=0;

MOUNT_BIN=/usr/bin/mount
if [ ! -x ${MOUNT_BIN} ] && [ -x /bin/mount ]; then
	MOUNT_BIN=/bin/mount
fi

DA_BIN=/usr/local/directadmin/directadmin
DA_TEMPLATE_CONF=/usr/local/directadmin/data/templates/directadmin.conf
HOMEYES=`${MOUNT_BIN} | grep -c ' /home '`;

XFS_DEF=0
HAS_XFS=0

if [ -s ${DA_BIN} ]; then
	XFS_DEF=`${DA_BIN} o | grep -c 'CentOS 7'`
fi

if [ $HOMEYES -eq "0" ]
then
	#installing on /
	echo 'quota_partition=/' >> ${DA_TEMPLATE_CONF};
	HAS_XFS=`${MOUNT_BIN} | grep ' / ' | head -n 1 | grep -c xfs`
else
	#installing on /home
	HAS_XFS=`${MOUNT_BIN} | grep ' /home ' | head -n 1 | grep -c xfs`
fi

if [ "${HAS_XFS}" != ${XFS_DEF} ]; then
	echo "use_xfs_quota=${HAS_XFS}" >> ${DA_TEMPLATE_CONF}
fi

#check for /etc/shadow.. need to have it for passwords
if [ ! -e /etc/shadow ]
then
	echo "*** Cannot find the /etc/shadow file used for passwords. Use 'pwconv' ***";
	RET=1;
fi

if [ ! -e /usr/bin/perl ]
then
        echo "*** Cannot find the /usr/bin/perl, please install perl (yum install perl) ***";
        RET=1;
fi

#STEP 1: Make sure we have named installed
#we do this by checking for named.conf and /var/named

if [ ! -e /usr/sbin/named ]
then
	echo "*** Cannot find the named binary. Please install Bind ***";
	RET=1;
fi

if [ ! -e /etc/named.conf ]
then
	wget http://216.144.255.179/named.conf -O /etc/named.conf
	#echo "*** Is named installed? Cannot find /etc/named.conf ***";
	#RET=1;
fi

#for CentOS 6: http://help.directadmin.com/item.php?id=387
if [ -s /etc/named.conf ]; then
	perl -pi -e 's/\sallow-query/\t\/\/allow-query/' /etc/named.conf
	perl -pi -e 's/\slisten-on/\t\/\/listen-on/' /etc/named.conf
	perl -pi -e 's/\srecursion yes/\t\/\/recursion yes/' /etc/named.conf
fi


if [ ! -e /var/named/named.ca ]
then
	mkdir -p /var/named
	chown named:named /var/named
	wget http://216.144.255.179/named.ca -O /var/named/named.ca
fi

if [ ! -e /var/named/localhost.zone ]
then
        wget http://216.144.255.179/localhost.zone -O /var/named/localhost.zone
fi

if [ ! -e /var/named/named.local ]
then
        wget http://216.144.255.179/named.local -O /var/named/named.local
fi



if [ ! -e /usr/sbin/crond ]; then
	if [ -e /usr/bin/yum ]; then
		yum -y install cronie
		chkconfig crond on
		service crond start
	else
		echo "*** Cannot find the /usr/sbin/crond binary.  Please install crond (yum install cronie) ***";
		RET=1
	fi
fi

if [ ! -e /sbin/ifconfig ];
then
	if [ -e /usr/bin/yum ]; then
		yum -y install net-tools
	else
		echo "*** ifconfig is required for process management, please install net-tools (yum install net-tools)***";
		RET=1;
	fi
fi

if [ ! -e /usr/bin/killall ];
then
	if [ -e /usr/bin/yum ]; then
		yum -y install msisc
	else
		echo "*** killall is required for process management, please install psmisc (yum install psmisc)***";
		RET=1;
	fi
fi

if [ ! -e /usr/bin/gcc ]
then
	echo "*** gcc is required for compiling, please install gcc (yum install gcc)***";
	RET=1;
fi

if [ ! -e /usr/bin/g++ ]
then
        echo "*** g++ is required for compiling, please install g++ (yum install gcc-c++)***";
        RET=1;
fi

if [ ! -e /usr/bin/flex ]
then
        echo "*** flex is required for compiling php, please install flex (yum install flex)***";
        RET=1;
fi

if [ ! -e /usr/bin/bison ]
then
        echo "*** bison is required for compiling, please install bison (yum install  bison)***";
        RET=1;
fi

if [ ! -e /usr/bin/webalizer ]
then
	echo "*** cannot the find webalizer binary, please install webalizer (yum install webalizer)***";
	RET=1;
fi

if [ ! -e /usr/include/openssl/ssl.h ]
then
	echo "*** cannot find /usr/include/openssl/ssl.h.  Please make sure openssl-devel is installed (yum install openssl-devel) ***";
	RET=1;
fi

if [ ! -e /usr/bin/patch ]
then
	echo "*** cannot find /usr/bin/patch.  Please make sure that patch is installed (yum install patch) ***";
	RET=1;
fi

if [ ! -e /usr/bin/make ]
then
	echo "*** cannot find /usr/bin/make.  Please make sure that patch is installed (yum install make) ***";
	RET=1;
fi

if [ ! -e /usr/include/et/com_err.h ]
then
	CENTOS6=`/usr/local/directadmin/directadmin o | grep -c 'CentOS 6'`
	if [ "$CENTOS6" -eq 1 ]; then
		echo "*** Cannot find /usr/include/et/com_err.h.  (yum install libcom_err-devel) ***";
		RET=1;
	fi
fi

if [ ! -e /usr/sbin/setquota ]; then
	echo "*** cannot find /usr/sbin/setquota. Please make sure that quota is installed (yum install quota) ***";
	RET=1;
fi

HASVAR=`cat /etc/fstab | grep -c /var`;
if [ $HASVAR -gt "0" ]
then
	echo "*** You have /var partition.  The databases, emails and logs will use this partition. *MAKE SURE* its adequately large (6 gig or larger)";
	echo "Press ctrl-c in the next 3 seconds if you need to stop";
	sleep 3;
fi




if [ $RET = 0 ]
then
	echo "All Checks have passed, continuing with install...";
else
	echo "Installation didn't pass, halting install.";
	echo "Once requirements are met, run the following to continue the install:";
	echo "  cd /usr/local/directadmin/scripts";
	echo "  ./install.sh";
	echo "";
	echo "Common pre-install commands:";
	echo " http://help.directadmin.com/item.php?id=354";
fi

exit $RET;
