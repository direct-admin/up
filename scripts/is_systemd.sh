#!/bin/sh
SYSTEMDDIR=/etc/systemd/system
if [ -d ${SYSTEMDDIR} ] && [ -e /usr/bin/systemctl ]; then
	echo "yes";
	exit 0;
fi
echo "no";
exit 1;
