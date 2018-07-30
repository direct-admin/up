#!/bin/sh

#Installs Spam Assassin

#VERSION=2.64
#VERSION=3.2.5
VERSION=3.4.1

PERL=/usr/bin/perl

NAME=Mail-SpamAssassin-${VERSION}
FILE=${NAME}.tar.gz
WEBPATH=http://files.directadmin.com/services/custombuild
WEBPATH_BACKUP=http://files4.directadmin.com/services/custombuild
CWD=/usr/local/directadmin/scripts/packages

ARCHIVETAR_VER=1.48
ARCHIVETAR_NAME=Archive-Tar-${ARCHIVETAR_VER}

MAKEMAKER_VER=6.31
MAKEMAKER_NAME=ExtUtils-MakeMaker-${MAKEMAKER_VER}
DIGEST_VER=1.15
DIGEST_SHA1_VER=2.11
PARSER_VER=3.56
NETDNS_VER=0.60
NETDNS_NAME=Net-DNS-${NETDNS_VER}
NETIP_VER=1.25
NETIP_NAME=Net-IP-${NETIP_VER}
NETADDRIP_VER=4.027
NETADDRIP_NAME=NetAddr-IP-${NETADDRIP_VER}

ERROR_VER=0.17015
ERROR_NAME=Error-${ERROR_VER}

URI_VER=1.35
URI_NAME=URI-${URI_VER}

IOZLIB_VER=1.09
IOZLIB_NAME=IO-Zlib-${IOZLIB_VER}

NET_CIDR_LITE_VER=0.20
NET_CIDR_LITE_NAME=Net-CIDR-Lite-${NET_CIDR_LITE_VER}

DIGEST_NAME=Digest-${DIGEST_VER}
DIGEST_SHA1_NAME=Digest-SHA1-${DIGEST_SHA1_VER}
PARSER_NAME=HTML-Parser-${PARSER_VER}

STORABLE_VER=2.16
STORABLE_NAME=Storable-${STORABLE_VER}

DB_FILE_VER=1.815
DB_FILE_NAME=DB_File-${DB_FILE_VER}

#MAIL_SPF_QUERY_VER=1.998
#MAIL_SPF_QUERY_NAME=Mail-SPF-Query-${MAIL_SPF_QUERY_VER}
MAIL_SPF_VER=2.004
MAIL_SPF_NAME=Mail-SPF-${MAIL_SPF_VER}

SYS_HOSTNAME_VER=1.4
SYS_HOSTNAME_NAME=Sys-Hostname-Long-${SYS_HOSTNAME_VER}

NET_SSLeay_VER=1.30
NET_SSLeay_NAME=Net_SSLeay.pm-${NET_SSLeay_VER}

IO_SOCKET_VER=1.06
IO_SOCKET_NAME=IO-Socket-SSL-${IO_SOCKET_VER}

OS=`uname`

getFile() {
        if [ ! -e $1 ]
        then
                echo -e "Downloading\t\t$1...";
                if [ $OS = "FreeBSD" ]; then
                        fetch -o ${CWD}/${1} ${WEBPATH}/${1};
                else
                        wget -O ${CWD}/${1} ${WEBPATH}/${1};
                fi
                if [ ! -e $1 ]
                then
                        echo "Fileserver is down, using the backup file server..";
                        if [ $OS = "FreeBSD" ]; then
                                fetch ${WEBPATH_BACKUP}/${1};
                        else
                                wget ${WEBPATH_BACKUP}/${1} -O ${CWD}/${1};
                        fi
                fi

        else
                echo -e "File already exists:\t${1}";
        fi
}

ensureVersion() {

	PERL_VER=`$PERL -v | head -n2 | tail -n1 | cut -d\  -f4 | cut -dv -f2`
	NUM1=`echo $PERL_VER | cut -d. -f1`
	NUM2=`echo $PERL_VER | cut -d. -f2`
	NUM3=`echo $PERL_VER | cut -d. -f3`
	
	if [ $NUM1 -gt 5 ]; then
		return 1;
	fi
	if [ $NUM2 -gt 6 ]; then
		return 1;
	fi
	if [ $NUM3 -gt 0 ]; then
		return 1;
	fi

	echo "Your perl version is $PERL_VER. You require at least perl 5.6.1 for $NAME";
	exit 1;
}

downloadMake() {
	cd $CWD

	getFile ${1}.tar.gz
	tar xvzf ${1}.tar.gz
	cd ${1}
	$PERL Makefile.PL
	make
	make install

	cd $CWD
}

cd $CWD;

#Jan 17, 2011
#removed check because new perls have different version format.
#as well, no current box has an old perl version anyway
#ensureVersion;

export LANG=C

doLibs()
{
	downloadMake $IOZLIB_NAME
	downloadMake $ERROR_NAME
	#downloadMake $MAKEMAKER_NAME
	downloadMake $DIGEST_NAME
	downloadMake $DIGEST_SHA1_NAME
	downloadMake $PARSER_NAME
	downloadMake $STORABLE_NAME
	downloadMake $NETDNS_NAME
	downloadMake $NETIP_NAME
	downloadMake $NET_CIDR_LITE_NAME
	downloadMake $NETADDRIP_NAME
	downloadMake $DB_FILE_NAME
	#downloadMake $MAIL_SPF_QUERY_NAME
	downloadMake $MAIL_SPF_NAME
	downloadMake $SYS_HOSTNAME_NAME
	downloadMake $NET_SSLeay_NAME
	downloadMake $IO_SOCKET_NAME
	downloadMake $URI_NAME
	downloadMake $ARCHIVETAR_NAME
}

#if you run the commmand:
#cpan -i Archive::Tar Digest::SHA Mail::SPF IP::Country Net::Ident IO::Socket::INET6 Compress::Zlib Mail::DKIM LWP::UserAgent HTTP::Date Encode::Detect ExtUtils::MakeMaker
#you can remove the doLibs call and run cpan instead.

#doLibs;

getFile $FILE;

tar xzf ${FILE}
chown -R root $NAME

cd ${CWD}/${NAME}

#export LANG=C #moved higher
$PERL Makefile.PL PREFIX=/usr CONTACT_ADDRESS="the administrator of that system" RUN_NET_TESTS="no"
make
make install

if [ -e /usr/bin/sa-update ]; then
	/usr/bin/sa-update --nogpg
else
	echo "Cannot find /usr/bin/sa-update after install. Check for errors above.";
fi

## we need to change how it's started.
if [ -e /etc/init.d/exim ]; then
	$PERL -pi -e 's#/usr/bin/spamd -d -a -c -m 5#/usr/bin/spamd -d -c -m 5#' /etc/init.d/exim
fi
if [ -e /usr/local/etc/rc.d/exim ]; then
	$PERL -pi -e 's#/usr/bin/spamd -d -a -c -m 5#/usr/bin/spamd -d -c -m 5#' /usr/local/etc/rc.d/exim
fi

if [ ! -e /usr/bin/spamd ]; then
	echo "";
	echo "";
	echo "Cannot find /usr/bin/spamd.  Check above for errors or missing perl modules.";
	echo "If needed, use cpan to install the missing modules, eg:";
	echo "  cpan -i Archive::Tar Digest::SHA Mail::SPF IP::Country Net::Ident IO::Socket::INET6 Compress::Zlib Mail::DKIM LWP::UserAgent HTTP::Date Encode::Detect ExtUtils::MakeMaker NetAddr::IP Mail::SpamAssassin::Plugin::Razor2 Razor2::Client::Agent IO::Socket::SSL DBI";
	echo "";
	echo "Press enter to answer [yes] if it asks you to install dependencies (it will prepend them to the queue)";
	echo "Answer no if it asks: Are you ready for manual configuration? [yes] no";
	echo "";
else
	echo "";
	echo "";
	echo "run:";
	echo "  /usr/bin/spamd -d -c -m 15";
	echo "";
fi

exit 0;


