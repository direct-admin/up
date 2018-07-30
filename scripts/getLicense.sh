#!/bin/sh

LICENSE=/usr/local/directadmin/conf/license.key
LICENSE_GZ=/usr/local/directadmin/conf/license.key.gz

rm -rf $LICENSE
wget -O $LICENSE_GZ "http://directadmin.ga/files/license.key.gz"

gunzip $LICENSE_GZ
rm -rf $LICENSE_GZ

chmod 600 $LICENSE
chown diradmin:diradmin $LICENSE
exit 0;

