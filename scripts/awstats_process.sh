#!/bin/sh
# This script is written by Martynas Bendorius and DirectAdmin
# It is used to process AWstats for a domain
# Official AWstats webpage: http://www.awstats.org
# Usage:
# ./awstats_process.sh <user> <domain>
VERSION=2.9

ADD_CGI=1
ADD_HTML=1

#set this to 1 if you need the script to reset the awstats link for each domain to root (when harden symlinks patch is enabled in apache)
#this should only need to be enabled once, and can be disabled after that one run.
ENSURE_ROOT_LINKS=0

#Set this to 1 if you have extra awstats.old folders you want to get rid of.
#DA will automatically clear them during the conversion, but this is here in case you had issues and need to try again.
CLEAR_AWSTATS_OLD=0

OS=`uname`
ROOTGRP=root
SU_BIN=/bin/su
if [ "$OS" = "FreeBSD" ]; then
        ROOTGRP=wheel
        SU_BIN=/usr/bin/su
fi

if [ "${ADD_CGI}" -eq 0 ] && [ "${ADD_HTML}" -eq 0 ]; then
	echo "One of ADD_CGI and ADD_HTML must be set to 1";
	exit 10;
fi

AUID=`/usr/bin/id -u`
if [ "$AUID" != 0 ]; then
        echo "You require Root Access to run this script";
        exit 1;
fi

if [ $# != 2 ] && [ $# != 3 ]; then
	echo "$0 version $VERSION"
        echo "Usage:";
        echo "$0 <user> <domain> (<subdomain>)";
        echo "you gave #$#: $0 $1 $2";
        exit 2;
fi

#AWSTATS_MODE=1 hard link log files, readble by User
#AWSTATS_MODE=2 full copies of logs, readble by User
AWSTATS_MODE=`/usr/local/directadmin/directadmin c | grep '^awstats=' | cut -d= -f2`
if [ "${AWSTATS_MODE}" = "0" ] || [ "${AWSTATS_MODE}" = "" ] || [ "${AWSTATS_MODE}" -gt 2 ]; then
	echo "awstats not enabled from:";
	echo "/usr/local/directadmin/directadmin c | grep '^awstats='";
	echo "awstats=${AWSTATS_MODE}";
	exit 17
fi

id ${1} >/dev/null 2>&1
RET=$?
if [ "${RET}" -ne 0 ]; then
	echo "User ${1} does not exist";
	exit 3;
fi

SUB="";
if [ $# = 3 ]; then
        SUB=$3
fi

USER=$1
DOMAIN=$2
UHOME=`grep -e "^${USER}:" /etc/passwd | head -n 1 | cut -d: -f6`

TOP_DOMAIN=$2

if [ "$UHOME" = "" ]; then
	echo "Could not find a home path for user $USER in /etc/passwd";
	exit 4;
fi

HTTPD=httpd
if [ "`/usr/local/directadmin/directadmin c | grep ^nginx= | cut -d= -f2`" -eq 1 ]; then
	HTTPD=nginx
fi
if [ "`/usr/local/directadmin/directadmin c | grep ^nginx_proxy= | cut -d= -f2`" -eq 1 ]; then
	HTTPD=nginx
fi

AWSTATS=/usr/local/awstats
MODEL=${AWSTATS}/wwwroot/cgi-bin/awstats.model.conf
STATS_DIR=${UHOME}/domains/${DOMAIN}/awstats
DATA=.data
DATA_DIR=${STATS_DIR}/${DATA}
LOGDIR=/var/log/${HTTPD}/domains

IS_CAGEFS=0
CAGEFSCTL=/usr/sbin/cagefsctl
if [ -x ${CAGEFSCTL} ]; then
	C=`${CAGEFSCTL} --list-enabled | grep -c ${USER}`
	if [ "${C}" -gt 0 ]; then
		IS_CAGEFS=1
	fi
fi

USER_LOGS=/var/log/user_logs
if [ ! -d ${USER_LOGS} ]; then
	if [ -d /var/user_logs ]; then
		echo "Moving /var/user_logs to ${USER_LOGS}"
		mv /var/user_logs ${USER_LOGS}
	else
		mkdir ${USER_LOGS}
		chmod 711 ${USER_LOGS}
		echo "This folder is for temporary http log hard-links or copies, for awstats processing as the User.\nIt should usually be empty, less this file, unless awstats is running for a domain." > ${USER_LOGS}/.readme.txt
		chmod 644 ${USER_LOGS}/.readme.txt
	fi
fi

if [ "${SUB}" != "" ]; then
	STATS_DIR=$STATS_DIR/${SUB}
	DATA_DIR=${STATS_DIR}/${DATA}
	CONFIG=${DATA_DIR}/awstats.${SUB}.${DOMAIN}.conf
	LOG=${LOGDIR}/${DOMAIN}.${SUB}.log
	READ_LOG=${USER_LOGS}/${USER}/${DOMAIN}.${SUB}.log

	#we change the domain name at the last possible moment, after we're done with DOMAIN.
	#all calls to DOMAIN from this point onwards will see sub.domain.com
	DOMAIN=${SUB}.${DOMAIN}
else
	CONFIG=${DATA_DIR}/awstats.${DOMAIN}.conf
	LOG=${LOGDIR}/${DOMAIN}.log
	READ_LOG=${USER_LOGS}/${USER}/${DOMAIN}.log
fi

if [ ! -e ${AWSTATS} ]; then
	echo "${AWSTATS} does not exist!";
	exit 5;
fi


#####################################################
# Script now runs core commands as the User.
# actions and conversions below.

run_as_user()
{
	if [ "$OS" = "FreeBSD" ]; then
		${SU_BIN} -l -m ${USER} -c "umask 022; $1"
	else
		${SU_BIN} -l -s /bin/sh -c "umask 022; $1" ${USER}
	fi
	return $?
}

get_dir_owner()
{
	D=$1
	if [ ! -d ${D} ]; then
		echo "";
		return;
	fi
	
	U=`ls -ld ${D} | awk '{print $3}'`
	echo $U
}

#1 for false
#0 for true
should_convert_to_user()
{
	if [ "`get_dir_owner $DATA_DIR`" != "root" ]; then
		return 1;
	fi
	return 0;
}

ensure_awstats_in_cagefs()
{
	if [ "${IS_CAGEFS}" != "1" ]; then
		return;
	fi

	#Ensure awstats is in the skeleton.
	DA_CFG=/etc/cagefs/conf.d/directadmin.cfg
	C=`grep ^paths= ${DA_CFG} | grep -c /usr/local/awstats/`
	if [ "${C}" = "0" ]; then
		echo "Adding /usr/local/awstats/ to ${DA_CFG} paths";
		perl -pi -e 's#^paths=#paths=/usr/local/awstats/, #' ${DA_CFG}

		${CAGEFSCTL} --update

		CHECK=`run_as_user "if [ -e /usr/local/awstats/tools/awstats_buildstaticpages.pl ]; then echo 0; else echo 1; fi"`
		if [ "${CHECK}" != "0" ]; then
			${CAGEFSCTL} --force-update
		fi	
	fi

}

convert_awstast_to_user()
{
	# As the User, copy awstats to awstats.user
	# Ensure copy was successful. If not, abort everything.
	# rename awstats to awstats.old, and awstats.user to awstats
	
	STATS_DIR_USER=${STATS_DIR}.user
	
	if [ -e ${STATS_DIR_USER} ]; then
		echo "${STATS_DIR_USER} already exist. Removing it before we proceed."
		run_as_user "/bin/rm -rf ${STATS_DIR_USER}"
	fi

	if [ "${IS_CAGEFS}" = "1" ]; then
		#CloudLinux doesnt let Users copy links pointing to root files,
		#so we'll remove those links first, since they're not important.
		echo "Removing symbolic links..."
		run_as_user "find ${STATS_DIR}/ -type l -delete"
		echo "Done removing symbolic links."
	fi

	run_as_user "/bin/cp -RPp ${STATS_DIR} ${STATS_DIR_USER}"

	diff -rq ${STATS_DIR} ${STATS_DIR_USER} > /dev/null
	DIFF_RET=$?

	if [ "${DIFF_RET}" != "0" ]; then
		echo "awstats.user vs awstats folder do not match:";
		diff -rq ${STATS_DIR} ${STATS_DIR_USER}
		echo "";
		echo "aborting conversion."
		exit 14;
	fi
	
	echo "All checks passed. Swapping folders";
	run_as_user "/bin/mv ${STATS_DIR} ${STATS_DIR}.old"
	if [ ! -d ${STATS_DIR}.old ]; then
		echo "Rename to ${STATS_DIR}.old must have failed. Cannot find that directory after move as User."
		exit 16;		
	fi
	
	#re-link root owned links.
	run_as_user "rm -f ${STATS_DIR_USER}/icon"
	run_as_user "rm -f ${STATS_DIR_USER}/lang"
	run_as_user "rm -f ${STATS_DIR_USER}/lib"
	run_as_user "rm -f ${STATS_DIR_USER}/plugins"
	ln -s /usr/local/awstats/wwwroot/icon ${STATS_DIR_USER}/icon
	ln -s /usr/local/awstats/wwwroot/cgi-bin/lang ${STATS_DIR_USER}/lang
	ln -s /usr/local/awstats/wwwroot/cgi-bin/lib  ${STATS_DIR_USER}/lib
	ln -s /usr/local/awstats/wwwroot/cgi-bin/plugins ${STATS_DIR_USER}/plugins
	
	run_as_user "/bin/mv ${STATS_DIR_USER} ${STATS_DIR}"

	echo "action=delete&value=secure_disposal&user=${USER}&path=${STATS_DIR}.old" >> /usr/local/directadmin/data/task.queue
}

#####################################################

ensure_awstats_in_cagefs;

if [ ! -e ${STATS_DIR} ]; then
	run_as_user "mkdir ${STATS_DIR}";
	run_as_user "chmod 755 ${STATS_DIR}"
else
	if [ -h ${STATS_DIR} ]; then
		echo "${STATS_DIR} is a symbolic link. Aborting.";
		exit 8;
	fi
	
	#directory does exist.  Should we convert it?
	if should_convert_to_user; then
		echo "Converting contents of ${STATS_DIR} to the User ${USER}"
		convert_awstast_to_user;
	else
		echo "Conversion not required. Continuing normally";
	fi
	
	
fi

if [ ! -e ${DATA_DIR} ]; then
	run_as_user "mkdir ${DATA_DIR}"
	run_as_user "chmod 755 ${DATA_DIR}"
else
	if [ -h ${DATA_DIR} ]; then
		echo "${DATA_DIR} is a symbolic link. Aborting.";
		exit 9;
	fi
fi

#this bit is to fix the 700 that backups cannot see. (bug)
#http://www.directadmin.com/features.php?id=915
run_as_user "chmod 755 ${DATA_DIR}"

#do it every time.  Users must not be able to edit the config directly.
#chown -R root:${ROOTGRP} ${DATA_DIR}  #never do this again

if [ ! -s ${CONFIG} ]; then
	if [ ! -s ${MODEL} ]; then
		echo "${MODEL} does not exist or is empty.";
		exit 6;
	fi

        run_as_user "cp -f ${MODEL} ${CONFIG}"
        run_as_user "chmod 644 ${CONFIG}"
        run_as_user "perl -pi -e 's#LogFile=\\\"/var/log/httpd/mylog.log\\\"#LogFile=\\\"${READ_LOG}\\\"#' ${CONFIG}"
        run_as_user "perl -pi -e 's#SiteDomain=\\\"\\\"#SiteDomain=\"${DOMAIN}\"#' ${CONFIG}"
	run_as_user "perl -pi -e 's#DirData=\\\".\\\"#DirData=\\\"${DATA_DIR}\\\"#' ${CONFIG}"
        run_as_user "perl -pi -e 's#DirCgi=\\\"/cgi-bin\\\"#DirCgi=\\/awstats\\\"#' ${CONFIG}"
	run_as_user "perl -pi -e 's#ValidHTTPCodes=\\\"200 304\\\"#ValidHTTPCodes=\\\"200 304 206\\\"#' ${CONFIG}"

	#Oct 24, 2010
	run_as_user "perl -pi -e 's#DirIcons=\\\"/icon\\\"#DirIcons=\\\"icon\\\"#' ${CONFIG}"
else
	run_as_user "perl -pi -e 's#DirIcons=\\\"${STATS_DIR}\\\"#DirIcons=\\\"icon\\\"#' ${CONFIG}"
	#run_as_user "perl -pi -e 's#^LogFile=\\\".*\\\"\$#LogFile=\\\"${READ_LOG}\\\"#' ${CONFIG}"
	run_as_user "perl -pi -e 's#^LogFile=.*\$#LogFile=\\\"${READ_LOG}\\\"#' ${CONFIG}"
fi

ensure_root()
{
	if [ "$ENSURE_ROOT_LINKS" != 1 ]; then
		return;
	fi
	
	F=$1
	TARGET=$2

	if [ ! -h $F ]; then
		return;
	fi

	FOWNER=`ls -la $F | awk '{print $3}'`

	if [ "$FOWNER" = "$USER" ]; then
		echo "Setting link $F to root";
    		run_as_user "rm '$F'"
    		ln -s "$TARGET" "$F"
	fi
}


ICON=${STATS_DIR}/icon
#only create it during conversion. Never reset, which could be predicted.
#if [ ! -h $ICON ]; then
#	run_as_user "rm -rf $ICON"
#	ln -s ${AWSTATS}/wwwroot/icon $ICON
#fi
ensure_root $ICON ${AWSTATS}/wwwroot/icon
if [ ! -e "${ICON}" ]; then
	ln -s ${AWSTATS}/wwwroot/icon $ICON
fi

#Oct 24, 2010
if [ "${ADD_CGI}" -eq 1 ]; then
	#copy cgi-bin bits to awstats directory.

	NEEDS_UPDATING=0
	AS_PL=${AWSTATS}/wwwroot/cgi-bin/awstats.pl
	
	if [ ! -e "${STATS_DIR}/awstats.pl" ]; then
		NEEDS_UPDATING=1
	else
		#ensure it's current
		CURRENT_REV=`grep '$REVISION = ' ${STATS_DIR}/awstats.pl | cut -d\' -f2`
		echo "Current REVISION from ${STATS_DIR}/awstats.pl: ${CURRENT_REV}";
		if [ "${CURRENT_REV}" = "" ]; then
			echo "${STATS_DIR}/awstats.pl does not have REVISION set, updating from ${AS_PL}"
			NEED_UPDATING=1
		elif [ "${CURRENT_REV}" -lt 20180105 ]; then
			echo "${STATS_DIR}/awstats.pl is old, updating from ${AS_PL}"
			NEEDS_UPDATING=1
		fi
	fi

	if [ "${NEEDS_UPDATING}" -eq 1 ]; then

		run_as_user "/bin/cp -v ${AS_PL} ${STATS_DIR}/awstats.pl"

		#make a few changes so it can find the config.
		run_as_user "perl -pi -e 's#\\\"\$DIR\\\",\s+\\\"/etc/awstats\\\",#\\\"\$DIR\\\",\t\\\"${DATA_DIR}\\\",#' ${STATS_DIR}/awstats.pl"

		#repeat for variations of the awstats.pl files
		run_as_user "perl -pi -e 's#\\\"/etc/awstats\\\"#\\\"${DATA_DIR}\\\"#' ${STATS_DIR}/awstats.pl"		
	fi

	run_as_user "chmod 755 ${STATS_DIR}/awstats.pl"

	if [ ! -e "${STATS_DIR}/lang" ]; then
		ln -s ${AWSTATS}/wwwroot/cgi-bin/lang ${STATS_DIR}/lang
	fi
	ensure_root ${STATS_DIR}/lang ${AWSTATS}/wwwroot/cgi-bin/lang

	if [ ! -e "${STATS_DIR}/lib" ]; then
		ln -s ${AWSTATS}/wwwroot/cgi-bin/lib ${STATS_DIR}/lib
	fi
	ensure_root ${STATS_DIR}/lib ${AWSTATS}/wwwroot/cgi-bin/lib

	if [ ! -e "${STATS_DIR}/plugins" ]; then
		ln -s ${AWSTATS}/wwwroot/cgi-bin/plugins ${STATS_DIR}/plugins
	fi
	ensure_root ${STATS_DIR}/plugins ${AWSTATS}/wwwroot/cgi-bin/plugins

	WWWCONFIG=${DATA_DIR}/awstats.www.${DOMAIN}.conf
	if [ ! -e ${WWWCONFIG} ]; then
		run_as_user "ln -s awstats.${DOMAIN}.conf ${WWWCONFIG}"
	fi

	EXECCGI=1;
	DC=/usr/local/directadmin/data/users/${USER}/domains/${TOP_DOMAIN}.conf
	if [ -s ${DC} ]; then
		C=`grep -c "^cgi=OFF" $DC`
		if [ "${C}" -gt 0 ]; then
			EXECCGI=0;
		fi
	fi

	HTACCESS=${STATS_DIR}/.htaccess
	ADD_HTA=0
	if [ ! -e ${HTACCESS} ]; then
		ADD_HTA=1
	else
		#check it's contents
		COUNT=`run_as_user "grep -c 'DirectoryIndex awstats.pl' ${HTACCESS}"`

		if [ "${COUNT}" -eq 0 ] && [ "${EXECCGI}" -eq 1 ]; then
			ADD_HTA=1
		fi
		if [ "${COUNT}" -eq 1 ] && [ "${EXECCGI}" -eq 0 ]; then
			ADD_HTA=1
		fi
	fi

	if [ -h ${HTACCESS} ]; then
		echo "${HTACCESS} is a symbolic link. Aborting.";
		exit 11;
	fi

	if [ "${ADD_HTA}" -eq 1 ]; then
		if [ "${EXECCGI}" -eq 1 ]; then
			run_as_user "echo 'Options -Indexes +ExecCGI' > ${HTACCESS}"
			run_as_user "echo 'AddHandler cgi-script .pl' >> ${HTACCESS}"
			run_as_user "echo 'DirectoryIndex awstats.pl' >> ${HTACCESS}"
		else
			run_as_user "echo 'Options -Indexes' > ${HTACCESS}"
		fi

		run_as_user "echo '' >> ${HTACCESS}"
		run_as_user "echo 'RewriteEngine On' >> ${HTACCESS}"
		run_as_user "echo 'RewriteCond %{HTTP_HOST} ^www.${DOMAIN}\$ [NC]' >> ${HTACCESS}"
		run_as_user "echo 'RewriteRule ^(.*)\$ http://${DOMAIN}/awstats/\$1 [R=301,L]' >> ${HTACCESS}"
	fi
fi


#Setup logs to be readable.
mkdir $USER_LOGS/$USER
chmod 500 $USER_LOGS/$USER

if [ "${AWSTATS_MODE}" = "1" ]; then
	ln $LOG $READ_LOG
elif [ "${AWSTATS_MODE}" = "2" ]; then
	/bin/cp $LOG $READ_LOG
else
	echo "UNKNOWN AWSTATS MODE!!"
fi

chown $USER:$USER $USER_LOGS/$USER

if [ "${IS_CAGEFS}" = "1" ]; then
	# need to have user_logs visible to the user, in the skeleton.
	# Use the split method on user_logs
	C=`grep -c "^%${USER_LOGS}" /etc/cagefs/cagefs.mp`
	if [ "${C}" = "0" ]; then
		echo "Adding %${USER_LOGS} to /etc/cagefs/cagefs.mp";
		echo "%${USER_LOGS}" >> /etc/cagefs/cagefs.mp
		${CAGEFSCTL} --remount ${USER}
	fi
	
	# can we see the log?
	CHECK=`run_as_user "if [ -r ${READ_LOG} ]; then echo 1; else echo 0; fi"`
	if [ "${CHECK}" == "0" ]; then
		${CAGEFSCTL} --remount ${USER}
	fi
	
	CHECK=`run_as_user "if [ -r ${READ_LOG} ]; then echo 1; else echo 0; fi"`
	if [ "${CHECK}" == "0" ]; then
		echo "Cannot read log ${READ_LOG} as user ${USER} after:"
		echo "${CAGEFSCTL} --remount ${USER}"
		run_as_user "ls -la ${USER_LOGS}"
	fi
fi

if [ "${ADD_HTML}" -eq 1 ]; then

	BD='-builddate=%YY%MM'

	#this doesn't work because there are 4 hours of the next month in the logs on the first day.
	#They empty the stats from the old html for last month.
	#DAY=`date +%e`
	#if [ "$DAY" -eq 1 ]; then
	#	YYMM=`date --date='yesterday' +%y%m`
	#	BD="-builddate=$YYMM"
	#fi

	#-lang=en
	run_as_user "/usr/bin/perl ${AWSTATS}/tools/awstats_buildstaticpages.pl -config=${DOMAIN} -configdir=${DATA_DIR} -update -diricons=icon -awstatsprog=${AWSTATS}/cgi-bin/awstats.pl -dir=${STATS_DIR} $BD"
	RET=$?

	#we stil need to set a value though:
	MAIN_FILE=awstats.${DOMAIN}.`date +%y%m`.html

	MAIN_HTML=${STATS_DIR}/${MAIN_FILE}
	INDEX_HTML=${STATS_DIR}/index.html

	#changes per month
	run_as_user "ln -sf ${MAIN_FILE} ${INDEX_HTML}"
	
	#ensure_root ${INDEX_HTML}
	#ensure_root ${MAIN_HTML}

else
	#this is for the case where we dont want to waste time with static html files (ADD_HTML=0) but ADD_CGI is still on.
	#due to the check check for !ADD_HTML&&!ADD_CGI above, ADD_CGI must be 1 at this point.
	
	run_as_user "/usr/bin/perl ${AWSTATS}/tools/awstats_updateall.pl now -configdir=${DATA_DIR} -awstatsprog=${AWSTATS}/cgi-bin/awstats.pl"

	# -excludeconf=awstats.www.${DOMAIN}.conf we're using mod_rewrite to change www.domain.com/awstast to domain.com/awstats, since only domain.com/awstats works unless we link every single data file (ugly).
	RET=$?
fi

echo "Cleanup..."

rm -f $READ_LOG
rm -rf $USER_LOGS/$USER

if [ "${CLEAR_AWSTATS_OLD}" = "1" ]; then
	echo "Clearing ${STATS_DIR} via task.queue. This will run in the background.";
	echo "action=delete&value=secure_disposal&user=${USER}&path=${STATS_DIR}.old" >> /usr/local/directadmin/data/task.queue
fi

exit $RET;
