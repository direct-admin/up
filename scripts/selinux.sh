#!/bin/sh

setenforce 0
if [ -e /etc/selinux/config ]; then
        perl -pi -e 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
        perl -pi -e 's/SELINUX=permissive/SELINUX=disabled/' /etc/selinux/config
fi
if [ -e /selinux/enforce ]; then
        echo "0" > /selinux/enforce
fi

if [ -e /usr/sbin/setenforce ]; then
	/usr/sbin/setenforce 0
fi
