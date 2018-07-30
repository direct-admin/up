#!/bin/sh

DIR=/etc/virtual/usage
USERS=/usr/local/directadmin/data/users

if [ ! -d $DIR ]; then
	exit 0;
fi

#for i in `ls $DIR | grep -e '.bytes$'`; do
for i in `ls ${DIR}/*.bytes 2>/dev/null | cut -d/ -f5`; do
{
	U_NAME=`echo $i | cut -d. -f1`
	#U_NAME=$i

	BF=${DIR}/${i}

	if [ ! -e ${BF} ]; then
		echo "rotate_email_usage.sh: cannot find ${BF}";
	fi

	if [ -d $USERS/$U_NAME ]; then
		echo "0=type=timestamp&time=`date +%s`" >> $USERS/$U_NAME/bandwidth.tally
		#cat $DIR/$i >> $USERS/$U_NAME/bandwidth.tally
		cat ${BF} >> $USERS/$U_NAME/bandwidth.tally
	else
		echo "rotate_email_usage.sh: Cannot find $USERS/$U_NAME";
	fi
};
done;

rm -rf $DIR/*

#remove per-email counts:
rm -f /etc/virtual/*/usage/*


#dovecot.bytes entries.
EV=/etc/virtual
for i in `ls ${EV}/*/dovecot.bytes 2>/dev/null | cut -d/ -f4`; do
{
	D=${EV}/${i};
	if [ -h $D ]; then
		continue;
	fi

	#if it's empty, ignore it.
	DB=${D}/dovecot.bytes
	if [ ! -s ${DB} ]; then
		continue;
	fi

	USERN=`grep -e "^$i:" /etc/virtual/domainowners | cut -d\  -f2`
	if [ "${USERN}" = "" ]; then
		echo "$i seems to be missing from /etc/virtual/domainowners";
		continue;
	fi
	
	DU=${USERS}/${USERN}
	if [ ! -d "${DU}" ]; then
		echo "Cannot find owner of $i from domainowners";
		continue;
	fi

	cat ${DB} >> ${DU}/bandwidth.tally

	rm -f ${DB};
};
done;


for i in `ls ${USERS}/*/dovecot.bytes 2>/dev/null | cut -d/ -f7`; do
{
	DU=${USERS}/${i}
	DB=${DU}/dovecot.bytes
	if [ ! -s ${DB} ]; then
		continue;
	fi

	cat ${DB} >> ${DU}/bandwidth.tally

	rm -f ${DB};
};
done;

exit 0;
