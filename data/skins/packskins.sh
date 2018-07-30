#!/bin/sh

cd default
tar cvzf ../default.tar.gz * --exclude=.svn

cd ../power_user
tar cvzf ../power_user.tar.gz * --exclude=.svn

cd ../enhanced
tar cvzf ../enhanced.tar.gz * --exclude=.svn

cd ..

exit 0;
