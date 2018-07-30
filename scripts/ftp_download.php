#!/usr/local/bin/php
<?php

$use_pasv = true;
$url_curl = false;

$ftp_server = getenv("ftp_ip");
$ftp_user_name = getenv("ftp_username");
$ftp_user_pass = getenv("ftp_password");
$ftp_remote_path = getenv("ftp_path");
$ftp_port = getenv("ftp_port");
$ftp_remote_file = getenv("ftp_remote_file");
$ftp_local_file = getenv("ftp_local_file");

$ftp_secure = getenv("ftp_secure");
$ftps = false;
if ($ftp_secure == "ftps")
	$ftps = true;

if ($url_curl)
{
	$exit_code = download_with_curl();
	exit($exit_code);
}

if ($ftps && !function_exists("ftp_ssl_connect"))
{
	echo "ftp_ssl_connect function does not exist. Dropping down to insecure ftp.\n";
	$ftps = false;
}

if ($ftps)
	$conn_id = ftp_ssl_connect($ftp_server, $ftp_port);
else
	$conn_id = ftp_connect($ftp_server, $ftp_port);

if (!$conn_id)
{
	echo "Unable to connect to ${ftp_server}:${ftp_port}\n";
	exit(1);
}

$login_result = ftp_login($conn_id, $ftp_user_name, $ftp_user_pass);

if (!$login_result)
{
	echo "Invalid login/password for $ftp_user_name on $ftp_server\n";
	ftp_close($conn_id);
	exit(2);
}

ftp_pasv($conn_id, $use_pasv);

if (!ftp_chdir($conn_id, $ftp_remote_path))
{
	echo "Invalid remote path '$ftp_remote_path'\n";
	ftp_close($conn_id);
	exit(3);
}

if (ftp_get($conn_id, $ftp_local_file, $ftp_remote_file, FTP_BINARY))
{
	ftp_close($conn_id);
	exit(0);
}
else
{
	$use_pasv = false;

	ftp_pasv($conn_id, $use_pasv);

	if (ftp_get($conn_id, $ftp_local_file, $ftp_remote_file, FTP_BINARY))
	{
		ftp_close($conn_id);
			exit(0);
	}
	else
	{
		echo "Error while downloading $ftp_remote_file\n";
		ftp_close($conn_id);
		exit(4);
	}
}



function download_with_curl()
{
	global $use_pasv, $ftp_server, $ftp_user_name, $ftp_user_pass, $ftp_remote_path, $ftp_port, $ftp_remote_file, $ftp_local_file, $ftp_secure, $ftps;

	$ftp_url = "ftp://".$ftp_server.":".$ftp_remote_path."/".$ftp_remote_file;
	$ch = curl_init();

	if (!$ch)
	{
		echo "Could not intialize curl\n";
		return 5;
	}

	curl_setopt($ch, CURLOPT_URL,				$ftp_url);
	curl_setopt($ch, CURLOPT_USERPWD,			$ftp_user_name.':'.$ftp_user_pass);
	curl_setopt($ch, CURLOPT_SSL_VERIFYPEER,	false);
	curl_setopt($ch, CURLOPT_SSL_VERIFYHOST,	false);
	curl_setopt($ch, CURLOPT_FTP_SSL,			CURLFTPSSL_ALL);
	curl_setopt($ch, CURLOPT_FTPSSLAUTH,		CURLFTPAUTH_TLS);
	//curl_setopt($ch, CURLOPT_PROTOCOLS,		CURLPROTO_FTPS);
	curl_setopt($ch, CURLOPT_PORT,				$ftp_port);
	curl_setopt($ch, CURLOPT_TIMEOUT,			15);

	//CURLOPT_FTP_FILEMETHOD?

	if (!$use_pasv)
		curl_setopt($ch, CURLOPT_FTPPORT, '-');

	$fp = fopen($ftp_local_file, 'w');
	if (!$fp)
	{
		echo "Unable to open $ftp_local_file for writing\n";
		return 6;
	}

	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_FILE, $fp);

	$result = curl_exec($ch);

	$exec_code = 0;
	if ($result === false)
	{
		echo "curl_exec error: ".curl_error($ch)."\n";
		$exec_code = 7;
	}
	else
	if(strlen($result) && $result!="1")
		echo $result."\n";

	fclose($fp);

	return $exec_code;
}

?>
