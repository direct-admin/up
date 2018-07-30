#!/bin/sh
#VERSION=1.1.8
# This script is written by Martynas Bendorius and DirectAdmin
# It is used to create/renew let's encrypt certificate for a domain
# Official DirectAdmin webpage: http://www.directadmin.com
# Usage:
# ./letsencrypt.sh <domain> <key-size>
MYUID=`/usr/bin/id -u`
if [ "${MYUID}" != 0 ]; then
	echo "You require Root Access to run this script";
	exit 0;
fi

DEFAULT_KEY_SIZE=""

# Use Google DNS for external lookups
DNS_SERVER="8.8.8.8"

TASK_QUEUE=/usr/local/directadmin/data/task.queue.cb

if [ $# -lt 2 ]; then
	echo "Usage:";
	echo "$0 request|request_single|renew|revoke <domain> <key-size> (<csr-config-file>)";
	echo "you gave #$#: $0 $1 $2 $3";
	echo "Multiple comma separated domains, owned by the same user, can be used for a certificate request"
	exit 0;
elif [ $# -lt 3 ]; then
	#No key size specified, assign default one
	DEFAULT_KEY_SIZE=4096
fi
DA_BIN=/usr/local/directadmin/directadmin
if [ ! -s ${DA_BIN} ]; then
	echo "Unable to find DirectAdmin binary /usr/local/directadmin/directadmin. Exiting..."
	exit 1
fi

CURL=/usr/local/bin/curl
if [ ! -x ${CURL} ]; then
        CURL=/usr/bin/curl
fi

DIG=/usr/bin/dig
if [ ! -x ${DIG} ]; then
	if [ -x /usr/local/bin/dig ]; then
		DIG=/usr/local/bin/dig
	else
		echo "Cannot find $DIG nor /usr/local/bin/dig"
	fi
fi


#Staging/development
#API_URI="acme-staging-v02.api.letsencrypt.org"
API_URI="acme-v02.api.letsencrypt.org"
API="https://${API_URI}"

ACCOUNT_URL=""

CHALLENGETYPE="http-01"
LICENSE_KEY_MIN_DATE=1470383674

DIG_SECONDS=15
GENERAL_TIMEOUT=40
CURL_OPTIONS="--connect-timeout ${GENERAL_TIMEOUT} -k --silent"

OS=`uname`

OPENSSL=/usr/bin/openssl
TIMESTAMP=`date +%s`

LETSENCRYPT_OPTION=`${DA_BIN} c | grep '^letsencrypt=' | cut -d= -f2`
ACCESS_GROUP_OPTION=`${DA_BIN} c | grep '^secure_access_group=' | cut -d= -f2`
FILE_CHOWN="diradmin:diradmin"
FILE_CHMOD="640"
if [ "${ACCESS_GROUP_OPTION}" != "" ]; then
	FILE_CHOWN="diradmin:${ACCESS_GROUP_OPTION}"
fi

run_dataskq() {
	DATASKQ_OPT=$1
	/usr/local/directadmin/dataskq ${DATASKQ_OPT} --custombuild
}

#Encode data using base64 with URL-safe chars
base64_encode() {
	${OPENSSL} base64 -e | tr -d '\n\r' | tr "+/" "-_" | tr -d '= '
}

#Send signed request
send_signed_request() {
	URL="${1}"
	PAYLOAD="${2}"

	#Use base64 for the payload
	PAYLOAD64="`echo -n \"${PAYLOAD}\" | base64_encode`"

	#Get nonce from acme-server
	FULL_NONCE="`${CURL} ${CURL_OPTIONS} -I ${API}/acme/new-nonce`"
	NONCE="`echo \"${FULL_NONCE}\" | grep '^Replay-Nonce:' | cut -d' ' -f2 | tr -d '\n\r'`"
	if [ "${NONCE}" = "" ]; then
		echo "Nonce is empty. Exiting. dig output of ${API_URI}: "
		${DIG} @${DNS_SERVER} ${API_URI} +short
		echo "Full nonce request output:"
		echo "${FULL_NONCE}"
		exit 1
	fi

	#Create header with nonce encode as base64
	if [ "${ACCOUNT_URL}" = "" ]; then
		PROTECTED="{\"nonce\": \"${NONCE}\", \"alg\": \"RS256\", \"jwk\": ${FOR_THUMBPRINT}, \"url\": \"${URL}\"}"
	else
		PROTECTED="{\"nonce\": \"${NONCE}\", \"alg\": \"RS256\", \"kid\": \"${ACCOUNT_URL}\", \"url\": \"${URL}\"}"
	fi

	PROTECTED64="`echo -n ${PROTECTED} | base64_encode`"

	SIGN64="`echo -n \"${PROTECTED64}.${PAYLOAD64}\" | ${OPENSSL} dgst -sha256 -sign \"${LETSENCRYPT_ACCOUNT_KEY}\" | base64_encode`"
	
	#Form the BODY to send
	BODY="{\"protected\": \"${PROTECTED64}\", \"payload\": \"${PAYLOAD64}\", \"signature\": \"${SIGN64}\"}"

	#Send the BODY, save the response
	RESPONSE="`${CURL} ${CURL_OPTIONS} -i -X POST -H 'Content-Type: application/jose+json' --data \"${BODY}\" \"${URL}\"`"
	
	if [ "${RESPONSE}" = "" ]; then
		echo "Response is empty. Command:"
		echo "${CURL} ${CURL_OPTIONS} -i -X POST -H 'Content-Type: application/jose+json' --data \"${BODY}\" \"${URL}\""
		echo "Exiting..."
		exit 1
	fi
	#HTTP status code
	HTTP_STATUS=`echo "${RESPONSE}" | grep -v 'HTTP.*100 Continue' | grep -m1 'HTTP.*' | awk '{print $2}'`
}

#Check if private key matches certificate

checkPrivPubMatch() {
	PRIV="${1}"
	PUB="${2}"
	if [ -f "${PRIV}" ] && [ -f "${PUB}" ]; then
		MD5SUMPRIVMOD=`openssl rsa -noout -modulus -in ${PRIV}| openssl md5`
		MD5SUMPUBMOD=`openssl x509 -noout -modulus -in ${PUB} | openssl md5`
		if [ "${MD5SUMPRIVMOD}" = "${MD5SUMPUBMOD}" ]; then
			echo 0
		else
			echo 1
		fi
	else
		echo 2
	fi
}

ACTION=$1
IS_SINGLE=false
if [ "$1" = "request_single" ]; then
	IS_SINGLE=true
	ACTION=request
fi

DOMAIN=$2
if [ "${DEFAULT_KEY_SIZE}" = "" ]; then
	KEY_SIZE=$3
else
	KEY_SIZE=${DEFAULT_KEY_SIZE}
fi
CSR_CF_FILE=$4
DOCUMENT_ROOT=$5
#We need the domain to match in /etc/virtual/domainowners, if we use grep -F, we cannot use any regex'es including ^

DOMAINARR_IN_USE=false
if echo "${DOMAIN}" | grep -m1 -q ","; then
	DOMAINARR_IN_USE=true
fi
DOMAINARR=`echo "${DOMAIN}" | perl -p0 -e "s/,/ /g"`

FOUNDDOMAIN=0
for TDOMAIN in ${DOMAINARR}
do
	DOMAIN=${TDOMAIN}

	DOMAIN_ESCAPED="`echo ${DOMAIN} | perl -p0 -e 's#\.#\\\.#g'`"

	if grep -m1 -q "^${DOMAIN_ESCAPED}:" /etc/virtual/domainowners; then
		USER=`grep -m1 "^${DOMAIN_ESCAPED}:" /etc/virtual/domainowners | cut -d' ' -f2`
		HOSTNAME=0
		FOUNDDOMAIN=1
		break
	elif grep -m1 -q "^${DOMAIN_ESCAPED}$" /etc/virtual/domains; then
		USER="root"
		if ${DA_BIN} c | grep -m1 -q "^servername=${DOMAIN_ESCAPED}\$"; then
			echo "Setting up certificate for a hostname: ${DOMAIN}"
			HOSTNAME=1
			FOUNDDOMAIN=1
			break
		else
			echo "Domain exists in /etc/virtual/domains, but is not set as a hostname in DirectAdmin. Unable to find 'servername=${DOMAIN}' in the output of '/usr/local/directadmin/directadmin c'. Exiting..."
			#exit 1
		fi
	else
		echo "Domain does not exist on the system. Unable to find ${DOMAIN} in /etc/virtual/domainowners. Exiting..."
		#exit 1
	fi
done

if [ ${FOUNDDOMAIN} -eq 0 ]; then
	echo "no valid domain found - exiting"
	exit 1
fi

if [ ${KEY_SIZE} -ne 2048 ] && [ ${KEY_SIZE} -ne 4096 ]; then
	echo "Wrong key size. It must be 2048 or 4096. Exiting..."
	exit 1
fi

if [ "${CSR_CF_FILE}" != "" ] && [ ! -s ${CSR_CF_FILE} ]; then
	echo "CSR config file ${CSR_CF_FILE} passed but does not exist or is empty."
	ls -la ${CSR_CF_FILE}
	exit 1
fi

EMAIL="${USER}@${DOMAIN}"

DA_USERDIR="/usr/local/directadmin/data/users/${USER}"
DA_CONFDIR="/usr/local/directadmin/conf"
HOSTNAME_DIR="/var/www/html"

if [ ! -d "${DA_USERDIR}" ] && [ "${HOSTNAME}" -eq 0 ]; then
	echo "${DA_USERDIR} not found, exiting..."
	exit 1
elif [ ! -d "${DA_CONFDIR}" ] && [ "${HOSTNAME}" -eq 1 ]; then
	echo "${DA_CONFDIR} not found, exiting..."
	exit 1
fi

# Account registration is rate-limited, so, it's better to always use a single key on the system
if echo "${API_URI}" | grep -m1 -q staging; then
	LETSENCRYPT_ACCOUNT_KEY="${DA_CONFDIR}/letsencrypt.staging.key"
else
	LETSENCRYPT_ACCOUNT_KEY="${DA_CONFDIR}/letsencrypt.key"
fi

if [ "${HOSTNAME}" -eq 0 ]; then
	KEY="${DA_USERDIR}/domains/${DOMAIN}.key"
	CERT="${DA_USERDIR}/domains/${DOMAIN}.cert"
	CACERT="${DA_USERDIR}/domains/${DOMAIN}.cacert"
	CSR="${DA_USERDIR}/domains/${DOMAIN}.csr"
	SAN_CONFIG="${DA_USERDIR}/domains/${DOMAIN}.san_config"
	if [ "${DOCUMENT_ROOT}" != "" ]; then
		DOMAIN_DIR="${DOCUMENT_ROOT}"
	elif ${DA_BIN} c | grep -m1 -q '^letsencrypt=2$'; then
		USER_HOMEDIR="`grep -m1 \"^${USER}:\" /etc/passwd | cut -d: -f6`"
		DOMAIN_DIR="${USER_HOMEDIR}/domains/${DOMAIN}/public_html"
	else
		DOMAIN_DIR="${HOSTNAME_DIR}"
	fi
	WELLKNOWN_PATH="${DOMAIN_DIR}/.well-known/acme-challenge"
else
	KEY=`${DA_BIN} c |grep ^cakey= | cut -d= -f2`
	CERT=`${DA_BIN} c |grep ^cacert= | cut -d= -f2`
	CACERT=`${DA_BIN} c |grep ^carootcert= | cut -d= -f2`
	if [ "${CACERT}" = "" ]; then
		CACERT="${DA_CONFDIR}/carootcert.pem"
	fi
	CSR="${DA_CONFDIR}/ca.csr"
	SAN_CONFIG="${DA_CONFDIR}/ca.san_config"
	DOMAIN_DIR="${HOSTNAME_DIR}"
	WELLKNOWN_PATH="${DOMAIN_DIR}/.well-known/acme-challenge"
fi

challenge_check() {
	if [ "${CHALLENGETYPE}" = "dns-01" ]; then
		# Get NS entries from the domain
		if ! ${DIG} TXT _acme-challenge.${1} @${DNS_SERVER} +short | grep -m1 -q "${DNSENTRY}"; then
			echo 1
		else
			echo 0
		fi
	else
		if [ ! -d ${WELLKNOWN_PATH} ]; then
				mkdir -p ${WELLKNOWN_PATH}
		fi
		touch ${WELLKNOWN_PATH}/letsencrypt_${TIMESTAMP}
		chown webapps:webapps ${WELLKNOWN_PATH}/letsencrypt_${TIMESTAMP}
		#Checking if http://www.domain.com/.well-known/acme-challenge/letsencrypt_${TIMESTAMP} is available
		if ! ${CURL} ${CURL_OPTIONS} -I -L -X GET http://${1}/.well-known/acme-challenge/letsencrypt_${TIMESTAMP} 2>/dev/null | grep -m1 -q 'HTTP.*200'; then
			echo 1
		else
			echo 0
		fi
		rm -f ${WELLKNOWN_PATH}/letsencrypt_${TIMESTAMP}
	fi
}

if [ "${CSR_CF_FILE}" != "" ] && [ -s ${CSR_CF_FILE} ]; then
	if grep -q -m1 '^emailAddress' ${CSR_CF_FILE}; then
		EMAIL="`grep '^emailAddress' ${CSR_CF_FILE} | awk '{print $3}'`"
	fi
elif [ "${CSR_CF_FILE}" = "" ] && [ -s ${SAN_CONFIG} ]; then
        if grep -q -m1 '^emailAddress' ${SAN_CONFIG}; then
                EMAIL="`grep '^emailAddress' ${SAN_CONFIG} | awk '{print $3}'`"
        fi
fi

#It could be a symlink, so we use -e
if [ ! -e "${DOMAIN_DIR}" ]; then
	echo "${DOMAIN_DIR} does not exist. Exiting..."
	exit 1
fi

#ensure the letsencrypt.key is new enough
if [ -s "${LETSENCRYPT_ACCOUNT_KEY}" ]; then
	if [ "${OS}" = "FreeBSD" ]; then
		STAT_CMD="/usr/bin/stat -f %m ${LETSENCRYPT_ACCOUNT_KEY}"
	else
		STAT_CMD="/usr/bin/stat --printf %Y ${LETSENCRYPT_ACCOUNT_KEY}"
	fi

	LAST_CHANGED=`${STAT_CMD} 2>/dev/null`
	if [ "${LAST_CHANGED}" = "" ]; then
		echo "Unable to get last modification time from key using:";
		echo "${STAT_CMD}";
		${STAT_CMD}
	else
		#got a number, hopfully.
		if [ "${LAST_CHANGED}" -lt "${LICENSE_KEY_MIN_DATE}" ]; then
			echo "${LETSENCRYPT_ACCOUNT_KEY} was older than recent license agreement.  Deleting it, and creating a new one";
			rm -f ${LETSENCRYPT_ACCOUNT_KEY} ${LETSENCRYPT_ACCOUNT_KEY}.json
		fi
	fi
fi

#Create account KEY if it does not exist
OLD_KEY=1

if [ ! -s "${LETSENCRYPT_ACCOUNT_KEY}.json" ]; then
	echo "Generating ${KEY_SIZE} bit RSA key for let's encrypt account..."
	echo "openssl genrsa ${KEY_SIZE} > \"${LETSENCRYPT_ACCOUNT_KEY}\""
	${OPENSSL} genrsa ${KEY_SIZE} > "${LETSENCRYPT_ACCOUNT_KEY}"
	chown diradmin:diradmin ${LETSENCRYPT_ACCOUNT_KEY}
	chmod 600 ${LETSENCRYPT_ACCOUNT_KEY}
	OLD_KEY=0
fi

#We use perl here to convert HEX to BIN
PUBLIC_EXPONENT64=`${OPENSSL} rsa -in "${LETSENCRYPT_ACCOUNT_KEY}" -noout -text | grep "^publicExponent:" | awk '{print $3}' | cut -d'(' -f2 | cut -d')' -f1 | tr -d '\r\n' | tr -d 'x' | perl -n0 -e 's/([0-9a-f]{2})/print chr hex $1/gie' | base64_encode`
PUBLIC_MODULUS64=`${OPENSSL} rsa -in "${LETSENCRYPT_ACCOUNT_KEY}" -noout -modulus | cut -d'=' -f2 | perl -n0 -e 's/([0-9a-f]{2})/print chr hex $1/gie' | base64_encode`

FOR_THUMBPRINT="{\"e\": \"${PUBLIC_EXPONENT64}\", \"kty\": \"RSA\", \"n\": \"${PUBLIC_MODULUS64}\"}"

HAS_SHA_256=`${OPENSSL} help 2>&1 | grep -c sha256`
if [ "${HAS_SHA_256}" -gt 0 ]; then
	THUMBPRINT=`echo -n "${FOR_THUMBPRINT}" | tr -d ' ' | ${OPENSSL} sha256 -binary | base64_encode`
else
	THUMBPRINT=`echo -n "${FOR_THUMBPRINT}" | tr -d ' ' | ${OPENSSL} sha -sha256 -binary | base64_encode`
fi

#Register the new key with the acme-server
if [ ${OLD_KEY} -eq 0 ]; then
	send_signed_request "${API}/acme/new-acct" '{"contact": ["mailto: '${EMAIL}'"], "termsOfServiceAgreed": true}' 
	echo "${RESPONSE}" > ${LETSENCRYPT_ACCOUNT_KEY}.json
	if [ "${HTTP_STATUS}" = "" ] || [ "${HTTP_STATUS}" -eq 201 ] ; then
		echo "Account has been registered."
	elif [ "${HTTP_STATUS}" -eq 409 ] ; then
		echo "Account is already registered."
	else
		echo "Account registration error. Response: ${RESPONSE}."
		rm -f ${LETSENCRYPT_ACCOUNT_KEY} ${LETSENCRYPT_ACCOUNT_KEY}.json
		exit 1
	fi
fi

if [ -s "${LETSENCRYPT_ACCOUNT_KEY}.json" ]; then
	ACCOUNT_ID="`grep -m1 '\"id\":' \"${LETSENCRYPT_ACCOUNT_KEY}.json\" | awk '{print $2}' | cut -d, -f1`"
	ACCOUNT_URL="${API}/acme/acct/${ACCOUNT_ID}"
else
	echo "Requesting CA for missing information about the account..."
	send_signed_request "${API}/acme/new-acct" '{\"onlyReturnExisting\": true}' "${API}/acme/acct"
	ACCOUNT_URL="`echo \"${RESPONSE}\" | grep ^Location: | awk '{print $2}' | tr -d '\r\n'`"
	send_signed_request "${ACCOUNT_URL}" '{}'
	ACCOUNT_ID="`echo \"${RESPONSE}\" | grep -oE '/[0-9]+' | cut -d/ -f2`"
	echo "${RESPONSE}" > "${LETSENCRYPT_ACCOUNT_KEY}.json"
fi

if [ "${ACTION}" = "revoke" ]; then
	if [ ! -e ${CERT} ]; then
		echo "Certificate ${CERT} does not exist, there is nothing to revoke."
		exit 1
	fi
	DER64="`${OPENSSL} x509 -in ${CERT} -inform PEM -outform DER | base64_encode`"
	send_signed_request "${API}/acme/revoke-cert" '{"certificate": "'"${DER64}"'"}' 
	if [ "${HTTP_STATUS}" = "" ] || [ "${HTTP_STATUS}" -eq 200 ] ; then
		echo "Certificate has been successfully revoked."
	else
		echo "Certificate revocation error. Response: ${RESPONSE}."
		exit 1
	fi
	exit 0
fi

#Overwrite san_config file if csr_cf_file path is different
if [ "${CSR_CF_FILE}" != "" ] && [ "${CSR_CF_FILE}" != "${SAN_CONFIG}" ]; then
	cp -f ${CSR_CF_FILE} ${SAN_CONFIG}
fi

#For multi-domains (www and non-www one)
SAN=""

if [ -s ${SAN_CONFIG} ] && ! ${DOMAINARR_IN_USE} && ! ${IS_SINGLE}; then
	SAN="`cat \"${SAN_CONFIG}\" | grep '^subjectAltName=' | cut -d= -f2`"
elif [ "${HOSTNAME}" -eq 0 ]; then
	if ${DOMAINARR_IN_USE} || ${IS_SINGLE}; then
		SAN=""
		for TDOMAIN in ${DOMAINARR}
		do
			CHALLENGE_TEST=`challenge_check ${TDOMAIN}`
			if [ ${CHALLENGE_TEST} -ne 1 ]; then
				SAN="${SAN}, DNS:${TDOMAIN}"
			else
				echo "skipping ${TDOMAIN} challenge test failed"
			fi
		done
		SAN=`echo ${SAN} | grep -o -E "DNS:(.*)"`
	elif ! echo "${DOMAIN}" | grep -q "^www\."; then
		#We have a domain without www., add www domain to to SAN too
		SAN="DNS:${DOMAIN}, DNS:www.${DOMAIN}"
	else
		#We have a domain with www., drop www and add it to SAN too
		DOMAIN2=`echo ${DOMAIN} | perl -p0 -e 's#^www.##'`
		SAN="DNS:${DOMAIN2}, DNS:www.${DOMAIN2}"
	fi
else
	#For hostname, we add www, mail, ftp, pop, smtp to the SAN
	if ${DOMAINARR_IN_USE} || ${IS_SINGLE};	then
		SAN=""
		for TDOMAIN in ${DOMAINARR}
		do
			SAN="${SAN}, DNS:${TDOMAIN}"
		done
		SAN=`echo ${SAN} | egrep -o "DNS:(.*)"`
	else

		if ! echo "${DOMAIN}" | grep -q "^www\."; then
			#We have a domain without www., add www domain to to SAN too
			MAIN_HOST=${DOMAIN}
		else
			#We have a domain with www., drop www and add it to SAN too
			DOMAIN2=`echo ${DOMAIN} | perl -p0 -e 's#^www.##'`
			MAIN_HOST=${DOMAIN2}
		fi
		SAN="DNS:${MAIN_HOST}"
		for A in www mail ftp pop smtp; do
		{
			H=${A}.${MAIN_HOST}
			CHALLENGE_TEST=`challenge_check ${H}`
			if [ ${CHALLENGE_TEST} -eq 1 ]; then
				if [ "${CHALLENGETYPE}" = "http-01" ]; then
					echo "${H} was skipped due to unreachable http://${H}/.well-known/acme-challenge/letsencrypt_${TIMESTAMP} file. Not adding to san_config"
				else
					echo "${H} was skipped due to missing DNS TXT entry at _acme-challenge.${H}. Not adding to san_config"
				fi
			else
				SAN="${SAN}, DNS:${H}"
			fi
		};
		done;
	fi
fi

DOMAINS="`echo ${SAN} | tr -d '\",' | perl -p0 -e 's#DNS:##g'`"

if echo ${DOMAINS} | grep -m1 -q '*\.'; then
	if [ "${CHALLENGETYPE}" = "http-01" ]; then
		echo "Found wildcard domain name and http-01 challenge type, switching to dns-01 validation."
		CHALLENGETYPE="dns-01"
	fi
fi

CN_DOMAIN=${DOMAIN}
if ! echo "${DOMAINS}" | grep -m1 -q "DNS:${DOMAIN},"; then
        CN_DOMAIN="`echo ${SAN} | cut -d':' -f2 | cut -d',' -f1`"
fi
if [ "${CN_DOMAIN}" = "" ]; then
	CN_DOMAIN=${DOMAIN}
fi

#Create san_config
if [ ! -s ${SAN_CONFIG} ] || ${DOMAINARR_IN_USE} || ${IS_SINGLE}; then
	echo "[ req_distinguished_name ]" > ${SAN_CONFIG}
	echo "CN = ${CN_DOMAIN}" >> ${SAN_CONFIG}
	echo "[ req ]" >> ${SAN_CONFIG}
	echo "distinguished_name = req_distinguished_name" >> ${SAN_CONFIG}
	echo "[SAN]" >> ${SAN_CONFIG}
	echo "subjectAltName=${SAN}" >> ${SAN_CONFIG}
fi

chown diradmin:diradmin ${SAN_CONFIG}
chmod 600 ${SAN_CONFIG}

#Form identifiers
IDENTIFIERS_PART=""
for single_domain in ${DOMAINS}; do {
	IDENTIFIERS_PART="${IDENTIFIERS_PART}, {\"type\": \"dns\", \"value\": \"${single_domain}\"}";
}
done
IDENTIFIERS_PART="`echo \"${IDENTIFIERS_PART}\" | perl -p0 -e 's|^, ||g'`"
IDENTIFIERS="{\"identifiers\": [${IDENTIFIERS_PART}]}"

echo "Requesting new certificate order..."
send_signed_request "${API}/acme/new-order" "${IDENTIFIERS}"

#Account has a key for let's encrypt, but it's not registered
if [ "${HTTP_STATUS}" -eq 403 ] ; then
	echo "User let's encrypt key has been found, but not registered. Registering..."
	send_signed_request "${API}/acme/new-acct" '{"contact": ["mailto: '${EMAIL}'"], "termsOfServiceAgreed": true}' > ${LETSENCRYPT_ACCOUNT_KEY}.json
	if [ "${HTTP_STATUS}" = "" ] || [ "${HTTP_STATUS}" -eq 201 ] ; then
		echo "Account has been registered."
	elif [ "${HTTP_STATUS}" -eq 409 ] ; then
		echo "Account is already registered."
	else
		echo "Account registration error. Response: ${RESPONSE}."
		rm -f ${LETSENCRYPT_ACCOUNT_KEY}.json ${LETSENCRYPT_ACCOUNT_KEY}
		exit 1
	fi

	echo "Requesting new certificate order..."
	send_signed_request "${API}/acme/new-order" "${IDENTIFIERS}"
fi

if [ "${HTTP_STATUS}" -ne 201 ] ; then
	echo "new-order error: ${RESPONSE}. Exiting..."
	exit 1
fi

AUTHORIZATIONS="`echo \"${RESPONSE}\" | tr -d '\n' | grep -o '"authorizations": \[[^]]*' | cut -d'[' -f2 | cut -d ']' -f1 | tr -d '",'`"
FINALIZE="`echo \"${RESPONSE}\" | grep -o '"finalize": ".*"' | awk '{print $2}' | tr -d '"'`"

if [ "${AUTHORIZATIONS}" = "" ]; then
	echo "Authorizations list empty, cannot continue. Exiting..."
	exit 1
fi

if [ "${FINALIZE}" = "" ]; then
	echo "Finalize URL empty, cannot continue. Exiting..."
	exit 1
fi

#For each of the domains, we need to verify them
for authorization in ${AUTHORIZATIONS}; do {
	AUTHORIZATION_REPLY="`${CURL} ${CURL_OPTIONS} ${authorization}`"
	single_domain="`echo \"${AUTHORIZATION_REPLY}\" | tr -d '\n' | grep -o -m1 '\"identifier\":[^}]*' | grep -o '\"value\": \"[^\"]*' | awk '{print $2}' | tr -d '\"'`"
	if [ "${single_domain}" = "" ]; then
		echo "Unable to determine domain name for authorization. Exiting..."
		exit 1
	else
		echo "Processing authorization for ${single_domain}..."
	fi
	
	if echo "${AUTHORIZATION_REPLY}" | grep -m1 -q '"status": "valid"'; then
		echo "Challenge is valid."
		continue
	fi

	CHALLENGE="`echo \"${AUTHORIZATION_REPLY}\" | tr -d '\n' | grep -o "\\"type\\": \\"${CHALLENGETYPE}\\",[^}]*"`"

	CHALLENGE_TOKEN="`echo \"${CHALLENGE}\" | tr ',' '\n' | grep -m1 '\"token\":' | cut -d'\"' -f4`"
	CHALLENGE_URI="`echo \"${CHALLENGE}\" | tr ',' '\n' | grep -m1 '\"url\":' | cut -d'\"' -f4`"
	CHALLENGE_STATUS="`echo \"${CHALLENGE}\" | tr ',' '\n' | grep -m1 '\"status\":' | cut -d'\"' -f4`"

	if [ "${CHALLENGE_TOKEN}" = "" ]; then
		echo "Challenge token is empty. Something went wrong. Exiting..."
		exit 1
	fi

	KEYAUTH="${CHALLENGE_TOKEN}.${THUMBPRINT}"

	if [ "${CHALLENGETYPE}" = "dns-01" ]; then
		DNSENTRY="`echo -n \"${KEYAUTH}\" | \"${OPENSSL}\" dgst -sha256 -binary | base64_encode`"
		# We must create _acme-challenge IN TXT for ${DOMAIN} here with DNSENTRY value
		# something like the following with very low TTL of 5sec or so: _acme-challenge 1 IN TXT "${DNSENTRY}"
		#
		# We cannot have SAN like: *.testing.martynas.it,abc.testing.martynas.it,testing.martynas.it, because it throws:
		# detail": "Error creating new order :: Domain name \"abc.testing.martynas.it\" is redundant with a wildcard domain in the same request. Remove one or the other from the certificate request.",
		echo "action=dns&do=delete&domain=${single_domain}&type=TXT&name=_acme-challenge" >> ${TASK_QUEUE}
		# it's run in reverse because the list is sorted for duplicates.  Must run the dataskq immediately before calling the add.
		run_dataskq
		echo "action=dns&do=add&domain=${single_domain}&type=TXT&name=_acme-challenge&value=\"${DNSENTRY}\"&ttl=5&named_reload=yes" >> ${TASK_QUEUE}
		run_dataskq
	else
		if [ "${DOMAIN_DIR}" = "/var/www/html" ]; then
			mkdir -p ${WELLKNOWN_PATH}
			chown webapps:webapps ${HOSTNAME_DIR}/.well-known
			chown webapps:webapps ${WELLKNOWN_PATH}
		fi

		if [ ! -d "${WELLKNOWN_PATH}" ]; then
			echo "Cannot find ${WELLKNOWN_PATH}. Create this path, ensure it's chowned to the User.";
			exit 1;
		fi
		echo "${KEYAUTH}" > "${WELLKNOWN_PATH}/${CHALLENGE_TOKEN}"
		chown webapps:webapps "${WELLKNOWN_PATH}/${CHALLENGE_TOKEN}"
	fi

	#Checking if challenge will be reachable
	CHALLENGE_TEST=`challenge_check ${single_domain}`
	if [ ${CHALLENGE_TEST} -eq 1 ] && [ "${CHALLENGETYPE}" = "http-01" ]; then
		echo "Error: http://${single_domain}/.well-known/acme-challenge/letsencrypt_${TIMESTAMP} is not reachable. Aborting the script."
		echo "dig output for ${single_domain}:"
		${DIG} @${DNS_SERVER} ${single_domain} +short
		${DIG} @${DNS_SERVER} AAAA ${single_domain} +short
		if [ ${LETSENCRYPT_OPTION} -eq 1 ]; then
			echo "Please make sure /.well-known alias is setup in WWW server."
		else
			echo "Please make sure .htaccess or WWW server is not preventing access to /.well-known folder."
		fi
        exit 1
    elif [ ${CHALLENGE_TEST} -eq 1 ]; then
		MAXTRIES=20
		TRIES=0
		# Get NS entries from the domain
		echo "DNS challenge test fail for _acme-challenge.${single_domain} IN TXT \"${DNSENTRY}\", retrying..."
		while [ ${CHALLENGE_TEST} -eq 1 ]; do
			CHALLENGE_TEST=`challenge_check ${single_domain}`
			sleep ${DIG_SECONDS}
			TRIES=`expr ${TRIES} + 1`
			if [ "${TRIES}" = "${MAXTRIES}" ]; then
				echo "DNS validation failed. Exiting..."
				exit 1
			fi
			echo "Retry failed, trying again in ${DIG_SECONDS}s..."
		done
	fi

	sleep 1

	echo "Waiting for domain verification..."
	while [ "${CHALLENGE_STATUS}" = "pending" ]; do
		sleep 1
		send_signed_request "${CHALLENGE_URI}" "{\"keyAuthorization\": \"${KEYAUTH}\"}"
		FULL_CHALLENGE_STATUS="`${CURL} ${CURL_OPTIONS} -X GET \"${CHALLENGE_URI}\"`"
		CHALLENGE_STATUS="`echo ${FULL_CHALLENGE_STATUS} | tr ',' '\n' | grep -m1 '\"status\":' | cut -d'\"' -f4`"
		CHALLENGE_DETAIL="`echo ${FULL_CHALLENGE_STATUS} | tr ',' '\n' | grep -m1 '\"detail\":' | cut -d'\"' -f4`"
	done

	CHALLENGE_STATUS_VALID=false

	if echo "${RESPONSE}" | grep -m1 -q '"status": "valid"'; then
		echo "Challenge is valid."
		CHALLENGE_STATUS_VALID=true
	fi

	if [ "${CHALLENGE_STATUS}" != "valid" ]; then
		echo "Trying again..."
		for n in `seq 1 5`; do
		sleep 1;
		echo -n "${n}..";
		done;
		echo "";
		send_signed_request "${CHALLENGE_URI}" "{\"keyAuthorization\": \"${KEYAUTH}\"}"
		sleep 1;
	else
		CHALLENGE_STATUS_VALID=true
	fi

	if ! ${CHALLENGE_STATUS_VALID}; then
		send_signed_request "${CHALLENGE_URI}" "{\"keyAuthorization\": \"${KEYAUTH}\"}"
		FULL_CHALLENGE_STATUS="`${CURL} ${CURL_OPTIONS} -X GET \"${CHALLENGE_URI}\"`"
		CHALLENGE_STATUS_RESPONSE="`echo \"${FULL_CHALLENGE_STATUS}\" | tr -d '\n' | grep -o "\\"type\\": \\"${CHALLENGETYPE}\\",[^}]*"`"
		CHALLENGE_STATUS="`echo \"${CHALLENGE_STATUS_RESPONSE}\" | tr ',' '\n' | grep -m1 '\"status\":' | cut -d'\"' -f4`"

		if [ "${CHALLENGE_STATUS}" != "valid" ]; then
			echo "Challenge status: ${CHALLENGE_STATUS}. Challenge error: ${CHALLENGE_STATUS_RESPONSE}. Exiting..."
			exit 1
		fi
	fi
	
	if [ "${CHALLENGETYPE}" = "http-01" ]; then
		rm -f "${WELLKNOWN_PATH}/${CHALLENGE_TOKEN}"
	fi

	if [ "${CHALLENGE_STATUS}" = "valid" ]; then
		echo "Challenge is valid."
	else
		if [ "${CHALLENGETYPE}" = "dns-01" ]; then
			echo "action=dns&do=delete&domain=${single_domain}&type=TXT&name=_acme-challenge&value=\"${DNSENTRY}\"" >> ${TASK_QUEUE}
			run_dataskq
		fi
		echo "Challenge is ${CHALLENGE_STATUS}. Details: ${CHALLENGE_DETAIL}. Exiting..."
		exit 1
	fi
}
done

#Create domain key, also generate CSR for the domain
echo "Generating ${KEY_SIZE} bit RSA key for ${DOMAIN}..."
echo "openssl genrsa ${KEY_SIZE} > \"${KEY}.new\""
${OPENSSL} genrsa ${KEY_SIZE} > "${KEY}.new"

${OPENSSL} req -new -sha256 -key "${KEY}.new" -subj "/CN=${CN_DOMAIN}" -reqexts SAN -config "${SAN_CONFIG}" -out "${CSR}"

#Request certificate from let's encrypt
DER64="`${OPENSSL} req -in ${CSR} -outform DER | base64_encode`"

send_signed_request "${FINALIZE}" "{\"resource\": \"new-cert\", \"csr\": \"${DER64}\"}"
CERTIFICATE_URL="`echo ${RESPONSE} | grep -m1 -o '\"certificate\": \"[^\"]*' | cut -d'\"' -f4`"

if [ "${CERTIFICATE_URL}" = "" ]; then
	echo "Unable to find certificate. Something went wrong. Printing response..."
	echo "${RESPONSE}" | grep -o '"detail": ".*"' | cut -d'"' -f4
	echo ""
	exit 1
fi

${CURL} ${CURL_OPTIONS} ${CERTIFICATE_URL} > ${CERT}.new.tmp

${OPENSSL} x509 -text < ${CERT}.new.tmp > /dev/null 2>&1
if [ $? -ne 0 ]; then
	echo "Certificate error in ${CERT}. Exiting..."
	/bin/rm -f ${KEY}.new ${CERT}.new.tmp
	exit 1
fi

openssl x509 -in ${CERT}.new.tmp -out ${CERT}.new
sed '1,/^$/d' ${CERT}.new.tmp > ${CACERT}.new

echo -n "Checking Certificate Private key match... "
CHECKPRIVPUBRES=`checkPrivPubMatch ${KEY}.new ${CERT}.new`
if [ $CHECKPRIVPUBRES -eq 0 ]; then
	echo "Match!"
else
	echo "Certificate mismatch!!!"
	rm -f ${KEY}.new ${CERT}.new.tmp ${CACERT}.new
	exit 1
fi

#everything went well, move the new files.
/bin/mv -f ${KEY}.new ${KEY}
/bin/mv -f ${CERT}.new ${CERT}
if [ -s ${CACERT}.new ]; then
	/bin/mv -f ${CACERT}.new ${CACERT}
fi
if [ ! -s ${CACERT} ]; then
echo "-----BEGIN CERTIFICATE-----
MIIEkjCCA3qgAwIBAgIQCgFBQgAAAVOFc2oLheynCDANBgkqhkiG9w0BAQsFADA/
MSQwIgYDVQQKExtEaWdpdGFsIFNpZ25hdHVyZSBUcnVzdCBDby4xFzAVBgNVBAMT
DkRTVCBSb290IENBIFgzMB4XDTE2MDMxNzE2NDA0NloXDTIxMDMxNzE2NDA0Nlow
SjELMAkGA1UEBhMCVVMxFjAUBgNVBAoTDUxldCdzIEVuY3J5cHQxIzAhBgNVBAMT
GkxldCdzIEVuY3J5cHQgQXV0aG9yaXR5IFgzMIIBIjANBgkqhkiG9w0BAQEFAAOC
AQ8AMIIBCgKCAQEAnNMM8FrlLke3cl03g7NoYzDq1zUmGSXhvb418XCSL7e4S0EF
q6meNQhY7LEqxGiHC6PjdeTm86dicbp5gWAf15Gan/PQeGdxyGkOlZHP/uaZ6WA8
SMx+yk13EiSdRxta67nsHjcAHJyse6cF6s5K671B5TaYucv9bTyWaN8jKkKQDIZ0
Z8h/pZq4UmEUEz9l6YKHy9v6Dlb2honzhT+Xhq+w3Brvaw2VFn3EK6BlspkENnWA
a6xK8xuQSXgvopZPKiAlKQTGdMDQMc2PMTiVFrqoM7hD8bEfwzB/onkxEz0tNvjj
/PIzark5McWvxI0NHWQWM6r6hCm21AvA2H3DkwIDAQABo4IBfTCCAXkwEgYDVR0T
AQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAYYwfwYIKwYBBQUHAQEEczBxMDIG
CCsGAQUFBzABhiZodHRwOi8vaXNyZy50cnVzdGlkLm9jc3AuaWRlbnRydXN0LmNv
bTA7BggrBgEFBQcwAoYvaHR0cDovL2FwcHMuaWRlbnRydXN0LmNvbS9yb290cy9k
c3Ryb290Y2F4My5wN2MwHwYDVR0jBBgwFoAUxKexpHsscfrb4UuQdf/EFWCFiRAw
VAYDVR0gBE0wSzAIBgZngQwBAgEwPwYLKwYBBAGC3xMBAQEwMDAuBggrBgEFBQcC
ARYiaHR0cDovL2Nwcy5yb290LXgxLmxldHNlbmNyeXB0Lm9yZzA8BgNVHR8ENTAz
MDGgL6AthitodHRwOi8vY3JsLmlkZW50cnVzdC5jb20vRFNUUk9PVENBWDNDUkwu
Y3JsMB0GA1UdDgQWBBSoSmpjBH3duubRObemRWXv86jsoTANBgkqhkiG9w0BAQsF
AAOCAQEA3TPXEfNjWDjdGBX7CVW+dla5cEilaUcne8IkCJLxWh9KEik3JHRRHGJo
uM2VcGfl96S8TihRzZvoroed6ti6WqEBmtzw3Wodatg+VyOeph4EYpr/1wXKtx8/
wApIvJSwtmVi4MFU5aMqrSDE6ea73Mj2tcMyo5jMd6jmeWUHK8so/joWUoHOUgwu
X4Po1QYz+3dszkDqMp4fklxBwXRsW10KXzPMTZ+sOPAveyxindmjkW8lGy+QsRlG
PfZ+G6Z6h7mjem0Y+iWlkYcV4PIWL1iwBi8saCbGS5jN2p8M+X+Q7UNKEkROb3N6
KOqkqm57TH2H3eDJAkSnh6/DNFu0Qg==
-----END CERTIFICATE-----" > ${CACERT}
fi
date +%s > ${CERT}.creation_time

cat ${CERT} ${CACERT} > ${CERT}.combined

chown ${FILE_CHOWN} ${KEY} ${CERT} ${CERT}.combined ${CACERT} ${CSR} ${CERT}.creation_time
chmod ${FILE_CHMOD} ${KEY} ${CERT} ${CERT}.combined ${CACERT} ${CSR} ${CERT}.creation_time

#Change exim, apache/nginx certs
if [ "${HOSTNAME}" -eq 1 ]; then
	echo "DirectAdmin certificate has been setup."

	#Exim
	echo "Setting up cert for Exim..."
	EXIMKEY="/etc/exim.key"
	EXIMCERT="/etc/exim.cert"
	cp -f ${KEY} ${EXIMKEY}
	cat ${CERT} ${CACERT} > ${EXIMCERT}
	chown mail:mail ${EXIMKEY} ${EXIMCERT}
	chmod 600 ${EXIMKEY} ${EXIMCERT}

	echo "action=exim&value=restart" >> ${TASK_QUEUE}
	echo "action=dovecot&value=restart" >> ${TASK_QUEUE}

	#Apache
	echo "Setting up cert for WWW server..."
	if [ -d /etc/httpd/conf/ssl.key ] && [ -d /etc/httpd/conf/ssl.crt ]; then
		APACHEKEY="/etc/httpd/conf/ssl.key/server.key"
		APACHECERT="/etc/httpd/conf/ssl.crt/server.crt"
		APACHECACERT="/etc/httpd/conf/ssl.crt/server.ca"
		APACHECERTCOMBINED="${APACHECERT}.combined"
		cp -f ${KEY} ${APACHEKEY}
		cp -f ${CERT} ${APACHECERT}
		cp -f ${CACERT} ${APACHECACERT}
		cat ${APACHECERT} ${APACHECACERT} > ${APACHECERTCOMBINED}
		chown root:root ${APACHEKEY} ${APACHECERT} ${APACHECACERT} ${APACHECERTCOMBINED}
		chmod 600 ${APACHEKEY} ${APACHECERT} ${APACHECACERT} ${APACHECERTCOMBINED}

		echo "action=httpd&value=restart" >> ${TASK_QUEUE}
	fi

	#Nginx
	if [ -d /etc/nginx/ssl.key ] && [ -d /etc/nginx/ssl.crt ]; then
		NGINXKEY="/etc/nginx/ssl.key/server.key"
		NGINXCERT="/etc/nginx/ssl.crt/server.crt"
		NGINXCACERT="/etc/nginx/ssl.crt/server.ca"
		NGINXCERTCOMBINED="${NGINXCERT}.combined"
		cp -f ${KEY} ${NGINXKEY}
		cp -f ${CERT} ${NGINXCERT}
		cp -f ${CACERT} ${NGINXCACERT}
		cat ${NGINXCERT} ${NGINXCACERT} > ${NGINXCERTCOMBINED}
		chown root:root ${NGINXKEY} ${NGINXCERT} ${NGINXCACERT} ${NGINXCERTCOMBINED}
		chmod 600 ${NGINXKEY} ${NGINXCERT} ${NGINXCACERT} ${NGINXCERTCOMBINED}

		echo "action=nginx&value=restart" >> ${TASK_QUEUE}
	fi

	#FTP
	echo "Setting up cert for FTP server..."
	cat ${KEY} ${CERT} ${CACERT} > /etc/pure-ftpd.pem
	chmod 600 /etc/pure-ftpd.pem
	chown root:root /etc/pure-ftpd.pem

	if /usr/local/directadmin/directadmin c | grep -m1 -q "^pureftp=1\$"; then
		echo "action=pure-ftpd&value=restart" >> ${TASK_QUEUE}
	else
		echo "action=proftpd&value=restart" >> ${TASK_QUEUE}
	fi

	echo "action=directadmin&value=restart" >> ${TASK_QUEUE}
	echo "The services will be restarted in about 1 minute via the dataskq."
	run_dataskq
fi

echo "Certificate for ${DOMAIN} has been created successfully!"
