# ******************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# ******************************************************************************************
package PFADMIN::DAO::MailboxDAO;

use strict;

use POSIX qw(strftime);
use Log::Log4perl;
use File::Basename;
use JSON qw(from_json);
use DBM::Deep;
use Wstk::Boolean;
use Wstk::WstkDefs qw(:ALL);
use Wstk::WstkException;
use Wstk::EntityHelper;
use Wstk::SearchFilterHelper;
use Wstk::Models::SearchFilter;
use PFADMIN::Defs qw(:ALL);
use PFADMIN::IOHelper;
use PFADMIN::Models::Mailbox;

use constant ENTITY_CLASS_NAME => PFADMIN::Models::Mailbox::CLASS_NAME;
use constant LIST_DEFAULT_LIMIT => 250;

sub new ($$;$) {
	my ( $class, $pfadmin) = @_;
	my $self = {
		logger          	=> Log::Log4perl::get_logger(__PACKAGE__),
		class_name      	=> $class,
		pfadmin         	=> $pfadmin,
		wstk				=> $pfadmin->{wstk},
		cf1_file			=> $pfadmin->get_config('postfix','mailboxes_db'),
		cf2_file			=> $pfadmin->get_config('postfix','mailboxes_pw_db'),
		maildir_path		=> $pfadmin->get_config('postfix','maildir_path'),		
		mailbox_base_path	=> $pfadmin->get_config('postfix','mailbox_base'),
		mailbox_uid        	=> $pfadmin->get_config('postfix','mailbox_uid', 0),
		mailbox_gid        	=> $pfadmin->get_config('postfix','mailbox_gid', 0),
		mailbox_chmod      	=> '0700',
		use_chown			=> 1,
		backup_path			=> undef,
		db_path				=> undef,
		db_file				=> undef,
		id_file				=> undef
	};
	bless( $self, $class );
	#
	$self->{db_path} = $self->{pfadmin}->dao_lookup('DomainsDAO')->get_db_path();
	$self->{backup_path} = $self->{pfadmin}->dao_lookup('DomainsDAO')->get_backup_path();
	$self->{db_file} = $self->{db_path}.'/mailboxes.db';
	$self->{id_file} = $self->{db_path}.'/mailboxes.id';
	#
	if(!$self->{db_path} || !$self->{backup_path}) {
		die Wstk::WstkException->new("db_path or backup_path is incorrect");
	}
	unless(-d $self->{db_path} || -d $self->{backup_path}) {		
		die Wstk::WstkException->new("db_path or backup_path not exist");
	}	
	unless(-e $self->{cf1_file}) {
		die Wstk::WstkException->new("Missing data file: " + $self->{cf1_file});
	}
	unless(-e $self->{cf2_file}) {
		die Wstk::WstkException->new("Missing data file: " + $self->{cf2_file});
	}
	unless(defined $self->{mailbox_base_path}) {
		die Wstk::WstkException->new("Missing property: postfix.mailbox_base");
	}
	unless($self->is_sync_label_valid()) {
		$self->sync_db();
	}
	#
	$self->{logger}->debug('mailbox_base: '.$self->{mailbox_base_path});
	#
	return $self;
}

sub get_class_name {
	my ($self) = @_;
	return $self->{class_name};
}


# ---------------------------------------------------------------------------------------------------------------------------------
# public methods
# ---------------------------------------------------------------------------------------------------------------------------------
sub add {
	my ($self, $entity) = @_;	
	my $err = undef;
	#
    unless($self->is_entity_valid($entity)) {
    	die Wstk::WstkException->new("entity", RPC_ERR_CODE_INVALID_ARGUMENT);
	}
	#
	my $domain = $self->{pfadmin}->dao_lookup('DomainsDAO')->get($entity->domainId());
	unless($domain) {
		die Wstk::WstkException->new($entity->domainId(), RPC_ERR_CODE_NOT_FOUND);
	}
	#
	if(index($entity->name, "@") < 0 ) {
		$entity->name(lc($entity->name() .'@'. $domain->name()));
	} else {
		my ($name, $domain) = split(/\@/, lc($entity->name()), 2);
		$entity->name(lc($name.'@'.$domain->name()));
	}
	#
	$entity->domainId($domain->name());	
	$entity->path($entity->name().$self->{maildir_path});
	$entity->xpath($entity->domainId().'/'.$entity->name());
	$entity->quota(int($entity->quota()));
	$entity->description($entity->description() ? $entity->description() : '');
	$entity->title($entity->title() ? $entity->title() : '');
	$entity->enabled(is_true($entity->enabled()) ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
	#
	my $pwhash = $self->get_pw_hash($entity->name(), $entity->password());
	if(!defined($pwhash) || $pwhash eq $entity->password()) {
		die Wstk::WstkException->new("Couldn't create password hash");
	}	
	$entity->password($pwhash);
	#
	my $db = $self->db_open();
	my $id = $entity->name();
	$db->lock();
	if(exists($db->{$id})) {
		$err = Wstk::WstkException->new($id , RPC_ERR_CODE_ALREADY_EXISTS);
		goto out;
	}
	$db->{$id} = $entity;
out:
	$db->unlock();
	if($err) { die $err; }
	# create mailbox dir
	mkdir_local($self, $entity->xpath());
	#
	return $entity;	
}

sub update {
	my ($self, $entity) = @_;
	my $err = undef;
	#
    unless($self->is_entity_valid($entity)) {
		die Wstk::WstkException->new("entity", RPC_ERR_CODE_INVALID_ARGUMENT);
	}
	#
	my $db = $self->db_open();
	my $id = lc($entity->name());
	$db->lock();
	my $obj = $db->{$id};
	unless($obj) {
		$err = Wstk::WstkException->new($id, RPC_ERR_CODE_NOT_FOUND);
		goto out;
	}
	#
	$obj->enabled(is_true($entity->enabled()) ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
	$obj->description($entity->description() ? $entity->description() : '');
	$obj->title($entity->title() ? $entity->title() : '');
	$obj->quota(int($entity->quota()));
	#
	if($entity->password() ne $obj->password()) {
		my $pwhash = $self->get_pw_hash($obj->name(), $entity->password());
		if(!defined($pwhash) || $pwhash eq $entity->password()) {
			die Wstk::WstkException->new("Couldn't create password hash");
		}	
		$obj->password($pwhash);
	}
	$db->{$id} = $obj;
out:
	$db->unlock();
	if($err) { die $err; }
	return $obj;
}

sub delete {
	my ($self, $entity_id) = @_;	
	#
   	unless(defined $entity_id) {
        die Wstk::WstkException->new("entity_id", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
	#
	my $entity = undef;
	my $id = lc($entity_id);
	my $db = $self->db_open();
	$db->lock();
	if(exists($db->{$id})) {
		$entity = delete($db->{$id});
	}
	$db->unlock();
	# delete mailbox dir
	if($entity && $self->{mailbox_base_path}) {
		my $path = $self->{mailbox_base_path}.'/'.$entity->xpath();		
		if(-d $path) {
			system("doveadm kick ".$entity->name());
			system('rm -rf '.$path);
		}
	}
	return 1;
}

sub delete_by_domain {
	my ($self, $domain_id) = @_;	
	#
   	unless(defined $domain_id) {
        die Wstk::WstkException->new("domain_id", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
	#
	my $db = $self->db_open();
	$db->lock();
	foreach my $id (keys %{$db}) {
		my $obj = $db->{$id};
		if($obj->domainId() eq $domain_id) {
			delete $db->{$id};
		}
	}	
	$db->unlock();
	return 1;
}

sub get {
	my ($self, $entity_id) = @_;		
	my $entity = undef;
	my $err = undef;
	#
   	unless(defined $entity_id) {
        die Wstk::WstkException->new("entity_id", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    #
	my $db = $self->db_open();
	$db->lock();	
	$entity = $db->{ lc($entity_id) };	
	$db->unlock();	
	return $entity;
}

sub list {
	my ($self, $domain_id, $filter) = @_;
	my ($ftext, $fstart, $fcount) = (undef, 0, LIST_DEFAULT_LIMIT);
	my $result = [];	
	#
 	my $ftext = filter_get_text($filter);
	my $fstart = filter_get_offset($filter);
	my $fcount = filter_get_limit($filter);
	#
	my $db = $self->db_open();
	$db->lock();
	foreach my $mbox (keys %{$db}) {
		my $obj = $db->{$mbox};
		if(!$obj || ($domain_id && $obj->domainId() ne $domain_id)) { next; }

		if($fstart > 0) { $fstart--; next; }		
		if($fcount > 0) { $fcount--; } else { last; }

		unless($ftext) {
			push(@{$result}, $obj);
			next;
		} 
		if($obj->name() =~ m/\Q$ftext/) {
			push(@{$result}, $obj);
		}
	}	
	$db->unlock();
	# 
	my @srt = sort { $a->{name} cmp $b->{name} } @{$result};
	return \@srt;
}

sub sync_db {
	my ($self) = @_;		
	my $err = undef;
	my %mailboxes;
	#	
	my $db = $self->db_open(); 
	$db->lock_exclusive();
	unless(-e $self->{cf1_file}) {
		$err = Wstk::WstkException->new("File not found: ".$self->{cf1_file});
		goto out;
	}
	unless(-e $self->{cf2_file}) {
		$err = Wstk::WstkException->new("File not found: ".$self->{cf2_file});
		goto out;
	}
	#
	open(my $fh, "<".$self->{cf1_file});
	unless($fh) {
		$err = Wstk::WstkException->new("Couldn't read file: ".$self->{cf1_file});
		goto out;
	}
	while(<$fh>) {
		next if($_ =~ /^#.*/ || length($_) <= 2);
		my $ln = $_; chomp($ln);
		my ($mbox, $path) = split(/\s+/, $ln, 2);
		$mbox = lc($mbox);
		my ($title, $domain) = split(/\@/, $mbox, 2);		
		my $obj = PFADMIN::Models::Mailbox->new(
					enabled  	=> Wstk::Boolean::TRUE,
					domainId 	=> $domain,
					name	 	=> $mbox,
					title 	 	=> $title,
					path	 	=> $path,
					xpath		=> $domain.'/'.$mbox,
					quota		=> 0,
					description => ''
				);
		$mailboxes{$mbox} = $obj;
	}
	close($fh);	
	#
	open(my $fh, "<".$self->{cf2_file});
	unless($fh) {
		$err = Wstk::WstkException->new("Couldn't read file: ".$self->{cf2_file});
		goto out;
	}
	while(<$fh>) {
		next if($_ =~ /^#.*/ || length($_) <= 2);
		my $ln = $_; chomp($ln);
		my ($mbox, $pass, $ep1, $ep2, $ep3, $ep4, $ep5, $epx) = split(/\:/, $ln, 8);
		$mbox = lc($mbox);
		unless(exists($mailboxes{$mbox})) {
			$self->{logger}->warn("Unknown mailbox: ".$mbox." (skipped)");
			next;
		}
		my $obj = $mailboxes{$mbox};
		$obj->password($pass);
		if($epx =~ /storage=(\d+)/) {
			$obj->quota($1);
		}
		unless(exists($db->{$mbox})) {
			$db->{$mbox} = $obj;			
		}		
	}	
	close($fh);		
	foreach my $id (keys %{$db}) {
		unless(exists($mailboxes{$id})) {
			my $obj = $db->{$id};
			$obj->enabled(Wstk::Boolean::FALSE);			
			$db->{$id} = $obj;
		} else {
			my $obj = $db->{$id};
			mkdir_local($self, $obj->xpath());
		}		
	}
	# update sync label
	$self->sync_label_store(
		$self->sync_label_get_original()
	);
	$self->{logger}->debug("mailboxes DB has been synchronized");
out:
	$db->unlock();
	if($err) { die $err; }
	return 1;
}

sub sync_data {
	my ($self) = @_;	
	my $oldfn1 = undef;
	my $oldfn2 = undef;
	my $restoreOld = 0;	
	my $err = undef;
	#
	my $backup_enable = $self->{pfadmin}->get_config('etc','backup_data');
	if($backup_enable eq 'true') {
		my $backup_ext = strftime("%d%m%Y", localtime);
		my ($dfile1) = (fileparse($self->{cf1_file}))[0];
		my ($dfile2) = (fileparse($self->{cf2_file}))[0];	
		$oldfn1 = $self->{backup_path}.'/'.$dfile1."_".$backup_ext;
		$oldfn2 = $self->{backup_path}.'/'.$dfile2."_".$backup_ext;
		rename($self->{cf1_file}, $oldfn1);
		rename($self->{cf2_file}, $oldfn2);
		$restoreOld = 1;
	}
	#
	open(my $fh1, ">".$self->{cf1_file});
	unless($fh1) {$err = Wstk::WstkException->new("Couldn't open file: ".$self->{cf1_file}); goto out; }
	open(my $fh2, ">".$self->{cf2_file});
	unless($fh2) {$err = Wstk::WstkException->new("Couldn't open file: ".$self->{cf2_file}); goto out; }

	print($fh1  "#\n# generated at: " . localtime() . "\n#\n");
	print($fh2  "#\n# generated at: " . localtime() . "\n#\n");

	#
	my $db = $self->db_open();
	$db->lock_exclusive();
	foreach my $id (keys %{$db}) {
		my $obj = $db->{$id};
		if(is_true($obj->enabled())) {
			print($fh1  $obj->name() ." ".$obj->path()."\n");
			print($fh2  $obj->name() .':'.$obj->password().'::::::'.($obj->quota() ? "userdb_quota_rule=*:storage=".$obj->quota().'G' : "")."\n");
		}
	}
	close($fh1);
	close($fh2);

	#
	$self->sync_label_store(
		$self->sync_label_get_original()
	);
	$self->{logger}->debug("mailboxes map has been synchronized");
out:	
	$db->unlock();
	if($err) {
		if($restoreOld) {
			rename($oldfn1, $self->{cf1_file});
			rename($oldfn2, $self->{cf2_file});
		}
		die $err;
	}
	return 1;
}

sub do_postmap {
	my ($self) = @_;
	
	my $cmd = 'postmap '.$self->{cf1_file}.' > /dev/null';
	system($cmd);
	
    my $res = $?;
    if ($res == -1) {
		my $err = $!;
		die Wstk::WstkException->new("postmap (".$self->{cf1_file}."), error: ".$err);
    }	
	return 1;
}

sub get_pw_hash {
	my ($self, $user, $pw) = @_;
	my $tmpfn = $self->{wstk}->get_path('tmp').'/.ttx'.time();
	system("doveadm pw -p '".$pw."' -s SHA512-CRYPT -u ".$user.' > '.$tmpfn);
    my $res = $?;
    if ($res == -1) {
		my $err = $!;
		$self->{logger}->error("doveadm fail: ".$err);
		unlink($tmpfn);
		return undef;
    }
	open(my $x, "<".$tmpfn) || return undef;
	my $res = <$x>; close($x); chomp($res);
	unlink($tmpfn);	
	return $res;
}

sub get_status {
	my ($self, $mbox) = @_;
	my $found = 0;
	#
	if(is_empty($mbox)) {
		die Wstk::WstkException->new('mbox', RPC_ERR_CODE_INVALID_ARGUMENT );		
	}
	$mbox = lc($mbox);	
	#
	my $db = $self->db_open();
	$db->lock();
	$found = exists($db->{$mbox});
	$db->unlock();
	#
	unless($found) {
		die Wstk::WstkException->new($mbox, RPC_ERR_CODE_NOT_FOUND);
	}
	my $tmpfn = $self->{wstk}->get_path('tmp').'/.ttst'.time();	
	system("doveadm -fjson mailbox status -u ".$mbox." all INBOX > ".$tmpfn.' 2>&1');
    my $res = $?;
    if ($res == -1) {
		my $err = $!;
		die Wstk::WstkException->new($err);
    }	
	open(my $x, "<".$tmpfn) || return undef;
	my $res = <$x>; close($x); chomp($res);
	unlink($tmpfn);
	#
	if($res =~ /Error:\s(.*)/ ) {
		die Wstk::WstkException->new('doveadm: '.$1);
	}
	return from_json($res);
}

# ---------------------------------------------------------------------------------------------------------------------------------
# private methods
# ---------------------------------------------------------------------------------------------------------------------------------
sub is_entity_valid {
	my ($self, $entity) = @_;	    
 	unless ($entity) {
        die Wstk::WstkException->new("entity", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    unless(entity_instance_of($entity, ENTITY_CLASS_NAME)) {
        die Wstk::WstkException->new("Type mismatch: " . entity_get_class($entity) . ", require: " . ENTITY_CLASS_NAME);
    }
	if(is_empty($entity->domainId())) {
		die Wstk::WstkException->new('Invalid property: domainId', RPC_ERR_CODE_INVALID_ARGUMENT);
	}
	if(is_empty($entity->name())) {
		die Wstk::WstkException->new('Invalid property: name', RPC_ERR_CODE_INVALID_ARGUMENT);
	}
    if($entity->name() !~ /^([a-zA-Z0-9\.\_\@])+$/) {
        die Wstk::WstkException->new("Invalid property: name", RPC_ERR_CODE_VALIDATION_FAIL);
    }
	if(is_empty($entity->password())) {
		die Wstk::WstkException->new('Invalid property: password', RPC_ERR_CODE_INVALID_ARGUMENT);
	}
	return 1;
}

sub mkdir_local {
	my ($self, $name) = @_;	
	if($self->{mailbox_base_path}) {
		my $path = $self->{mailbox_base_path}.'/'.$name;
		unless(-d $path) {
			mkdir($path);
			if($self->{use_chown}) {
				chown($self->{mailbox_uid}, $self->{mailbox_gid}, $path) if($self->{mailbox_uid});
				chmod(oct($self->{mailbox_chmod}), $path) if($self->{mailbox_chmod});
			}
		}
	}
	return 1;
}

sub sync_label_get_original {
	my ($self) = @_;	
	return io_get_file_lastmod($self->{cf1_file});
}

sub sync_label_get_stored {
	my ($self) = @_;		
	open(my $x, "<".$self->{id_file}) || return 0;
	my $ts = <$x>; close($x);
	chomp($ts);	
	return $ts;
}

sub sync_label_store {
	my ($self, $ts) = @_;
	open(my $x, ">" . $self->{id_file}) || return 0;
	print($x $ts."\n" );
	close($x);
	return 1;
}

sub is_sync_label_valid {
	my ($self) = @_;
	my $ots = $self->sync_label_get_original();
	my $cts = $self->sync_label_get_stored();
	return ($cts > 0 && $ots == $cts);
}

sub db_open {
	my ($self) = @_;
	return DBM::Deep->new(file => $self->{db_file}, locking => 0, autoflush => 1);
}

1;
