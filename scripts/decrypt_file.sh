#!/bin/sh

if [ "$#" -ne 3 ]; then

        echo "Usage:";
        echo "  $0 <encryptedin> <fileout> <passwordfile>"
		echo ""
        exit 1
fi

OPENSSL=/usr/bin/openssl

E=$1
O=$2
P=$3

if [ "${E}" = "" ] || [ ! -e ${E} ]; then
	echo "Cannot find $F for decryption"
	exit 2;
fi

if [ "${O}" = "" ]; then
	echo "Please pass a destination path"
	exit 3;
fi

if [ "${P}" = "" ] || [ ! -s ${P} ]; then
	echo "Cannot find passwordfile $P"
	exit 4
fi

${OPENSSL} enc -d -aes-256-cbc -salt -in $E -out $O -kfile ${P} 2>&1

RET=$?

exit $RET