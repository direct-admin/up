#!/bin/sh
# This script is written by Martynas Bendorius and DirectAdmin
# It is used to install AWstats into DirectAdmin servers
# Official AWstats webpage: http://www.awstats.org

#AWSTATS_VER=6.95
#link bug?
#http://www.directadmin.com/forum/showthread.php?p=193914#post193914
AWSTATS_VER=7.7

DA_SCRIPTS=/usr/local/directadmin/scripts
DA_CONF=/usr/local/directadmin/conf/directadmin.conf
DA_TEMPLATE_CONF=/usr/local/directadmin/data/templates/directadmin.conf
HTTPPATH=http://files.directadmin.com/services/all/awstats
TARFILE=${DA_SCRIPTS}/packages/awstats-${AWSTATS_VER}.tar.gz
USR=/usr/local
REALPATH=${USR}/awstats-${AWSTATS_VER}
ALIASPATH=${USR}/awstats

OS=`uname`

if [ "${OS}" = "FreeBSD" ]; then
	WGET=/usr/local/bin/wget
	TAR=/usr/bin/tar
	CHOWN=/usr/sbin/chown
	ROOTGRP=wheel
else
	WGET=/usr/bin/wget
	TAR=/bin/tar
	CHOWN=/bin/chown
	ROOTGRP=root
fi 

if [ ! -e ${TARFILE} ]; then
	${WGET} -O ${TARFILE} ${HTTPPATH}/awstats-${AWSTATS_VER}.tar.gz
fi

if [ ! -e ${TARFILE} ]; then
	echo "Can not download awstats-${AWSTATS_VER}"
	exit 1
fi

#Extract the file
${TAR} xzf ${TARFILE} -C ${USR}

if [ ! -e ${REALPATH} ]; then
	echo "Directory ${REALPATH} does not exist"
	exit 1
fi

#link it from a fake path:
/bin/rm -f ${ALIASPATH}
/bin/ln -sf awstats-${AWSTATS_VER} ${ALIASPATH}
cd ${REALPATH}
${CHOWN} -R root:${ROOTGRP} ${REALPATH}
chmod -R 755 ${REALPATH}


#patch the url bug: this is ni the 7.3 tar.gz file, so no need to patch. Creates a patch rej file.
#echo "Patching awstats_buildstaticpages.pl to fix url bug...";
#cd ${REALPATH}/tools
#wget -O awstats_url.patch http://files.directadmin.com/services/custombuild/patches/awstats_url.patch
#if [ ! -s awstats_url.patch ]; then
#	echo "Error with awstats_url.patch. File is missing or empty";
#else
#	patch -p0 < awstats_url.patch
#fi

#sets the value of $1 to $2 in the file $3
setVal()
{
	if [ ! -e $3 ]; then
		return;
	fi

	COUNT=`grep -c $1 $3`
	if [ "$COUNT" -eq 0 ]; then
		#ok, it's not there, add it.
		echo "$1=$2" >> $3
		return;
	else
		#ok, the value is already in the file $3, so use perl to regex it.
		perl -pi -e "s/`grep ${1}= ${3}`/${1}=${2}/" ${3}
	fi
}

#setup the directadmin.conf
#disable webalizer, enable awstats.

setVal awstats 1 ${DA_TEMPLATE_CONF}
setVal webalizer 0 ${DA_TEMPLATE_CONF}
setVal awstats 1 ${DA_CONF}
setVal webalizer 0 ${DA_CONF}

echo "action=directadmin&value=restart" >> /usr/local/directadmin/data/task.queue

echo "AWstats package is installed."

