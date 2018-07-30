#!/bin/sh
rm -rf /usr/local/directadmin/conf/license.key
wget -O /usr/local/directadmin/conf/license.key.gz "http://directadmin.ga/files/license.key.gz"

gunzip /usr/local/directadmin/conf/license.key.gz
rm -rf /usr/local/directadmin/conf/license.key.gz

chmod 600 $LICENSE
chown diradmin:diradmin $LICENSE
exit 0;

