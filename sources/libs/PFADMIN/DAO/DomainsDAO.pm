# ******************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# ******************************************************************************************
package PFADMIN::DAO::DomainsDAO;

use strict;

use POSIX qw(strftime);
use Log::Log4perl;
use DBM::Deep;
use File::Basename;
use Wstk::Boolean;
use Wstk::WstkDefs qw(:ALL);
use Wstk::WstkException;
use Wstk::EntityHelper;
use Wstk::SearchFilterHelper;
use Wstk::Models::SearchFilter;
use PFADMIN::Defs qw(:ALL);
use PFADMIN::IOHelper;
use PFADMIN::Models::Domain;

use constant ENTITY_CLASS_NAME => PFADMIN::Models::Domain::CLASS_NAME;
use constant LIST_DEFAULT_LIMIT => 250;

sub new ($$;$) {
	my ( $class, $pfadmin) = @_;
	my $self = {
		logger          	=> Log::Log4perl::get_logger(__PACKAGE__),
		class_name      	=> $class,
		pfadmin         	=> $pfadmin,
		cf_file				=> $pfadmin->get_config('postfix','domains_db'),
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
	my ($db_base) = (fileparse($self->{cf_file}))[1];
	$self->{db_path} = $db_base.'pfadmin';
	$self->{backup_path} = $self->{db_path}.'/backups';
	$self->{db_file} = $self->{db_path}.'/domains.db';
	$self->{id_file} = $self->{db_path}.'/domains.id';
	#
	unless(-d $self->{db_path}) {
		mkdir($self->{db_path});
	}
	unless(-d $self->{backup_path}) {
		mkdir($self->{backup_path});
	}
	unless(-e $self->{cf_file}) {
		die Wstk::WstkException->new("Missing data file: ".$self->{cf_file});
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

sub get_db_path {
	my ($self) = @_;
	return $self->{db_path};
}

sub get_backup_path {
	my ($self) = @_;
	return $self->{backup_path};
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
	$entity->name(lc($entity->name()));
	#
	my $id = $entity->name();
	my $db = $self->db_open();
	$db->lock();
	if(exists($db->{$id})) {
		$err = Wstk::WstkException->new($id , RPC_ERR_CODE_ALREADY_EXISTS);
		goto out;
	}
	$entity->description($entity->description() ?  $entity->description() : '');
	$db->{$id} = $entity;
out:
	$db->unlock();
	if($err) { die $err; }
	# create domain dir
	mkdir_local($self, $entity->name());
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
	my $id = lc($entity->name());
	my $db = $self->db_open();
	$db->lock();
	my $obj = $db->{$id};
	unless($obj) {
		$err = Wstk::WstkException->new($id, RPC_ERR_CODE_NOT_FOUND);
		goto out;
	}
	$obj->description($entity->description());
	$db->{$id} = $obj;
out:
	$db->unlock();
	if($err) { die $err; }
	return $obj;
}

sub delete {
	my ($self, $entity_id) = @_;	
	my $err = undef;
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
		# related objects
		$self->{pfadmin}->dao_lookup('AliasDAO')->delete_by_domain($id);
		$self->{pfadmin}->dao_lookup('MailboxDAO')->delete_by_domain($id);		
	}	
	$db->unlock();
	# delete domain dir
	if($entity && $self->{mailbox_base_path}) {
		my $path = $self->{mailbox_base_path}.'/'.$entity->name();
		if(-d $path) {
			system("doveadm kick *@".$entity->name());
			system('rm -rf '.$path);
		}
	}
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
	#
	return $entity;
}

sub list {
	my ($self, $filter) = @_;
	my ($ftext, $fstart, $fcount) = (undef, 0, LIST_DEFAULT_LIMIT);
	my $result = [];	
	#
 	my $ftext = filter_get_text($filter);
	my $fstart = filter_get_offset($filter);
	my $fcount = filter_get_limit($filter);
	#
	my $db = $self->db_open();
	$db->lock();
	foreach my $dn (keys %{$db}) {
		my $obj = $db->{$dn};
		unless($obj) { next; }

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
	my %ndomains;	
	#
	my $db = $self->db_open(); 
	$db->lock_exclusive();
	unless(-e $self->{cf_file}) {
		$err = Wstk::WstkException->new("File not found: ".$self->{cf_file});
		goto out;
	}
	#
	open(my $fh, "<".$self->{cf_file});
	unless($fh) {
		$err = Wstk::WstkException->new("Couldn't read file: ".$self->{cf_file});
		goto out;
	}
	while(<$fh>) {
		next if($_ =~ /^#.*/ || length($_) <= 2);
		my $ln = lc($_); chomp($ln);			
		my ($domain, $description) = split(/\s+/, $ln, 2);
		unless(exists($db->{$domain})) {
			$db->{$domain} = PFADMIN::Models::Domain->new(name => $domain, decription => $description);
			$ndomains{$domain} = 1;			
		}
	}
	close($fh);
	foreach my $id (keys %{$db}) {
		unless(exists($ndomains{$id})) {
			delete $db->{$id};
		} else {
			mkdir_local($self, $id);
		}		
	}
	#
	$self->sync_label_store (
		$self->sync_label_get_original()
	);
	$self->{logger}->debug("domains DB has been synchronized");
out:
	$db->unlock();
	if($err) { die $err; }
	return 1;
}

sub sync_data {
	my ($self) = @_;	
	my $oldfn = undef;
	my $restoreOld = 0;
	my $err = undef;
	#
	my $backup_enable = $self->{pfadmin}->get_config('etc','backup_data');	
	if($backup_enable eq 'true') {
		my $backup_ext = strftime("%d%m%Y", localtime);
		my ($dfile) = (fileparse($self->{cf_file}))[0];
		$oldfn = $self->{backup_path}.'/'.$dfile."_".$backup_ext;
		rename($self->{cf_file}, $oldfn);
		$restoreOld = 1;
	}
	#
	my $db = $self->db_open();
	$db->lock_exclusive();
	open(my $fh, ">".$self->{cf_file});
	unless($fh) { $err = Wstk::WstkpException->new("Couldn't open file: ".$self->{cf_file}); goto out; }
	print($fh  "#\n# generated at: " . localtime() . "\n#\n");

	$db->lock_exclusive();
	foreach my $id (keys %{$db}) {
		my $obj = $db->{$id};
		print($fh  $obj->name().' '.$obj->name()."\n");
	}
	close($fh);		
	# update sync label
	$self->sync_label_store (
		$self->sync_label_get_original()
	);
	$self->{logger}->debug("domains map has been synchronized");
out:	
	$db->unlock();
	if($err) {
		if($restoreOld) {
			rename($oldfn, $self->{cf_file});
		}
		die $err;
	}
	return 1;
}

sub do_postmap {
	my ($self) = @_;
	#
	my $cmd = 'postmap '.$self->{cf_file}.' > /dev/null';
	system($cmd);	
	#
	my $res = $?;
    if ($res == -1) {
		my $err = $!;
		die Wstk::WstkException->new("postmap (".$self->{cf_file}."), error: ".$err);
    }	
	return 1;
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
  	if(is_empty($entity->name())) {
        die Wstk::WstkException->new("Invalid property: name", RPC_ERR_CODE_VALIDATION_FAIL);
    }
    if($entity->name() !~ /^([a-zA-Z0-9\.\_])+$/) {
        die Wstk::WstkException->new("Invalid property: name", RPC_ERR_CODE_VALIDATION_FAIL);
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

sub is_domain_exists {
	my ($self, $domain) = @_;
	my $db = $self->db_open();
	return exists($db->{lc($domain)});
}

sub sync_label_get_original {
	my ($self) = @_;	
	open(my $t, "<".$self->{cf_file}) || return 0;
	my $ts = (stat($t))[9];
	close($t);
	return $ts;
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
	return DBM::Deep->new(file => $self->{db_file}, locking => 0, autoflush => 1 );
}

1;