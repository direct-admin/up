#!/bin/sh
#This script will ensure that the quotas are set in the fstab file

echo "Checking quotas...";

FSTAB="/etc/fstab"

/usr/bin/perl -pi -e 's/[\ \t]+\/home[\ \t]+ext3[\ \t]+defaults[\ \t]+/\t\t\/home\t\t\text3\tdefaults,usrquota,grpquota\t/' $FSTAB
/usr/bin/perl -pi -e 's/[\ \t]+\/[\ \t]+ext3[\ \t]+defaults[\ \t]+/\t\t\t\/\t\t\text3\tdefaults,usrquota,grpquota\t/' $FSTAB

/usr/bin/perl -pi -e 's/[\ \t]+\/home[\ \t]+ext4[\ \t]+defaults[\ \t]+/\t\t\/home\t\t\text4\tdefaults,usrquota,grpquota\t/' $FSTAB
/usr/bin/perl -pi -e 's/[\ \t]+\/[\ \t]+ext4[\ \t]+defaults[\ \t]+/\t\t\t\/\t\t\text4\tdefaults,usrquota,grpquota\t/' $FSTAB

/usr/bin/perl -pi -e 's/[\ \t]+\/home[\ \t]+ext4[\ \t]+defaults,errors=continue[\ \t]+/\t\t\/home\t\t\text4\tdefaults,errors=continue,usrquota,grpquota\t/' $FSTAB
/usr/bin/perl -pi -e 's/[\ \t]+\/[\ \t]+ext4[\ \t]+defaults,errors=continue[\ \t]+/\t\t\t\/\t\t\text4\tdefaults,errors=continue,usrquota,grpquota\t/' $FSTAB

/usr/bin/perl -pi -e 's/[\ \t]+\/home[\ \t]+ext3[\ \t]+errors=remount-ro[\ \t]+/\t\t\/home\t\t\text3\terrors=remount-ro,usrquota,grpquota\t/' $FSTAB
/usr/bin/perl -pi -e 's/[\ \t]+\/[\ \t]+ext3[\ \t]+errors=remount-ro[\ \t]+/\t\t\t\/\t\t\text3\terrors=remount-ro,usrquota,grpquota\t/' $FSTAB

/usr/bin/perl -pi -e 's/[\ \t]+\/home[\ \t]+ext4[\ \t]+defaults,errors=remount-ro[\ \t]+/\t\t\/home\t\t\text4\tdefaults,errors=remount-ro,usrquota,grpquota\t/' $FSTAB
/usr/bin/perl -pi -e 's/[\ \t]+\/[\ \t]+ext4[\ \t]+defaults,errors=remount-ro[\ \t]+/\t\t\t\/\t\t\text4\tdefaults,errors=remount-ro,usrquota,grpquota\t/' $FSTAB

/usr/bin/perl -pi -e 's/[\ \t]+\/home[\ \t]+ext4[\ \t]+errors=remount-ro[\ \t]+/\t\t\/home\t\t\text4\terrors=remount-ro,usrquota,grpquota\t/' $FSTAB
/usr/bin/perl -pi -e 's/[\ \t]+\/[\ \t]+ext4[\ \t]+errors=remount-ro[\ \t]+/\t\t\t\/\t\t\text4\terrors=remount-ro,usrquota,grpquota\t/' $FSTAB

/usr/bin/perl -pi -e 's/[\ \t]+\/home[\ \t]+ext4[\ \t]+defaults[\ \t]+/\t\t\/home\t\t\text4\tdefaults,usrquota,grpquota\t/' $FSTAB
/usr/bin/perl -pi -e 's/[\ \t]+\/[\ \t]+ext4[\ \t]+defaults[\ \t]+/\t\t\t\/\t\t\text4\tdefaults,usrquota,grpquota\t/' $FSTAB

/usr/bin/perl -pi -e 's/[\ \t]+\/home[\ \t]+xfs[\ \t]+defaults[\ \t]+/\t\t\/home\t\t\txfs\tdefaults,uquota,gquota\t/' $FSTAB
/usr/bin/perl -pi -e 's/[\ \t]+\/[\ \t]+xfs[\ \t]+defaults[\ \t]+/\t\t\t\/\t\t\txfs\tdefaults,uquota,gquota\t/' $FSTAB

#run it again with a variance
if [ -e /etc/debian_version ]; then

	/usr/bin/perl -pi -e 's/[\ \t]+\/home[\ \t]+ext3[\ \t]+defaults,errors=remount-ro[\ \t]+/\t\t\/home\t\t\text3\tdefaults,errors=remount-ro,usrquota,grpquota\t/' $FSTAB
	/usr/bin/perl -pi -e 's/[\ \t]+\/[\ \t]+ext3[\ \t]+defaults,errors=remount-ro[\ \t]+/\t\t\t\/\t\t\text3\tdefaults,errors=remount-ro,usrquota,grpquota\t/' $FSTAB

	/usr/bin/perl -pi -e 's/(\s)+\/home(\s)+ext4(\s)+errors=remount-ro(\s)+/\t\t\t\/home\t\t\text4\terrors=remount-ro,usrquota,grpquota\t/' $FSTAB
	/usr/bin/perl -pi -e 's/(\s)+\/(\s)+ext4(\s)+errors=remount-ro(\s)+/\t\t\t\/\t\t\text4\terrors=remount-ro,usrquota,grpquota\t/' $FSTAB
fi


#hide the errors, it was confusing people
/bin/mount -o remount,rw /home 2> /dev/null 1> /dev/null
/bin/mount -o remount,rw / 2> /dev/null 1> /dev/null
/sbin/quotaoff -a 2> /dev/null
/sbin/quotacheck -cavugmf 2> /dev/null
/sbin/quotaon -a

exit 0;
