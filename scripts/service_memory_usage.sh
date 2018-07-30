#!/bin/sh

PS=/bin/ps
AWK=/usr/bin/awk
GREP=/bin/grep
if [ ! -x $GREP ]; then
	GREP=/usr/bin/grep
fi
SORT=/bin/sort
if [ ! -x $SORT ]; then
	SORT=/usr/bin/sort
fi

$PS axo comm,rss | $AWK '{arr[$1]+=$2} END {for (i in arr) {print i "=" arr[i]/1024}}' | $GREP -v '=0$'

RET=$?
exit $RET
