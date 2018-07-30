#!/usr/local/bin/php -c/usr/local/directadmin/scripts/php_clean.ini
<?php

$version = 0.1;

/*
Backup script for the per-domain RoundCube settings.
Backup/Restore written by DirectAdmin: http://www.directadmin.com
RoundCube Webmail Client: http://roundcube.net

This script will generate a per-domain XML output of all users for that domain, in the roundcube database.
It will also include one system account username (eg: admin), which is associated with the domain.
The XML file is index/ID independant, so you can restore a set of domain accounts onto any other
active DirectAdmin/RoundCube database without worry of ID conflicts.
See the restore_roundcube.php for info on the restore process.

See the DirectAdmin versions system for more info:
http://www.directadmin.com/features.php?id=1062

All variables are passed via environment, not command line options
But you can specify environmental variables... via command line options before the script (see the showHelp() function)

RETURN VALUES
0: All is well
>1: an error worthy or reporting has occured. Message on stderr.
1: an error, most likely due to not actually having RoundCube installed or no restore data, has occured.

*/

/***********************
* Environmental variables
*/
$domain = getenv("domain");				//Get all email users from this domain.
$system_username = getenv("username");	//Also get this single system account
$xml_file = getenv("xml_file");			//and save all info to this file.

/***********************
* this restores as da_admin instead of da_roundube.
* For the backup, we are less concerned with dangerous data, so we use it for reliability reasons.
*/
$high_access_connection = TRUE;

/***********************
* If $high_access_restore is false, this is used for the mysql credentials.
*/
$rc_config = "/var/www/html/roundcube/config/config.inc.php";

//****************************************************************
//****************************************************************

if (!isset($domain) || $domain == "")
	show_help();

if (!isset($system_username) || $system_username == "")
	show_help();

if (!isset($xml_file) || $xml_file == "")
	show_help();

if (!extension_loaded('mysqli'))
{
	echo_stderr("Php is not compiled with mysqli. Cannot dump roundcube settings.\n");
	exit(1);
}


//****************************************************************
//****************************************************************

if ($high_access_connection)
{
	$mysql_conf = @parse_ini_file("/usr/local/directadmin/conf/mysql.conf");
}

if ($high_access_connection && $mysql_conf)
{

	$mysql_user = $mysql_conf['user'];
	$mysql_pass = $mysql_conf['passwd'];
	$mysql_host = 'localhost';
	$mysql_db = 'da_roundcube';

	if (isset($mysql_conf['host']) && $mysql_conf['host'] != "")
		$mysql_host = $mysql_conf['host'];
}
else
{
	if (!file_exists($rc_config))
	{
		echo_stderr("Cannot find RoundCube config at $rc_config.  Is RC installed and up to date?\n");
		exit(7);
	}

	include_once($rc_config);

	if (!isset($config) || !isset($config['db_dsnw']) || $config['db_dsnw'] == '')
	{
		echo_stderr("Cannot find \$config['db_dsnw'] variable in $rc_config\n");
		exit(6);
	}

	//$config['db_dsnw'] = 'mysql://da_roundcube:password@localhost/da_roundcube';

	$values = explode('/', $config['db_dsnw']);
	$connect = explode('@', $values[2]);
	$auth = explode(':', $connect[0]);

	$mysql_user = $auth[0];
	$mysql_pass = $auth[1];
	$mysql_host = $connect[1];
	$mysql_db = $values[3];
}

$mysqli = new mysqli($mysql_host, $mysql_user, $mysql_pass);
if ($mysqli->connect_errno) {
    echo_stderr("Failed to connect to MySQL: (" . $mysqli->connect_errno . ") " . $mysqli->connect_error."\n");
    exit(3);
}
$mysqli->set_charset('utf8');

if (!$mysqli->select_db($mysql_db))
{
	echo_stderr("There is no $mysql_db database. Skipping RoundCube backup.\n");
	exit(1);
}

//****************************************************************
//****************************************************************

//Check if we have contactgroups
$have_contactgroups = true;
$query = "SHOW TABLES LIKE 'contactgroups'";
$result = $mysqli->query($query);
if ($result->num_rows == 0)
{
	$have_contactgroups = false;
}



//First, find all accounts for this domain.
$query = "SELECT * FROM  `users` WHERE username LIKE '%@".mes($domain)."' OR username='".mes($system_username)."'";
$result = $mysqli->query($query);

if (!$result)
{
	echo_stderr("Query error with user selection: ".$mysqli->error);
	$mysqli->close();
	exit(8);
}

$top_depth = 0;

$fp = @fopen($xml_file, 'w');
if (!$fp)
{
	echo_stderr("Unable to open $xml_file for writing. Unable to backup RoundCube Data.");
	$mysqli->close();
	exit(5);
}

xml_open("ROUNDCUBE", $top_depth);

while($user = $result->fetch_object())
{
	$email_depth = $top_depth + 1;
	$email_item_depth = $email_depth + 1;

	xml_open("EMAIL", $email_depth);

	//echo "usermname = ".$user->username."\n";
	//echo "user_id = ".$user->user_id."\n";
	xml_item("USERNAME", $user->username, $email_item_depth);
	xml_item("LANGUAGE", $user->language, $email_item_depth);
	xml_item("PREFERENCES", $user->preferences, $email_item_depth);
	xml_item("CREATED", $user->created, $email_item_depth);
	xml_item("LAST_LOGIN", $user->last_login, $email_item_depth);

	//get all indentities
	$query = "SELECT * FROM `identities` WHERE user_id=".$user->user_id." AND del=0";
	$identities_result = $mysqli->query($query);

	xml_open("INDENTITIES", $email_item_depth);
	while ($identity = $identities_result->fetch_array())
	{
		$identity_depth = $email_item_depth + 1;
		$identity_item_depth = $identity_depth + 1;

		xml_open("INDENTITY", $identity_depth);

		xml_item("EMAIL", $identity['email'], $identity_item_depth);
		xml_item("STANDARD", $identity['standard'], $identity_item_depth);
		xml_item("NAME", $identity['name'], $identity_item_depth);
		xml_item("CHANGED", $identity['changed'], $identity_item_depth);
		xml_item("ORGANIZATION", $identity['organization'], $identity_item_depth);
		xml_item("REPLY-TO", $identity['reply-to'], $identity_item_depth);
		xml_item("BCC", $identity['bcc'], $identity_item_depth);
		xml_item("SIGNATURE", $identity['signature'], $identity_item_depth);
		xml_item("HTML_SIGNATURE", $identity['html_signature'], $identity_item_depth);

		xml_close("INDENTITY", $identity_depth);
	}
	xml_close("INDENTITIES", $email_item_depth);

	//dictionary?

	//contacts
	$query = "SELECT * FROM `contacts` WHERE user_id=".$user->user_id." AND del=0";
	$contacts_result = $mysqli->query($query);

	xml_open("CONTACTS", $email_item_depth);
	while ($contact = $contacts_result->fetch_array())
	{

		$contact_depth = $email_item_depth + 1;
		$contact_item_depth = $contact_depth + 1;

		xml_open("CONTACT", $contact_depth);

		xml_item('EMAIL', $contact['email'], $contact_item_depth);
		xml_item('NAME', $contact['name'], $contact_item_depth);
		xml_item('CHANGED', $contact['changed'], $contact_item_depth);
		xml_item('FIRSTNAME', $contact['firstname'], $contact_item_depth);
		xml_item('SURNAME', $contact['surname'], $contact_item_depth);
		xml_item('VCARD', $contact['vcard'], $contact_item_depth);
		xml_item('WORDS', $contact['words'], $contact_item_depth);

		xml_open("GROUPS", $contact_item_depth);
		if ($have_contactgroups)
		{
			$query = "SELECT m.*,g.name,g.changed FROM `contactgroups` as g, `contactgroupmembers` as m WHERE m.contact_id=".$contact['contact_id']." AND g.contactgroup_id=m.contactgroup_id AND g.del=0";
			if (!($groups_result = $mysqli->query($query)))
			{
				echo_stderr("group query error: ".$mysqli->error."\n");
				exit(4);
			}

			while ($group = $groups_result->fetch_array())
			{
				xml_open("GROUP", $contact_item_depth+1);

				xml_item("NAME", $group['name'], $contact_item_depth+2);
				xml_item("CHANGED", $group['changed'], $contact_item_depth+2);
				xml_item("CREATED", $group['created'], $contact_item_depth+2);

				xml_close("GROUP", $contact_item_depth+1);
			}
		}
		xml_close("GROUPS", $contact_item_depth);

		xml_close("CONTACT", $contact_depth);
	}
	xml_close("CONTACTS", $email_item_depth);

	xml_close("EMAIL", 1);
}

xml_close("ROUNDCUBE", $top_depth);

fclose($fp);
$mysqli->close();

exit(0);
//**********************************************************************

function xml_item($name, $value, $tabs)
{
	global $fp;

	for ($i=0; $i<$tabs; $i++)
		fwrite($fp, "\t");

	fwrite($fp, "<".$name.">");
	fwrite($fp, urlencode($value));
	fwrite($fp, "</".$name.">\n");
}

function xml_open($name, $tabs)
{
	global $fp;

	for ($i=0; $i<$tabs; $i++)
		fwrite($fp, "\t");

	fwrite($fp, "<".$name.">\n");
}
function xml_close($name, $tabs)
{
	global $fp;

	for ($i=0; $i<$tabs; $i++)
		fwrite($fp, "\t");

	fwrite($fp, "</".$name.">\n");
}

function show_help()
{
	global $version;
	echo_stderr("Roundcube $version backup script to backup Users.\n\n");
	echo_stderr("Usage:\n");
	echo_stderr("  username=username domain=domain.com xml_file=/path/to/rc.xml ".__FILE__."\n\n");

	echo_stderr("The script will output XML of all current email accounts stored in roundcube,\n");
	echo_stderr("for the given domain.\n");
	exit(2);
}

function die_stderr($str)
{
	echo_stderr($str);
	die();
}

function echo_stderr($str)
{
	$fd = fopen('php://stderr', 'w');
	fwrite($fd, $str);
	fclose($fd);
}

function mes($str)
{
	global $mysqli;
	return $mysqli->real_escape_string($str);
}

?>
