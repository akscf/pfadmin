# ******************************************************************************************
#
# (C)2021 aks
# https://github.com/akscf/
# ******************************************************************************************
package PFADMIN::DAO::HeloFilterDAO;

use strict;

use POSIX qw(strftime);
use Log::Log4perl;
use File::Basename;
use File::Slurp;
use DBM::Deep;
use UUID::Tiny ':std';
use Wstk::Boolean;
use Wstk::WstkDefs qw(:ALL);
use Wstk::WstkException;
use Wstk::EntityHelper;
use Wstk::SearchFilterHelper;
use Wstk::Models::SearchFilter;
use PFADMIN::IOHelper;
use PFADMIN::Defs qw(:ALL);
use PFADMIN::Models::FilterRule;

use constant ENTITY_CLASS_NAME => PFADMIN::Models::FilterRule::CLASS_NAME;
use constant LIST_DEFAULT_LIMIT => 250;

sub new ($$;$) {
	my ( $class, $pfadmin) = @_;
	my $self = {
		logger          	=> Log::Log4perl::get_logger(__PACKAGE__),
		class_name      	=> $class,
		pfadmin         	=> $pfadmin,
		wstk				=> $pfadmin->{wstk},
		filter_file			=> $pfadmin->get_config('postfix','helo_filter'),
		filter_enabled 		=> 1,
		backup_path			=> undef,
		db_path				=> undef,
		db_file				=> undef,
		id_file				=> undef
	};
	bless( $self, $class );
    #
	$self->{db_path} = $self->{pfadmin}->dao_lookup('DomainsDAO')->get_db_path();
	$self->{backup_path} = $self->{pfadmin}->dao_lookup('DomainsDAO')->get_backup_path();
	$self->{db_file} = $self->{db_path}.'/helo_filter.db';
	$self->{id_file} = $self->{db_path}.'/helo_filter.id';
	#
	if(!$self->{db_path} || !$self->{backup_path}) {
		die Wstk::WstkException->new("db_path or backup_path are malformed");
	}
	unless(-d $self->{db_path} || -d $self->{backup_path}) {
		die Wstk::WstkException->new("db_path or backup_path not exist");
	}
    unless ($self->{filter_file}) {
    	$self->{filter_enabled} = 0;
    }
	if($self->{filter_enabled}) {
		unless (-e $self->{filter_file}) {
			write_file($self->{filter_file}, "#\n");
		}
	}
	unless($self->is_sync_label_valid()) {		
		$self->sync_db() if($self->{filter_enabled});
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
	$entity->id(create_uuid_as_string(UUID_V4));
	$entity->regex($entity->regex());
	$entity->message($entity->message() ? $entity->message() : '');
	$entity->description($entity->description() ?  $entity->description() : '');
	$entity->enabled(is_true($entity->enabled()) ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
	#
	my $id = $entity->id();
	my $db = $self->db_open();
	$db->lock();
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
	if(is_empty($entity->id())) {
		die Wstk::WstkException->new('Invalid property: id', RPC_ERR_CODE_INVALID_ARGUMENT);
	}
	#
	my $db = $self->db_open();
	my $id = $entity->id();
	$db->lock();
	my $obj = $db->{$id};
	unless($obj) {
		$err = Wstk::WstkException->new($id, RPC_ERR_CODE_NOT_FOUND);
		goto out;
	}
	my $regex = $entity->regex();
	$regex =~ s/\s/\\s/g;
	$entity->regex($regex);	
	#
	$obj->regex($entity->regex());
	$obj->message($entity->message() ? $entity->message() : '');
	$obj->description($entity->description() ?  $entity->description() : '');
	$obj->enabled(is_true($entity->enabled()) ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
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
	unless($self->{filter_enabled})  {
		die Wstk::WstkException->new('filter is disabled', RPC_ERR_CODE_INTERNAL_ERROR);
	}
   	unless(defined $entity_id) {
        die Wstk::WstkException->new("entity_id", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
	#
	my $db = $self->db_open();
	$db->lock();
	if(exists($db->{$entity_id})) {
		delete($db->{$entity_id});
	}	
	$db->unlock();	
	return 1;
}

sub get {
	my ($self, $entity_id) = @_;		
	my $entity = undef;
	my $err = undef;
	#
	unless($self->{filter_enabled})  {
		die Wstk::WstkException->new('filter is disabled', RPC_ERR_CODE_INTERNAL_ERROR);
	}
   	unless(defined $entity_id) {
        die Wstk::WstkException->new("entity_id", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
	#
	my $db = $self->db_open();
	$db->lock();	
	$entity = $db->{$entity_id};	
	$db->unlock();	
	return $entity;
}

sub list {
	my ($self, $filter) = @_;
	my ($ftext, $fstart, $fcount) = (undef, 0, LIST_DEFAULT_LIMIT);
	my $result = [];	
	#
	unless($self->{filter_enabled})  {
		return $result;
	}
	#
	my $ftext = filter_get_text($filter);
	my $fstart = filter_get_offset($filter);
	my $fcount = filter_get_limit($filter);
	#    
	my $db = $self->db_open();
	$db->lock();
	foreach my $id (keys %{$db}) {
		my $obj = $db->{$id};
		if(!$obj) { next; }
		
		if($fstart > 0) { $fstart--; next; }		
		if($fcount > 0) { $fcount--; } else { last; }
		
		unless($ftext) {
			push(@{$result}, $obj);
			next;
		}
		if($obj->regex() =~ m/\Q$ftext/ || $obj->action() =~ m/\Q$ftext/) {
			push(@{$result}, $obj);
		}
	}	
	$db->unlock();
	# 
	my @srt = sort { $a->{regex} cmp $b->{regex} } @{$result};
	return \@srt;
}

sub sync_db {
	my ($self) = @_;
	my $err = undef;
	#
	unless($self->{filter_enabled})  {
		$self->{logger}->debug("filter is disabled");
		return 1;
	}
	#
	my $db = $self->db_open();	
	$db->lock_exclusive();
	$db->clear();

	open(my $fh, "<".$self->{filter_file});
	unless($fh) {
		$err = Wstk::WstkException->new("Couldn't read file: ".$self->{filter_file});
		goto out;
	}
	my ($wend, $skip, $cnt) = (0, 0, 0);
	while(<$fh>) {
		next if($_ =~ /^#.*/ || length($_) <= 2);
		my $ln = $_; chomp($ln);		
		# ignore expressions
		if($ln =~ /^IF.*/) {$wend +=1; $skip +=1;}
		if($wend && $ln =~/^ENDIF/) {$wend -=1; $skip -=1; }
		next if($skip > 0);				
		# regex-action-msg
		if($ln =~ /^\/(.*)\/\s+(\w+){1}(\s(.*))?$/) {
			my ($regex, $action, $msg) = ($1, $2, $3);
			$msg =~ s/^\s+//;			
			my $id = create_uuid_as_string(UUID_V4);
			my $obj = PFADMIN::Models::FilterRule->new(
					id 			=> $id,
					enabled  	=> Wstk::Boolean::TRUE,
					regex	 	=> '/'.$regex.'/',
					action	 	=> $action,
					message 	=> $msg
				);
			$db->{$id} = $obj; $cnt++;
		}
	}
	close($fh);
	# update sync label
	$self->sync_label_store(
		$self->sync_label_get_original()
	);
	$self->{logger}->debug("DB has been synchronized ($cnt rules added)");
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

	unless($self->{filter_enabled})  {
		$self->{logger}->debug("fiilter is disabled");
		return 1;
	}
	#
	open(my $fh, ">".$self->{filter_file});
	unless($fh) {$err = Wstk::WstkException->new("Couldn't open file: ".$self->{filter_file}); goto out; }	
	print($fh  "#\n# generated at: " . localtime() . "\n#\n");
	#
	my $db = $self->db_open();
	$db->lock_exclusive();
	foreach my $id (keys %{$db}) {
		my $obj = $db->{$id};
		if(is_true($obj->enabled())) {
			print($fh  $obj->regex() ." ". $obj->action() . ($obj->message() ? (" ".$obj->message()) : "") ."\n");
		}
	}
	close($fh);
	# update sync label
	$self->sync_label_store(
		$self->sync_label_get_original()
	);
	$self->{logger}->debug("map has been synchronized");
out:	
	$db->unlock();
	if($err) {
		if($restoreOld) {
			rename($oldfn, $self->{filter_file});
		}
		die $err;
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
	if(is_empty($entity->regex())) {
		die Wstk::WstkException->new('Invalid property: regex', RPC_ERR_CODE_INVALID_ARGUMENT);
	}
	if(is_empty($entity->action())) {
		die Wstk::WstkException->new('Invalid property: action', RPC_ERR_CODE_INVALID_ARGUMENT);
	}    
	return 1;
}

sub sync_label_get_original {
	my ($self) = @_;
	return io_get_file_lastmod($self->{filter_file});
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
	#
	unless($self->{filter_enabled})  {
		return 1;
	}

	my $ots = $self->sync_label_get_original();
	my $cts = $self->sync_label_get_stored();
	
	return ($cts > 0 && $ots == $cts);
}

sub strip_regex {
	my ($str) = @_;
	$str =~ s/\s/\\s/g;
	return $str;
}

sub db_open {
	my ($self) = @_;
	return DBM::Deep->new(file => $self->{db_file}, locking => 0, autoflush => 1 );
}

1;
