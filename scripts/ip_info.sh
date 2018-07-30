#!/bin/sh

DIG=/usr/bin/dig
WHOIS=/usr/bin/whois

if [ $# -ne 1 ]; then
	echo "Usage:";
	echo "  $0 ip";
	exit 1;
fi

if [ ! -x "$DIG" ]; then
	echo "Cannot find $DIG or it's not executable.";
	exit 2;
else
	$DIG -x "$1" +noshort 2>&1
fi

if [ -x "$WHOIS" ]; then
	$WHOIS "$1" 2>&1
fi

exit 0;
