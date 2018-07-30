#!/bin/sh

#script to regenerate the data files in /usr/local/directadmin/data/users/username

DEBUG=0;
OS=`uname`;

DA_PATH=/usr/local/directadmin
DA_USR=$DA_PATH/data/users

#change this value if the user was created by someone else.
CREATOR=admin

IP=`grep -H server /usr/local/directadmin/data/admin/ips/* | cut -d: -f1 | cut -d/ -f8`

#If you don't want the user to be on the server IP, then specify the correct IP here (remove the #)
#IP=1.2.3.4

NS1=`grep ns1 /usr/local/directadmin/conf/directadmin.conf | cut -d= -f2`
NS2=`grep ns2 /usr/local/directadmin/conf/directadmin.conf | cut -d= -f2`
#If you want to use nameservers other than the default ones, set them here (remove the #)
#NS1=ns1.yourns.com
#NS2=ns2.yourns.com


#To set the domain, pass it as the 3rd argument when runnign the script. Don't change this value.
DOMAIN="";

#default package.  To change the package, edit this value ('default' probably doesn't exist, but no harm done)
PACKAGE=default


help()
{
	echo "DirectAdmin data restore (beta)";
	echo "";
	echo "Usage: $0 <username> <user|reseller|admin> (<domain>)";
	echo "";
	echo "<username> is required."
	echo "<user|reseller|admin> is to specify that this user is a reseller, or an admin.";
	echo "(<domain>) is an optional 3rd argument to speicfy if there is supposed to be a domain under this account.";
	echo "";
	echo "Note: the creator in the user.conf will be set to 'admin'. If it should be something else, edit the CREATOR value in this script";
	exit 1;
}

debug()
{
	if [ $DEBUG -eq 1 ]; then
		echo $1
	fi
}

add_to_file()
{
	#usage:
	#add_to_file name val filename
	#
	#it will add name=val to filename if name doesn't already exist.
	#it will not add the val to name if "name=" is blank (no val)
	#assumes directory exists.
	
	if [ ! -e $3 ]; then
		COUNT=0;
	else
		COUNT=`grep -c -e "^$1=" $3`;
	fi

	if [ $COUNT -eq 0 ]; then

		echo "$1=$2" >> $3

	fi

	#else it already is in the file. don't touch it.
}

set_file()
{

	#set_file /path/file user:user 711
	#file is created if it doesn't exist

	if [ ! -e $1 ]; then
		touch $1;
	fi

	chown $2 $1
	chmod $3 $1
}

create_dir()
{
	#create_dir /path/to/dir user:user 711

        if [ ! -e $1 ]; then
                mkdir -p $1
        fi
        chown $2 $1
        chmod $3 $1
	
}

fix_admin()
{
	debug "fix_admin $1"
	fix_reseller $1 admin
}

fix_reseller()
{
	debug "fix_reseller $1 $2";

	fix_user $1 $2

	set_file $DA_USR/$1/backup.conf diradmin:diradmin 600
	
	echo "$IP" >> $DA_USR/$1/ip.list
	set_file $DA_USR/$1/ip.list diradmin:diradmin 600

	create_dir $DA_USR/$1/packages diradmin:diradmin 700
	set_file $DA_USR/$1/packages.list diradmin:diradmin 600
	set_file $DA_USR/$1/reseller.allocation diradmin:diradmin 600
	set_file $DA_USR/$1/reseller.usage diradmin:diradmin 600
	set_file $DA_USR/$1/reseller.history diradmin:diradmin 600

	FILE=$DA_USR/$1/reseller.conf
        add_to_file aftp ON $FILE
        add_to_file bandwidth unlimited $FILE
        add_to_file cgi ON $FILE
        add_to_file dns ON $FILE
        add_to_file dnscontrol ON $FILE
	add_to_file domainptr unlimited $FILE
        add_to_file ftp unlimited $FILE
        add_to_file ip shared $FILE
	add_to_file ips 0 $FILE
        add_to_file mysql unlimited $FILE
        add_to_file nemailf unlimited $FILE
        add_to_file nemailml unlimited $FILE
        add_to_file nemailr unlimited $FILE
        add_to_file nemails unlimited $FILE

        add_to_file ns1 $NS1 $FILE
        add_to_file ns2 $NS2 $FILE
        add_to_file nsubdomains unlimited $FILE
	add_to_file oversell ON $FILE
	add_to_file package custom $FILE
        add_to_file php ON $FILE
        add_to_file quota unlimited $FILE
        add_to_file sentwarning no $FILE
	add_to_file serverip ON $FILE
        add_to_file spam ON $FILE
        add_to_file ssh OFF $FILE
        add_to_file ssl OFF $FILE
        add_to_file subject "Your account for \|domain\| is now ready for use." $FILE
	add_to_file userssh OFF $FILE
        add_to_file vdomains unlimited $FILE

        set_file $FILE diradmin:diradmin 600

	FILE=$DA_USR/$1/ticket.conf
	add_to_file active yes $FILE
	add_to_file html "Follow <a href=\"http://www.domain.com/support\">this link</a> for a 3rd party ticket system." $FILE
	add_to_file newticket 0 $FILE

	
	#refill the users.list
	FILE=$DA_USR/$1/users.list
	
	#grep -H creator=$1 $DA_USR/*/user.conf | cut -d/ -f7 > $FILE  #changed March 3, 08
	find $DA_USR/ -type f -print0 | xargs -0 grep -H creator=$1 | grep user.conf | cut -d/ -f7 > $FILE
	set_file $FILE diradmin:diradmin 600

	FILE=$DA_PATH/data/admin/$2.list
	COUNT=`grep -c -e "^$1$" $FILE`
	if [ $COUNT -eq 0 ]; then
		echo $1 >> $FILE
	fi

}

add_domain()
{
	debug "add_domain $1 $2 $3";

	#add_domain domain.com username 1.2.3.4

	echo "$1" >> $DA_USR/$2/domains.list

	DFILE=$DA_USR/$2/domains/$1.conf
	add_to_file UseCanonicalName OFF $DFILE
	add_to_file bandwidth unlimited $DFILE
	add_to_file cgi ON $DFILE
	add_to_file defaultdomain yes $DFILE
	add_to_file domain $1 $DFILE
	add_to_file ip $3 $DFILE
	add_to_file php ON $DFILE
	add_to_file quota unlimited $DFILE
	add_to_file safemode OFF $DFILE
	add_to_file ssl ON $DFILE
	add_to_file suspended no $DFILE
	add_to_file username $2 $DFILE

	set_file $DFILE diradmin:diradmin 600

	DFILE=$DA_USR/$2/domains/$1.ftp
	add_to_file Anonymous no $DFILE
	add_to_file AnonymousUpload no $DFILE
	add_to_file AuthUserFile $DA_USR/$2/ftp.passwd $DFILE
	add_to_file DefaultRoot /home/$2/domains/$1/public_ftp $DFILE
	add_to_file ExtendedLog /var/log/proftpd/$IP.bytes $DFILE
	add_to_file MaxClients 10 $DFILE
	add_to_file MaxLoginAttempts 3 $DFILE
	add_to_file ServerAdmin webmaster@$1 $DFILE
	add_to_file ServerName ProFTPd $DFILE
	add_to_file defaultdomain yes $DFILE
	add_to_file ip $IP $DFILE

	set_file $DA_USR/$2/domains/$1.subdomains diradmin:diradmin 600
	set_file $DA_USR/$2/domains/$1.usage diradmin:diradmin 600

	echo "action=rewrite&value=httpd&user=$2" >> /usr/local/directadmin/data/task.queue;
}

fix_user()
{
	debug "fix_user $1 $2";

	#$1 is the username
	#$2 is the usertype (user,reseller,admin)

	#create /usr/local/directadmin/data/users/username
	create_dir $DA_USR/$1 diradmin:diradmin 711

        #create /usr/local/directadmin/data/users/username/domains
	create_dir $DA_USR/$1/domains diradmin:diradmin 711	
	
	#user.conf
	FILE=$DA_USR/$1/user.conf
	
	add_to_file account ON $FILE
	add_to_file aftp ON $FILE
	add_to_file bandwidth unlimited $FILE
	add_to_file cgi ON $FILE
	add_to_file creator $CREATOR $FILE

	add_to_file date_created "`date`" $FILE

	add_to_file dnscontrol ON $FILE
	add_to_file docsroot ./data/skins/enhanced $FILE
	add_to_file domainptr unlimited $FILE
	if [ "$DOMAIN" != "" ]; then
		add_to_file domain $DOMAIN $FILE
		add_to_file email $1@$DOMAIN $FILE

		add_domain $DOMAIN $1 $IP
	fi

	
	add_to_file ftp unlimited $FILE

	add_to_file ip $IP $FILE
	
	add_to_file language en $FILE
	add_to_file mysql unlimited $FILE
	add_to_file name $1 $FILE
	add_to_file nemailf unlimited $FILE
	add_to_file nemailml unlimited $FILE
	add_to_file nemailr unlimited $FILE
	add_to_file nemails unlimited $FILE
	
	add_to_file ns1 $NS1 $FILE
	add_to_file ns2 $NS2 $FILE

	add_to_file nsubdomains unlimited $FILE
	add_to_file package $PACKAGE $FILE
	add_to_file php ON $FILE
	add_to_file quota unlimited $FILE
	add_to_file sentwarning no $FILE
	add_to_file skin enhanced $FILE
	add_to_file spam ON $FILE
	add_to_file ssh OFF $FILE
	add_to_file ssl OFF $FILE
	add_to_file suspend_at_limit ON $FILE
	add_to_file suspended no $FILE
	add_to_file username $1 $FILE
	add_to_file usertype $2 $FILE
	add_to_file vdomains unlimited $FILE

	set_file $FILE diradmin:diradmin 600
	set_file $DA_USR/$1/user.usage diradmin:diradmin 600
	set_file $DA_USR/$1/user.history diradmin:diradmin 600
	set_file $DA_USR/$1/tickets.list diradmin:diradmin 600

	#ticket.conf
	FILE=$DA_USR/$1/ticket.conf
	add_to_file ON yes $FILE;
	add_to_file email '' $FILE;
	add_to_file new 0 $FILE;
	set_file $FILE diradmin:diradmin 600

	set_file $DA_USR/$1/ftp.passwd root:ftp 644

	set_file $DA_USR/$1/domains.list diradmin:diradmin 600
	set_file $DA_USR/$1/crontab.conf diradmin:diradmin 600

	if [ $OS = "FreeBSD" ]; then
		set_file $DA_USR/$1/bandwidth.tally root:wheel 644
	else
		set_file $DA_USR/$1/bandwidth.tally root:root 644
	fi


}

do_fix()
{
	if [ "$3" != "" ]; then
		#we have a domain
		DOMAIN=$3;
	fi

	case "$2" in
		admin)		fix_admin $1;
			;;
		reseller)	fix_reseller $1 reseller;
			;;
		user)		fix_user $1 user;
			;;
		*)		fix_user $1 user;
	esac
}

if [ $# -eq 0 ]; then
	help;
fi


case "$1" in
	?|--help|-?|-h) help;
		;;
	*) do_fix $1 $2 $3
		;;
esac

exit 0;
