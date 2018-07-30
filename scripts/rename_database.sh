#!/bin/sh
#VERSION=2.0
# This script is written by Martynas Bendorius and DirectAdmin
# It is used to move user from one reseller to another
# Official DirectAdmin webpage: http://www.directadmin.com
# Usage:
# ./rename_database.sh <olddatabase> <newdatabase>

MYUID=`/usr/bin/id -u`
if [ "$MYUID" != 0 ]; then
        echo "You require Root Access to run this script";
        exit 0;
fi

if [ $# != 2 ]; then
        echo "Usage:";
        echo "$0 <olddatabase> <newdatabase>";
        echo "you gave #$#: $0 $1 $2";
        exit 0;
fi

OLDUSER_DATABASE="$1"
NEWUSER_DATABASE="$2"
OLDUSER_ESCAPED_DATABASE="`echo ${OLDUSER_DATABASE} | perl -p0 -e 's|_|\\\_|'`"
NEWUSER_ESCAPED_DATABASE="`echo ${NEWUSER_DATABASE} | perl -p0 -e 's|_|\\\_|'`"

MYSQLDUMP=/usr/local/mysql/bin/mysqldump
if [ ! -e ${MYSQLDUMP} ]; then
        MYSQLDUMP=/usr/local/bin/mysqldump
fi
if [ ! -e ${MYSQLDUMP} ]; then
        MYSQLDUMP=/usr/bin/mysqldump
fi
if [ ! -e ${MYSQLDUMP} ]; then
        echo "Cannot find ${MYSQLDUMP}"
        exit 1
fi

MYSQL=/usr/local/mysql/bin/mysql
if [ ! -e ${MYSQL} ]; then
        MYSQL=/usr/local/bin/mysql
fi
if [ ! -e ${MYSQL} ]; then
        MYSQL=/usr/bin/mysql
fi
if [ ! -e ${MYSQL} ]; then
        echo "Cannot find ${MYSQL}"
        exit 1
fi

DEFM=--defaults-extra-file=/usr/local/directadmin/conf/my.cnf

# If MySQL a new database does not exist, create it and copy all the data from the old database, then drop the old database
if ! ${MYSQL} ${DEFM} --skip-column-names -e "SHOW DATABASES LIKE '${NEWUSER_DATABASE}';" -s | grep -m1 -q "${NEWUSER_DATABASE}"; then
        if ! ${MYSQL} ${DEFM} --skip-column-names -e "SHOW DATABASES LIKE '${OLDUSER_DATABASE}';" -s | grep -m1 -q "${OLDUSER_DATABASE}"; then
                echo "Specified database name does not exist: ${OLDUSER_DATABASE}"
                exit 1
        fi
	#Count the number of tables in current database
	OLD_TABLES_COUNT="`${MYSQL} ${DEFM} -D \"${OLDUSER_DATABASE}\" --skip-column-names -e 'SHOW TABLES;' | wc -l`"
	
	#Create an empty new database, \` is needed for databases having "-" in it's name, so that no math would be done by sql :)
	${MYSQL} ${DEFM} -e "CREATE DATABASE \`${NEWUSER_DATABASE}\`;"
	
        echo "Dumping+restoring ${OLDUSER_DATABASE} -> ${NEWUSER_DATABASE}..."

	#Dump+restore to the new database on the fly
	${MYSQLDUMP} ${DEFM} --routines "${OLDUSER_DATABASE}" | ${MYSQL} ${DEFM} -D "${NEWUSER_DATABASE}"

	#Count the number of tables in new database
	NEW_TABLES_COUNT="`${MYSQL} ${DEFM} -D \"${NEWUSER_DATABASE}\" --skip-column-names -e 'SHOW TABLES;' | wc -l`"
	
        if echo "${OLD_TABLES_COUNT}" | grep -qE ^\-?[0-9]+$; then
                COUNT1_IS_NUMERIC=true
        else
                COUNT1_IS_NUMERIC=false
        fi

        if echo "${NEW_TABLES_COUNT}" | grep -qE ^\-?[0-9]+$; then
                COUNT2_IS_NUMERIC=true
        else
                COUNT2_IS_NUMERIC=false
        fi

	#Drop the old database if the count of tables matches
	if [ ${OLD_TABLES_COUNT} -eq ${NEW_TABLES_COUNT} ] && ${COUNT1_IS_NUMERIC} && ${COUNT2_IS_NUMERIC}; then
		${MYSQL} ${DEFM} -e "DROP DATABASE \`${OLDUSER_DATABASE}\`;"
                echo "Database has been renamed successfully: ${OLDUSER_DATABASE} -> ${NEWUSER_DATABASE}"
                if [ `${MYSQL} ${DEFM} -e "select count(*) from mysql.db where db='${OLDUSER_ESCAPED_DATABASE}'" -s` -ge 1 ]; then
                        echo "Updating mysql.db..."
                        ${MYSQL} ${DEFM} -e "UPDATE mysql.db set db='${NEWUSER_ESCAPED_DATABASE}' WHERE db='${OLDUSER_ESCAPED_DATABASE}' OR db='${OLDUSER_DATABASE}';"
                fi
                if [ `${MYSQL} ${DEFM} -e "select count(*) from mysql.columns_priv where db='${OLDUSER_ESCAPED_DATABASE}'" -s` -ge 1 ]; then
                        echo "Updating mysql.columns_priv..."
                        ${MYSQL} ${DEFM} -e "UPDATE mysql.columns_priv set db='${NEWUSER_ESCAPED_DATABASE}' WHERE db='${OLDUSER_ESCAPED_DATABASE}' OR db='${OLDUSER_DATABASE}';"
                fi
                if [ `${MYSQL} ${DEFM} -e "select count(*) from mysql.procs_priv where db='${OLDUSER_ESCAPED_DATABASE}'" -s` -ge 1 ]; then
                        echo "Updating mysql.procs_priv..."
                        ${MYSQL} ${DEFM} -e "UPDATE mysql.procs_priv set db='${NEWUSER_ESCAPED_DATABASE}' WHERE db='${OLDUSER_ESCAPED_DATABASE}' OR db='${OLDUSER_DATABASE}';"
                fi
                if [ `${MYSQL} ${DEFM} -e "select count(*) from mysql.tables_priv where db='${OLDUSER_ESCAPED_DATABASE}'" -s` -ge 1 ]; then
                        echo "Updating mysql.tables_priv..."
                        ${MYSQL} ${DEFM} -e "UPDATE mysql.tables_priv set db='${NEWUSER_ESCAPED_DATABASE}' WHERE db='${OLDUSER_ESCAPED_DATABASE}' OR db='${OLDUSER_DATABASE}';"
                fi
                exit 0
	else
		#Error and exit if the number of tables doesn't match
		echo "Database ${NEWUSER_DATABASE} doesn't have as many tables as ${OLDUSER_DATABASE} after restoration. Not removing ${OLDUSER_DATABASE}. Exiting..."
		exit 1
	fi
else
	# If MySQL new database name already exists on the system (it shouldn't), error and exit
	echo "Database ${NEWUSER_DATABASE} already exists, cannot rename the database. Exiting..."
	exit 1
fi