# ******************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# ******************************************************************************************
package PFADMIN::DAO::AliasDAO;

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
use PFADMIN::Models::Alias;

use constant ENTITY_CLASS_NAME => PFADMIN::Models::Alias::CLASS_NAME;
use constant LIST_DEFAULT_LIMIT => 250;

sub new ($$;$) {
	my ( $class, $pfadmin) = @_;
	my $self = {
		logger          => Log::Log4perl::get_logger(__PACKAGE__),
		class_name      => $class,
		pfadmin         => $pfadmin,
		cf_file			=> $pfadmin->get_config('postfix','aliases_db'),
		backup_path		=> undef,
		db_path			=> undef,
		db_file			=> undef,
		id_file			=> undef
	};
	bless( $self, $class );
    #
	$self->{db_path} = $self->{pfadmin}->dao_lookup('DomainsDAO')->get_db_path();
	$self->{backup_path} = $self->{pfadmin}->dao_lookup('DomainsDAO')->get_backup_path();
	$self->{db_file} = $self->{db_path}.'/aliases.db';
	$self->{id_file} = $self->{db_path}.'/aliases.id';
	#
	if(!$self->{db_path} || !$self->{backup_path}) {
		die Wstk::WstkException->new("db_path or backup_path is incorrect");
	}
	unless(-d $self->{db_path} || -d $self->{backup_path}) {		
		die Wstk::WstkException->new("db_path or backup_path not exist");
	}	
	unless(-e $self->{cf_file}) {
		die Wstk::WstkException->new("Missing file: ".$self->{cf_file});
	}
	unless($self->is_sync_label_valid()) {
		$self->sync_db();
	}
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
	if(index($entity->address, "@") < 0 ) {
		$entity->address(lc($entity->address() .'@'. $domain->name()));
	} else {
		my ($name, $domain) = split(/\@/, $entity->address(), 2);
		$entity->address(lc($name.'@'.$domain->name()));
	}
	#
	$entity->domainId($domain->name());
	$entity->targets($entity->targets() ? lc($entity->targets()) : '');
	$entity->description($entity->description() ?  $entity->description() : '');	
	$entity->enabled(is_true($entity->enabled()) ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
	#	
	my $id = $entity->address();
	my $db = $self->db_open();
	$db->lock();
	if(exists($db->{$id})) {
		$err = Wstk::WstkException->new($id , RPC_ERR_CODE_ALREADY_EXISTS);
		goto out;
	}
	$db->{$id} = $entity;
out:
	$db->unlock();
	if($err) { die $err; }
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
	my $id = lc($entity->address());
	my $db = $self->db_open();
	$db->lock();
	my $obj = $db->{$id};
	unless($obj) {
		$err = Wstk::WstkException->new($id, RPC_ERR_CODE_NOT_FOUND);
		goto out;
	}
	$obj->enabled(is_true($entity->enabled()) ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
	$obj->targets($entity->targets() ? lc($entity->targets()) : '');
	$obj->description($entity->description() ? $entity->description() : '');	
	#
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
	my $id = lc($entity_id);
	my $db = $self->db_open();
	$db->lock();
	if(exists($db->{$id})) {
		delete($db->{$id});
	}	
	$db->unlock();
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
	foreach my $alias (keys %{$db}) {
		my $obj = $db->{$alias};
		if(!$obj || ($domain_id && $obj->domainId() ne $domain_id)) { next; }
		
		if($fstart > 0) { $fstart--; next; }		
		if($fcount > 0) { $fcount--; } else { last; }
		
		unless($ftext) {
			push(@{$result}, $obj);
			next;
		} 
		if($obj->address() =~ m/\Q$ftext/ || $obj->targets() =~ m/\Q$ftext/) {
			push(@{$result}, $obj);
		}
	}	
	$db->unlock();
	# 
	my @srt = sort { $a->{address} cmp $b->{address} } @{$result};
	return \@srt;
}

sub sync_db {
	my ($self) = @_;	
	my $err = undef;
	my %aliases;
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
		my ($address, $targets) = split(/\s+/, $ln, 2);
		my ($name, $domain) = split(/\@/, $address, 2);		
		my $obj = PFADMIN::Models::Alias->new(
					enabled  	=> Wstk::Boolean::TRUE,
					domainId 	=> $domain,
					address	 	=> $address,
					targets	 	=> $targets,
					description => ''
				);
		unless(exists($db->{$address})) {
			$db->{$address} = $obj;
		}
		$aliases{$address} = $obj;
	}
	close($fh);	
	foreach my $id (keys %{$db}) {
		unless(exists($aliases{$id})) {
			my $obj = $db->{$id};
			$obj->enabled(Wstk::Boolean::FALSE);			
			$db->{$id} = $obj;
		}
	}
	# update sync label
	$self->sync_label_store(
		$self->sync_label_get_original()
	);
	$self->{logger}->debug("aliases DB has been synchronized");
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
	open(my $fh, ">".$self->{cf_file});
	unless($fh) {
		$err = Wstk::WstkException->new("Couldn't open file: ".$self->{cf_file});
		goto out;
	}	
	print($fh  "#\n# generated at: " . localtime() . "\n#\n");

	my $db = $self->db_open();
	$db->lock_exclusive();
	foreach my $id (keys %{$db}) {
		my $obj = $db->{$id};
		if(is_true($obj->enabled())) {
			print($fh  $obj->address() ." ".$obj->targets()."\n");
		}		
	}
	close($fh);
	# update sync label
	$self->sync_label_store(
		$self->sync_label_get_original()
	);
	$self->{logger}->debug("aliases map has been synchronized");
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
	if(is_empty($entity->domainId())) {
		die Wstk::WstkException->new('Invalid property: domainId', RPC_ERR_CODE_INVALID_ARGUMENT);
	}
	if(is_empty($entity->address())) {
		die Wstk::WstkException->new('Invalid property: address', RPC_ERR_CODE_INVALID_ARGUMENT);
	}
	if(is_empty($entity->targets())) {
		die Wstk::WstkException->new('Invalid property: targets', RPC_ERR_CODE_INVALID_ARGUMENT);
	}
	return 1;
}

sub sync_label_get_original {
	my ($self) = @_;
	return io_get_file_lastmod($self->{cf_file});
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
