<?php
$version = '2.0';

$user = getenv('DBUSER');
$pass = getenv('DBPASS');
$username = getenv('USERNAME');
$newusername = getenv('NEWUSERNAME');

$host = getenv('DBHOST');
if ($host == "")
	$host = 'localhost';

$verbose = getenv('VERBOSE');
$verbose = ($verbose == 1) ? 1 : 0;
$ignore_errors = 0;		//power through at your own risk

$exit_code = 0;

$rename_database_sh = '/usr/local/directadmin/scripts/rename_database.sh';
if (file_exists('/usr/local/directadmin/scripts/custom/rename_database.sh'))
	$rename_database_sh = '/usr/local/directadmin/scripts/custom/rename_database.sh';

if ($username == "" || $username == "root" || $username == "mysql")
{
	die("Bad username ($username). aborting mysql database swap");
}

if ($newusername == "" || $newusername == "root" || $newusername == "mysql")
{
        die('Bad new username. aborting mysql database swap');
}

$mysqli = new mysqli('localhost',$user,$pass);
if ($mysqli->connect_error)
{
	die('Could not connect to mysql: ('.$mysqli->connect_errno.') '. $mysqli->connect_error);
}

//*******************************************************************
// Main code

$mysqli->select_db('mysql');

replace_users($mysqli);
rename_dbs($mysqli);

$mysqli->query("FLUSH_PRIVILEGES");
$mysqli->close();

exit($exit_code);

//*******************************************************************

function rename_dbs($mysqli)
{
	global $username, $newusername, $ignore_errors, $rename_database_sh, $exit_code;

	// This will find all databases owned by the User
	// for each db, create a new db with the correct name (based on the old db?)
	// for each db, it finds all tables


	$user_dbs = get_user_dbs($mysqli);

	foreach ($user_dbs as $db)
	{
		$new_db = preg_replace('/'.$username.'\\_/', $newusername.'_', $db);

		vecho("Swapping $db to $new_db\n");

		//This will mysqldump -> mysql to a new CREATE DB
		//and will update mysql.db, mysql.columns_priv, mysql.procs_priv, mysql.tables_priv
		$ret = 0;
		system($rename_database_sh." '".$db."' '".$new_db."'", $ret);
		if ($ret != 0)
			$exit_code = $ret;

	}
}

function get_user_dbs($mysqli)
{
	global $username;

	$query = "SHOW DATABASES LIKE '$username\\_%'";
	if (! ($result = $mysqli->query($query)) )
	{
		die("DB List Error: ". $mysqli->error);
	}

	$db_array = array();

	while (($row = $result->fetch_row()))
	{
		array_push($db_array, $row[0]);
	}

	$result->free();

	return $db_array;
}


function replace_users($mysqli)
{
	global $username;
	global $newusername;

	//in this function, we need to replace
	// username to newusername
	// username_user to newusername_user

	$mysqli->query("UPDATE mysql.user SET user='$newusername' WHERE user='$username'");
	$mysqli->query("UPDATE mysql.db SET user='$newusername' WHERE user='$username'");
	$query = "SELECT user,host FROM mysql.user WHERE user LIKE '$username\\_%'";
	$result = $mysqli->query($query) or vecho("Error selecting mysql.user: ".$mysqli->error."\n", 1);

	while ($row = $result->fetch_row())
	{
		$user = $row[0];
		$host = $row[1];
		$new_user = preg_replace('/'.$username.'_/', $newusername."_", $user);

		vecho("swapping '$user'@'$host' with '$new_user'@'$host'");

		$query = "RENAME USER '$user'@'$host' TO '$new_user'@'$host'";
		$mysqli->query($query) or vecho("Error updating '$user'@'$host' to '$new_user'@'$host' in mysql.user: ".$mysqli->error."\n", 1);
	}
	$result->free();
}

function vecho($str, $is_err=0)
{
	global $verbose;

	if ($verbose || $is_err==1)
	echo $str."\n";
}

?>
