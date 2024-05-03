# ******************************************************************************************
#
# (C)2021 aks
# https://github.com/akscf/
# ******************************************************************************************
package PFADMIN::DAO::BodyFilterDAO;

use strict;

use POSIX qw(strftime);
use Log::Log4perl;
use File::Basename;
use File::Slurp;
use File::Copy;
use Wstk::Boolean;
use Wstk::WstkDefs qw(:ALL);
use Wstk::WstkException;
use Wstk::EntityHelper;
use Wstk::SearchFilterHelper;
use Wstk::Models::SearchFilter;
use PFADMIN::IOHelper;
use PFADMIN::Defs qw(:ALL);

sub new ($$;$) {
	my ( $class, $pfadmin) = @_;
	my $self = {
		logger          	=> Log::Log4perl::get_logger(__PACKAGE__),
		class_name      	=> $class,
		pfadmin         	=> $pfadmin,
		wstk				=> $pfadmin->{wstk},
		filter_file			=> $pfadmin->get_config('postfix','body_filter'),
		filter_enabled 		=> 1
	};
	bless( $self, $class );
    #
    unless ($self->{filter_file}) {
    	$self->{filter_enabled} = 0;
    }    
	if($self->{filter_enabled}) {
		unless (-e $self->{filter_file}) {
			write_file($self->{filter_file}, "#\n");
		}
	}
	return $self;
}

sub get_class_name {
	my ($self) = @_;
	return $self->{class_name};
}

# ---------------------------------------------------------------------------------------------------------------------------------
# public methods
# ---------------------------------------------------------------------------------------------------------------------------------
sub read {
	my ($self) = @_;
	#
	unless($self->{filter_enabled})  {
		die Wstk::WstkException->new('filter disabled', RPC_ERR_CODE_INTERNAL_ERROR);
	}
	#
	my $data = undef;
	
	$self->lock(1);
    $data = read_file($self->{filter_file});
    $self->lock(0);

    return $data;
}

sub write {
	my ($self, $data) = @_;	
	#
	unless($self->{filter_enabled})  {
		die Wstk::WstkException->new('filter disabled', RPC_ERR_CODE_INTERNAL_ERROR);
	}

    my $file = $self->{filter_file};
    my $backup = $file.'.old';
    
    $self->lock(1);  
    copy($file, $backup);    
    write_file($file, $data);
    $self->lock(0);
	
	return 1;
}

sub get_abs_path {
	my ($self) = @_;
	unless($self->{filter_enabled})  {
		die Wstk::WstkException->new('filter disabled', RPC_ERR_CODE_INTERNAL_ERROR);
	}
	return $self->{filter_file};
}

sub is_file_empty {
	my ($self) = @_;		
	return (io_get_file_size($self->{filter_enabled}) == 0);
}

sub is_filter_enabled {
	my ($self) = @_;		
	return $self->{filter_enabled};
}

# ---------------------------------------------------------------------------------------------------------------------------------
# private methods
# ---------------------------------------------------------------------------------------------------------------------------------
sub lock {
    my ($self, $action) = @_;
    my $wstk = $self->{pfadmin}->{wstk};
    if($action == 1) {
        my $v = $wstk->sdb_get('lock_body_filter');
        if($v) { die Wstk::WstkException->new( 'Resource is locked, try again later', RPC_ERR_CODE_INTERNAL_ERROR ); }
        $wstk->sdb_put('lock_body_filter', 1);
    } else {
        $wstk->sdb_put('lock_body_filter', undef);
    }
}


1;
