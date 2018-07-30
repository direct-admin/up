#!/bin/sh
# This script is written by Martynas Bendorius and DirectAdmin
# It is used to move user from one reseller to another
# Official DirectAdmin webpage: http://www.directadmin.com
# Usage:
# ./move_user_to_reseller.sh <user> <oldreseller> <newreseller>

MYUID=`/usr/bin/id -u`
if [ "$MYUID" != 0 ]; then
        echo "You require Root Access to run this script";
        exit 0;
fi

if [ $# != 3 ]; then
        echo "Usage:";
        echo "$0 <user> <oldreseller> <newreseller>";
        echo "you gave #$#: $0 $1 $2 $3";
        exit 0;
fi

OLD_RESELLER=$2
NEW_RESELLER=$3

RESELLER_OLD=/usr/local/directadmin/data/users/$2/users.list
RESELLER_NEW=/usr/local/directadmin/data/users/$3/users.list

USERN=$1

if [ ! -e ${RESELLER_OLD} ]; then
	echo "File ${RESELLER_OLD} does not exist. Can not continue."
	exit 1;
fi

if [ ! -e ${RESELLER_NEW} ]; then
	echo "File ${RESELLER_NEW} does not exist. Can not continue."
	exit 1;
fi

if [ "`grep -wc $USERN $RESELLER_OLD`" = "0" ]; then
	echo "User $USERN is not owned by $2 reseller"
	exit 1;
fi

if [ ! -e /usr/bin/perl ]; then
	echo "/usr/bin/perl does not exist";
	exit 1;
fi

isOwned()
{
	IP=$1
	IPF=/usr/local/directadmin/data/admin/ips/$IP
	if [ ! -s $IPF ]; then
		#good spot for an error message, but can't echo anything
		echo "0";
		return;
	fi
	IPSTATUS=`grep status= $IPF | cut -d= -f2`;
	if [ "$IPSTATUS" = "owned" ]; then
		echo "1";
	else
		echo "0";
	fi
}

#ensure IPs are brought forward
for i in `cat /usr/local/directadmin/data/users/$USERN/user_ip.list`; do
{
	if [ "`isOwned $i`" = "1" ]; then
		echo "$i is owned. Moving the IP to the new Reseller";
		
		perl -pi -e "s#$i\n##g" /usr/local/directadmin/data/users/$OLD_RESELLER/ip.list
		echo "$i" >> /usr/local/directadmin/data/users/$NEW_RESELLER/ip.list
		
		perl -pi -e "s#reseller=$OLD_RESELLER#reseller=$NEW_RESELLER#g" /usr/local/directadmin/data/admin/ips/$i
	else
		echo "$i is shared. Leaving the IP with the old Reseller";
	fi
};
done;


echo "Removing user from $2 reseller"
perl -pi -e "s#$USERN\n##g" /usr/local/directadmin/data/users/$2/users.list

echo "Adding user to $3 reseller"
echo "$USERN" >>  /usr/local/directadmin/data/users/$3/users.list

echo "Changing user owner"
for i in `ls /usr/local/directadmin/data/users/$USERN/domains/*.conf`; do { perl -pi -e "s/creator=$2/creator=$3/g" $i; }; done;

#change the user.conf
perl -pi -e "s/creator=$2/creator=$3/" /usr/local/directadmin/data/users/$USERN/user.conf

#this is needed to update "show all users" cache.
echo "action=cache&value=showallusers" >> /usr/local/directadmin/data/task.queue
echo "action=rewrite&value=httpd&user=$USERN" >> /usr/local/directadmin/data/task.queue

#messy bit that removes the user from the backup_crons.list, but only for type=reseller backups.
#the user is left in the admin backups still in the type=admin backups.
perl -pi -e "s/select[0-9]+=$USERN&(.*)(type=reseller)/\$1\$2/" /usr/local/directadmin/data/admin/backup_crons.list

echo "User has been moved to $3"

exit 0;
