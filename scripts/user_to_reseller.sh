#!/bin/sh
# This script is written by Martynas Bendorius and DirectAdmin
# It is used to convert user to reseller
# Official DirectAdmin webpage: http://www.directadmin.com
# Usage:
# ./user_to_reseller.sh <user>

MYUID=`/usr/bin/id -u`
if [ "$MYUID" != 0 ]; then
        echo "You require Root Access to run this script";
        exit 0;
fi

if [ $# != 1 ]; then
        echo "Usage:";
        echo "$0 <user>";
        echo "you gave #$#: $0 $1";
        exit 0;
fi

USERNAME=$1

BASEDIR=/usr/local/directadmin/data

ADMIN_DATA=${BASEDIR}/users/admin
RESELLER_LIST=${BASEDIR}/admin/reseller.list

USER_DATA=${BASEDIR}/users/$1
USER_BACKUP_CONF=${USER_DATA}/backup.conf
USER_CONF=${USER_DATA}/user.conf
USER_USAGE=${USER_DATA}/user.usage

RESELLER_ALLOC=${USER_DATA}/reseller.allocation
RESELLER_CONF=${USER_DATA}/reseller.conf
RESELLER_USAGE=${USER_DATA}/reseller.usage

if [ ! -d ${USER_DATA} ]; then
	echo "Directory ${USER_DATA} does not exist. Can not continue."
	exit 1;
fi

if [ "`grep -wc $1 ${RESELLER_LIST}`" = "1" ]; then
	echo "User $1 is already reseller. Can not continue."
	exit 1;
fi

if [ ! -e /usr/bin/perl ]; then
	echo "/usr/bin/perl does not exist.";
	exit 1;
fi

echo "Re-configuring user directory /home/$1."
mkdir -p /home/$1/user_backups
mkdir -p /home/$1/domains/default
mkdir -p /home/$1/domains/sharedip
mkdir -p /home/$1/domains/suspended
cp -R ${BASEDIR}/templates/default/* /home/$1/domains/default
chown -R $1:$1 /home/$1/user_backups
chown -R $1:$1 /home/$1/domains/default
chown -R $1:$1 /home/$1/domains/sharedip
chown -R $1:$1 /home/$1/domains/suspended

SAG=`/usr/local/directadmin/directadmin c | grep secure_access_group | cut -d= -f2`
if [ "$SAG" != "" ]; then
	if [ "$SAG" != '(null)' ]; then
		#must be set to something, and not null, thus on.
		chown $1:$1 /home/$1
		chmod 711 /home/$1
		chown $1:${SAG} /home/$1/domains
		chmod 750 /home/$1/domains
	fi
fi


echo "Re-configuring DirectAdmin files."
# Changing usertype
perl -pi -e 's/usertype=user/usertype=reseller/' ${USER_CONF}

# Creating backup.conf
if [ ! -e ${USER_BACKUP_CONF} ]; then
	echo -n "" > ${USER_BACKUP_CONF}
	echo "ftp_ip=" >> ${USER_BACKUP_CONF}
	echo "ftp_password=" >> ${USER_BACKUP_CONF}
	echo "ftp_path=/" >> ${USER_BACKUP_CONF}
	echo "ftp_username=" >> ${USER_BACKUP_CONF}
	echo "local_path=" >> ${USER_BACKUP_CONF}
fi
# Creating ip.list
if [ ! -e ${USER_DATA}/ip.list ]; then
	grep "ip=" ${USER_DATA}/user.conf | cut -d= -f2 > ${USER_DATA}/ip.list
fi
# Creating everything else
touch ${USER_DATA}/login.hist
touch ${USER_DATA}/reseller.history
touch ${USER_DATA}/users.list
cp -f ${ADMIN_DATA}/u_welcome.txt ${USER_DATA}/u_welcome.txt

# Creating packages
mkdir -p ${USER_DATA}/packages
touch ${USER_DATA}/packages.list

# Creating reseller.allocation
if [ ! -e ${RESELLER_ALLOC} ]; then
	echo -n "" > ${RESELLER_ALLOC}
	grep "bandwidth=" ${USER_CONF} >> ${RESELLER_ALLOC}
	grep "domainptr=" ${USER_CONF} >> ${RESELLER_ALLOC}
	grep "ftp=" ${USER_CONF} >> ${RESELLER_ALLOC}
	grep "mysql=" ${USER_CONF} >> ${RESELLER_ALLOC}
	grep "nemailf=" ${USER_CONF} >> ${RESELLER_ALLOC}
	grep "nemailml=" ${USER_CONF} >> ${RESELLER_ALLOC}
	grep "nemailr=" ${USER_CONF} >> ${RESELLER_ALLOC}
	grep "nemails=" ${USER_CONF} >> ${RESELLER_ALLOC}
	grep "nsubdomains=" ${USER_CONF} >> ${RESELLER_ALLOC}
	echo "nusers=0" >> ${RESELLER_ALLOC}
	grep "quota=" ${USER_CONF} >> ${RESELLER_ALLOC}
	grep "vdomains=" ${USER_CONF} >> ${RESELLER_ALLOC}
fi

# Editing ticket.conf
if [ -e ${USER_DATA}/ticket.conf ] && [ "`grep -c 'active=' ${USER_DATA}/ticket.conf`" = "0" ]; then
	echo "active=yes" >> ${USER_DATA}/ticket.conf
	echo 'html=Follow <a href="http://www.domain.com/support">this link</a> for a 3rd party ticket system.' >> ${USER_DATA}/ticket.conf
	echo "newticket=0" >> ${USER_DATA}/ticket.conf
fi

# Creating reseller.conf
if [ ! -e ${RESELLER_CONF} ]; then
	egrep -v "account=|creator=|date_created=|docsroot=|domain=|email=|ip=|name=|skin=|suspend_at_limit=|suspended=|username=|usertype=|zoom=|language=" ${USER_CONF} > ${RESELLER_CONF}
	echo "userssh=ON" >> ${RESELLER_CONF}
	echo "dns=ON" >> ${RESELLER_CONF}
	echo "ip=shared" >> ${RESELLER_CONF}
	echo "ips=0" >> ${RESELLER_CONF}
	echo "oversell=ON" >> ${RESELLER_CONF}
	echo "serverip=ON" >> ${RESELLER_CONF}
	echo "subject=Your account for |domain| is now ready for use." >> ${RESELLER_CONF}
fi

# Creating reseller.usage
if [ ! -e ${RESELLER_USAGE} ]; then
	egrep -v "db_quota=|email_quota=" ${USER_USAGE} > ${RESELLER_USAGE}
	echo "nusers=1" >> ${RESELLER_USAGE}
fi

CREATOR=`grep "creator=" ${USER_CONF} | cut -d= -f2`
CREATOR_USERSLIST=${BASEDIR}/users/${CREATOR}/users.list
echo "Removing user from the other reseller."
perl -pi -e "s#$1\n##g" ${CREATOR_USERSLIST}

# Setting permissions
chmod 600 ${USER_DATA}/backup.conf ${USER_DATA}/reseller.usage ${USER_DATA}/reseller.conf ${USER_DATA}/reseller.allocation ${USER_DATA}/packages.list ${USER_DATA}/login.hist ${USER_DATA}/reseller.history ${USER_DATA}/users.list
chmod 700 ${USER_DATA}/packages
chmod 644 ${USER_DATA}/u_welcome.txt
chown -R diradmin:diradmin ${USER_DATA}/packages ${USER_DATA}/u_welcome.txt ${USER_DATA}/backup.conf ${USER_DATA}/reseller.usage ${USER_DATA}/reseller.conf ${USER_DATA}/reseller.allocation ${USER_DATA}/packages.list ${USER_DATA}/login.hist ${USER_DATA}/reseller.history ${USER_DATA}/users.list

echo "Adding reseller to $3 reseller list"
echo "$1" >> ${RESELLER_LIST}

echo "Changing user owner"
perl -pi -e "s/creator=$CREATOR/creator=admin/g" ${USER_CONF}

#this is needed to update "show all users" cache.
echo "action=cache&value=showallusers" >> /usr/local/directadmin/data/task.queue
/usr/local/directadmin/dataskq

echo "User $1 has been converted to reseller."

exit 0;
