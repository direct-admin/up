#!/usr/bin/perl

#VERSION=14

sub get_domain_owner
{
	my ($domain) = @_;
	my $username="";
	open(DOMAINOWNERS,"/etc/virtual/domainowners");
	while (<DOMAINOWNERS>)
	{
		$_ =~ s/\n//;
		my ($dmn,$usr) = split(/: /, $_);
		if ($dmn eq $domain)
		{
			close(DOMAINOWNERS);
			return $usr;
		}
	}
	close(DOMAINOWNERS);

	return -1;
}

# hit_limit_user
# checks to see if a username has hit the send limit.
# returns:
#	-1 for "there is no limit"
#	0  for "still under the limit"
#	1  for "at the limit"
#	2  for "over the limit"

sub hit_limit_user
{
	my($username) = @_;

	my $count = 0;
	my $email_limit = 0;

	if (open (LIMIT, "/etc/virtual/limit_$username"))
	{
		$email_limit = int(<LIMIT>);
		close(LIMIT);
	}
	else
	{
		open (LIMIT, "/etc/virtual/limit");
		$email_limit = int(<LIMIT>);
		close(LIMIT);
	}

	if ($email_limit > 0)
	{
		#check this users limit
		$count = (stat("/etc/virtual/usage/$username"))[7];

		#this is their last email.
		if ($count == $email_limit)
		{
			return 1;
		}

		if ($count > $email_limit)
		{
			return 2;
		}

		return 0;
	}

	return -1;
}

# hit_limit_email
# same idea as hit_limit_user, except we check the limits (if any) for per-email accounts.

sub hit_limit_email
{
	my($user,$domain) = @_;

	my $user_email_limit = 0;
	if (open (LIMIT, "/etc/virtual/$domain/limit/$user"))
	{
		$user_email_limit = int(<LIMIT>);
		close(LIMIT);
	}
	else
	{
		if (open (LIMIT, "/etc/virtual/user_limit"))
		{
			$user_email_limit = int(<LIMIT>);
			close(LIMIT);
		}
	}

	if ($user_email_limit > 0)
	{
		my $count = 0;
		$count = (stat("/etc/virtual/$domain/usage/$user"))[7];
		if ($count == $user_email_limit)
		{
			return 1;
		}
		if ($count > $user_email_limit)
		{
			return 2;
		}
		return 0;
	}

	return -1;
}

#smtpauth
#called by exim to verify if an smtp user is allowed to
#send email through the server
#possible success:
# user is in /etc/virtual/domain.com/passwd and password matches
# user is in /etc/passwd and password matches in /etc/shadow

sub smtpauth
{
	$username	= Exim::expand_string('$1');
	$password	= Exim::expand_string('$2');
	$extra		= Exim::expand_string('$3');
	$domain		= "";
	$unixuser	= 1;

	#check for netscape that offsets the login/pass by one
	if ($username eq "" && length($extra) > 0)
	{
		$username = $password;
		$password = $extra;
	}

	if ($username =~ /\@/)
	{
		$unixuser = 0;
		($username,$domain) = split(/\@/, $username);
		if ($domain eq "") { return "no"; }
	}

	if ($unixuser == 1)
	{
		#the username passed doesn't have a domain, so its a system account
		$homepath = (getpwnam($username))[7];
		if ($homepath eq "") { return 0; }
		open(PASSFILE, "< $homepath/.shadow") || return "no";
		$crypted_pass = <PASSFILE>;
		close PASSFILE;

		if ($crypted_pass eq crypt($password, $crypted_pass))
		{
			my $limit_check = hit_limit_user($username);
			if ($limit_check > 1)
			{
				die("The email send limit for $username has been reached\n");
			}

			return "yes";
		}
		else { return "no"; }
	}
	else
	{
		#the username contain a domain, which is now in $domain.
		#this is a pure virtual pop account.

		open(PASSFILE, "< /etc/virtual/$domain/passwd") || return "no";
		while (<PASSFILE>)
		{
			($test_user,$test_pass) = split(/:/,$_);
			$test_pass =~ s/\n//g; #snip out the newline at the end
			if ($test_user eq $username)
			{
				if ($test_pass eq crypt($password, $test_pass))
				{
					close PASSFILE;

					my $domain_owner = get_domain_owner($domain);
					if ($domain_owner != -1)
					{
						my $limit_check = hit_limit_user($domain_owner);
						if ($limit_check > 1)
						{
							die("The email send limit for $domain_owner has been reached\n");
						}

						$limit_check = hit_limit_email($username, $domain);
						if ($limit_check > 1)
						{
							die("The email send limit for $username\@${domain} has been reached\n");
						}
					}

					return "yes";
				}
			}
		}
		close PASSFILE;
		return "no";
	}

	return "no";
}

sub find_uid_apache
{
	my ($work_path) = @_;
	my @pw;
	
	# $pwd will probably look like '/home/username/domains/domain.com/public_html'
	# it may or may not use /home though. others are /usr/home, but it's ultimately
	# specified in the /etc/passwd file.  We *could* parse through it, but for efficiency
	# reasons, we'll only check /home and /usr/home ..   if they change it, they can
	# manually adjust if needed.

	@dirs = split(/\//, $work_path);
	foreach $dir (@dirs)
	{
		# check the dir name for a valid user
		# get the home dir for that user
		# compare it with the first part of the work_path

		if ( (@pw = getpwnam($dir))  )
		{
			if ($work_path =~/^$pw[7]/)
			{
				return $pw[2];
			}
		}
	}
	return -1;
}

sub find_uid_auth_id
{
	# this will be passwed either
	# 'username' or 'user@domain.com'

	my ($auth_id) = @_;
	my $unixuser = 1;
	my $domain = "";
	my $user = "";
	my $username = $auth_id;
	my @pw;

	if ($auth_id =~ /\@/)
	{
		$unixuser = 0;
		($user,$domain) = split(/\@/, $auth_id);
		if ($domain eq "") { return "-1"; }
        }

	if (!$unixuser)
	{
		# we need to take $domain and get the user from /etc/virtual/domainowners
		# once we find it, set $username
		my $u = get_domain_owner($domain);;
		if ($u != -1)
		{
			$username = $u;
		}
	}

	#log_str("username found from $auth_id: $username:\n");

	if ( (@pw = getpwnam($username))  )
	{
		return $pw[2];
	}

	return -1;
}

sub find_uid_sender
{
	my $sender_address = Exim::expand_string('$sender_address');

	my ($user,$domain) = split(/\@/, $sender_address);

	my $primary_hostname = Exim::expand_string('$primary_hostname');
	if ( $domain eq $primary_hostname )
	{
		@pw = getpwnam($user);
		return $pw[2];
	}

	my $username = get_domain_owner($domain);

	if ( (@pw = getpwnam($username))  )
	{
		return $pw[2];
	}

	return -1;
}

sub find_uid
{
        my $uid = Exim::expand_string('$originator_uid');
	my $username = getpwuid($uid);
        my $auth_id = Exim::expand_string('$authenticated_id');
        my $work_path = $ENV{'PWD'};

	if ($username eq "apache" || $username eq "nobody" || $username eq "webapps")
	{
		$uid = find_uid_apache($work_path);
		if ($uid != -1) { return $uid; }
	}
	
	$uid = find_uid_auth_id($auth_id);
	if ($uid != -1) { return $uid; }

	# we don't want to rely on this, but it's all thats left.
	return find_uid_sender;
}

sub uid_exempt
{
        my ($uid) = @_;
        if ($uid == 0) { return 1; }

        my $name = getpwuid($uid);
        if ($name eq "root") { return 1; }
        if ($name eq "diradmin") { return 1; }

        return 0;
}


#check_limits
#used to enforce limits for the number of emails sent
#by a user.  It also logs the bandwidth of the data
#for received mail.

sub check_limits
{
	#find the curent user
	$uid = find_uid();

	#log_str("Found uid: $uid\n");

	if (uid_exempt($uid)) { return "yes"; }

	my $name="";

	#check this users limit
	$name = getpwuid($uid);

	if (!defined($name))
	{
		#possibly the sender-verify
		$name = "unknown";
		#return "yes";
	}

	my $count = 0;
	my $email_limit = 0;
	if (open (LIMIT, "/etc/virtual/limit_$name"))
	{
		$email_limit = int(<LIMIT>);
		close(LIMIT);
	}
	else
	{
		open (LIMIT, "/etc/virtual/limit");
		$email_limit = int(<LIMIT>);
		close(LIMIT);
	}

	my $sender_address 	= Exim::expand_string('$sender_address');
	my $authenticated_id	= Exim::expand_string('$authenticated_id');
	my $sender_host_address	= Exim::expand_string('$sender_host_address');
	my $mid 		= Exim::expand_string('$message_id');
	my $message_size	= Exim::expand_string('$message_size');
	my $local_part		= Exim::expand_string('$local_part');
	my $domain		= Exim::expand_string('$domain');
	my $timestamp		= time();
	my $is_retry = 0;

	if ($email_limit > 0)
	{
		#check this users limit
		$count = (stat("/etc/virtual/usage/$name"))[7];

		if ($count > $email_limit)
		{
			die("You ($name) have reached your daily email limit of $email_limit emails\n");
		}

		if ($mid ne "")
		{
			if (! -d "/etc/virtual/usage/${name}_ids")
			{
				mkdir("/etc/virtual/usage/${name}_ids", 0770);
			}

			my $mid_char = substr($mid, 0, 1);

			if (! -d "/etc/virtual/usage/${name}_ids/$mid_char")
			{
				mkdir("/etc/virtual/usage/${name}_ids/$mid_char", 0770);
			}

			my $id_file = "/etc/virtual/usage/${name}_ids/$mid_char/$mid";

			if (-f $id_file)
			{
				$is_retry = 1;
			}
			else
			{
				open(IDF, ">>$id_file");
				print IDF "log_time=$timestamp\n";
				close(IDF);
				chmod (0660, $id_file);
			}
		}

		#this is their last email.
		if (($count == $email_limit) && ($is_retry != 1))
		{
			#taddle on the dataskq
			#note that the sender_address here is only the person who sent the last email
			#it doesnt meant that they have sent all the spam
			#this action=limit will trigger a check on usage/user.bytes, and DA will try and figure it out.
			open(TQ, ">>/etc/virtual/mail_task.queue");
			print TQ "action=limit&username=$name&count=$count&limit=$email_limit&email=$sender_address&authenticated_id=$authenticated_id&sender_host_address=$sender_host_address&log_time=$timestamp\n";
			close(TQ);
			chmod (0660, "/etc/virtual/mail_task.queue");
		}

		if ($is_retry != 1)
		{
			open(USAGE, ">>/etc/virtual/usage/$name");
			print USAGE "1";
			close(USAGE);
			chmod (0660, "/etc/virtual/usage/$name");
		}
	}

	if ( ($authenticated_id ne "") && ($is_retry != 1) )
	{
		my $user="";
		my $domain="";
		($user, $domain) = (split(/@/, $authenticated_id));

		if ($domain ne "")
		{
			my $user_email_limit = 0;
			if (open (LIMIT, "/etc/virtual/$domain/limit/$user"))
			{
				$user_email_limit = int(<LIMIT>);
				close(LIMIT);
			}
			else
			{
				if (open (LIMIT, "/etc/virtual/user_limit"))
				{
					$user_email_limit = int(<LIMIT>);
					close(LIMIT);
				}
			}

			if ($user_email_limit > 0)
			{
				$count = 0;
				$count = (stat("/etc/virtual/$domain/usage/$user"))[7];

				if ($count == $user_email_limit)
				{
					open(TQ, ">>/etc/virtual/mail_task.queue");
					print TQ "action=userlimit&username=$name&count=$count&limit=$user_email_limit&email=$sender_address&authenticated_id=$authenticated_id&sender_host_address=$sender_host_address&log_time=$timestamp\n";
					close(TQ);
					chmod (0660, "/etc/virtual/mail_task.queue");
				}

				if ($count > $user_email_limit)
				{
					die("Your E-Mail ($authenticated_id) has reached it's daily email limit of $user_email_limit emails\n");
				}

				if (! -d "/etc/virtual/$domain/usage")
				{
					mkdir("/etc/virtual/$domain/usage", 0770);
				}

				if (-d "/etc/virtual/$domain/usage")
				{
					open(USAGE, ">>/etc/virtual/$domain/usage/$user");
					print USAGE "1";
					close(USAGE);
					chmod (0660, "/etc/virtual/$domain/usage/$user");
				}
			}
		}
	}

	log_bandwidth($uid,"type=email&email=$sender_address&method=outgoing&id=$mid&authenticated_id=$authenticated_id&sender_host_address=$sender_host_address&log_time=$timestamp&message_size=$message_size&local_part=$local_part&domain=$domain");

	return "yes"
}

sub log_email
{
	my($lp,$dmn) = @_;

	#log_str("logging $lp\@$dmn\n");
	my $user = get_domain_owner($dmn);
	if ($user == -1) { return "no"; }

	my $mid = Exim::expand_string('$message_id');

	if ( (@pw = getpwnam($user))  )
	{
		log_bandwidth($pw[2],"type=email&email=$lp\@$dmn&method=incoming&id=$mid");
	}

	return "yes";
}

sub save_virtual_user
{
	my $dmn = Exim::expand_string('$domain');
	my $lp  = Exim::expand_string('$local_part');
	my $usr = "";
	my $pss = "";
	my $entry = "";

	open (PASSWD, "/etc/virtual/$dmn/passwd") || return "no";

	while ($entry = <PASSWD>) {
		($usr,$pss) = split(/:/,$entry);
		if ($usr eq $lp) {
			close(PASSWD);
			log_email($lp, $dmn);
			return "yes";
		}
	}
	close (PASSWD);

	return "no";
}

sub log_bandwidth
{
	my ($uid,$data) = @_;
	my $name = getpwuid($uid);

	if (uid_exempt($uid)) { return; }

	if ($name eq "") { $name = "unknown"; }

	my $bytes = Exim::expand_string('$message_size');

	if ($bytes == -1) { return; }

	my $work_path = $ENV{'PWD'};

	open (BYTES, ">>/etc/virtual/usage/$name.bytes");
	print BYTES "$bytes=$data&path=$work_path\n";
	close(BYTES);
	chmod (0660, "/etc/virtual/usage/$name.bytes");
}

sub log_str
{
	my ($str) = @_;

	open (LOG, ">> /tmp/test.txt");

	print LOG $str;

	close(LOG);
}
