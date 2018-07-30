#!/bin/sh
# This script is written by Martynas Bendorius and DirectAdmin
# It is used to convert reseller to user
# Official DirectAdmin webpage: http://www.directadmin.com
# Usage:
# ./reseller_to_user.sh <user>

if [ $UID != 0 ]; then
        echo "You require Root Access to run this script";
        exit 0;
fi

if [ $# != 2 ]; then
        echo "Usage:";
        echo "  $0 <user> <reseller>";
        echo "you gave #$#: $0 $1 $2";
		echo "where:"
		echo "user: name of the account to downgrade."
		echo "reseller: name of the new creator of the User: eg: admin";
        exit 0;
fi

RESELLER_LIST=${BASEDIR}/admin/reseller.list
BASEDIR=/usr/local/directadmin/data
USR=$1
NEW_CREATOR=$2
NEW_CREATOR_IP_LIST=${BASEDIR}/users/${NEW_CREATOR}/ip.list
RESELLER_LIST=${BASEDIR}/admin/reseller.list
USER_DATA=${BASEDIR}/users/$USR
USER_CONF=${USER_DATA}/user.conf
USER_BACKUP_CONF=${USER_DATA}/backup.conf
RESELLER_ALLOC=${USER_DATA}/reseller.allocation
RESELLER_CONF=${USER_DATA}/reseller.conf
RESELLER_USAGE=${USER_DATA}/reseller.usage

if [ ! -d ${USER_DATA} ]; then
	echo "Directory ${USER_DATA} does not exist. Can not continue."
	exit 1;
fi

if [ "`grep -wc $USR ${RESELLER_LIST}`" = "0" ]; then
	echo "Reseller $USR is already user. Can not continue."
	exit 1;
fi

if [ ! -e /usr/bin/perl ]; then
	echo "/usr/bin/perl does not exist.";
	exit 1;
fi

echo "Re-configuring user directory /home/$USR."
rm -rf /home/$USR/user_backups
rm -rf /home/$USR/domains/default
rm -rf /home/$USR/domains/sharedip
rm -rf /home/$USR/domains/suspended

echo "Re-configuring DirectAdmin files."
# Changing usertype
perl -pi -e 's/usertype=reseller/usertype=user/' ${USER_CONF}

#if any IPs are managed by this Reseller, owernship should go to new creator.
for ip in `cat ${USER_DATA}/ip.list`; do
{
	IPFILE=${BASEDIR}/admin/ips/$ip
	
	C=`grep -c reseller=${USR} ${IPFILE}`
	if [ "$C" -gt 0 ]; then
		#swap reseller to new reseller.
		perl -pi -e "s/^creator=$USR\$/creator=$NEW_CREATOR/" $IPFILE
		
		#and add it to the new resellers list.
		C=`grep -c $ip $NEW_CREATOR_IP_LIST`
		if [ "$C" -eq 0 ]; then
			echo $ip >> $NEW_CREATOR_IP_LIST
		fi
	fi
};
done;


rm -f ${USER_BACKUP_CONF}
rm -f ${USER_DATA}/ip.list
rm -f ${USER_DATA}/login.hist
rm -f ${USER_DATA}/reseller.history
rm -f ${USER_DATA}/users.list
rm -f ${USER_DATA}/u_welcome.txt
rm -rf ${USER_DATA}/packages
rm -f ${USER_DATA}/packages.list
rm -f ${RESELLER_ALLOC}
rm -f ${RESELLER_CONF}
rm -f ${RESELLER_USAGE}
CREATOR=`grep "creator=" ${USER_CONF} | cut -d= -f2`
RESELLER_USERSLIST=${BASEDIR}/users/$NEW_CREATOR/users.list

# Editing ticket.conf
if [ -e ${USER_DATA}/ticket.conf ]; then
	ACTIVE="`grep 'active=' ${USER_DATA}/ticket.conf`"
	HTML="`grep 'html=' ${USER_DATA}/ticket.conf`"
	NEWTICKET="`grep 'newticket=' ${USER_DATA}/ticket.conf`"
	perl -pi -e "s#$ACTIVE\n##g" ${USER_DATA}/ticket.conf
	perl -pi -e "s#$HTML\n##g" ${USER_DATA}/ticket.conf
	perl -pi -e "s#$NEWTICKET\n##g" ${USER_DATA}/ticket.conf
fi

echo "Adding user to the $2 reseller."
echo "$USR" >> ${RESELLER_USERSLIST}

echo "Removing user from the reseller list."
perl -pi -e "s#$USR\n##g" ${RESELLER_LIST}

echo "Changing user owner"
perl -pi -e "s/creator=$CREATOR/creator=$NEW_CREATOR/g" ${USER_CONF}

#this is needed to update "show all users" cache.
echo "action=cache&value=showallusers" >> /usr/local/directadmin/data/task.queue
/usr/local/directadmin/dataskq

echo "Reseller $USR has been converted to user."

exit 0;
