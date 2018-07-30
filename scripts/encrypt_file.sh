#!/bin/sh

if [ "$#" -ne 3 ]; then

        echo "Usage:";
        echo "  $0 <filein> <encryptedout> <passwordfile>"
		echo ""
        exit 1
fi

OPENSSL=/usr/bin/openssl

F=$1
E=$2
P=$3

if [ "${F}" = "" ] || [ ! -e ${F} ]; then
	echo "Cannot find $F for encryption"
	exit 2;
fi

if [ "${E}" = "" ]; then
	echo "Please pass a destination path"
	exit 3;
fi

if [ "${P}" = "" ] || [ ! -s ${P} ]; then
	echo "Cannot find passwordfile $P"
	exit 4
fi

${OPENSSL} enc -e -aes-256-cbc -salt -in $F -out $E -kfile ${P} 2>&1

RET=$?

exit $RET