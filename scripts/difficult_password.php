#!/usr/local/bin/php
<?php

/*
This script is to enforce a level of password difficulty that users must use.
You can change the minimum length if you wish, the default is 6.
The requirement for special characters is disabled by default.

Related directadmin.conf options:
- difficult password enforcement: http://www.directadmin.com/features.php?id=910
- enable shift chars: https://www.directadmin.com/features.php?id=1625
- min password length: http://www.directadmin.com/features.php?id=1176
- random password length: http://www.directadmin.com/features.php?id=1604
- ajax password checking/generation: http://www.directadmin.com/features.php?id=1560
*/


$min_length = getenv("difficult_password_length_min");
$pass = getenv("password");
$random_password_length = getenv("random_password_length");
$special_characters_in_random_passwords = getenv("special_characters_in_random_passwords");

if ($random_password_length < $min_length)
{
	$min_length = $random_password_length;
}


//FUNCTION CALL section

check_length($pass);
enforce_mixed_case($pass);
enforce_numbers($pass);

if ($special_characters_in_random_passwords)
	enforce_shift_chars($pass);

//FUNCTION CALL section, end

//passes the test
echo "Password OK\n";

exit(0);


function enforce_shift_chars($str)
{
	if (!has_shift_chars($str))
	{
		echo "Password must have at least one special character such as !@#%$ etc..\n";
		exit(3);
	}
}

function enforce_numbers($str)
{
	if (!has_numbers($str))
	{
		echo "Password must have numbers\n";
		exit(4);
	}
}

function enforce_mixed_case($str)
{
	if (!has_caps($str) || !has_lower_case($str))
	{
		echo "Password must have both upper and lower case characters\n";
		exit(2);
	}
}

function check_length($str)
{
	global $min_length;
	$len = strlen($str);
	if ($len < $min_length)
	{
		echo "Password is too short ($len).  Use at least $min_length characters\n";
		exit(1);
	}
}

function has_shift_chars($str)
{
	//return preg_match("/[\~\!\@\#\$\%\^\&\*\(\)\-\=\_\+\{\}\:\;\|\<\>\,\.\?\/]+/", $str);
	$len = strlen($str);
	$num_count=0;
	for ($i=0; $i<$len; $i++)
	{
		$ch=$str[$i];
		if ('!' <= $ch && $ch <= '/')
		{
			$num_count++;
		}
		if (':' <= $ch && $ch <= '@')
		{
			$num_count++;
		}
		if ('[' <= $ch && $ch <= '`')
		{
			$num_count++;
		}
		if ('{' <= $ch && $ch <= '~')
		{
			$num_count++;
		}
	}
	return $num_count;
}

function has_numbers($str)
{
	return preg_match("/[0-9]+/", $str);
}

function has_caps($str)
{
	return preg_match("/[A-Z]+/", $str);
}

function has_lower_case($str)
{
	return preg_match("/[a-z]+/", $str);
}

exit(0);

?>
