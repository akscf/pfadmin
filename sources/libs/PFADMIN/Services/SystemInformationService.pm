# ******************************************************************************************
#
# (C)2021 aks
# https://github.com/akscf/
# ******************************************************************************************
package PFADMIN::Services::SystemInformationService;

use strict;

use Log::Log4perl;
use Wstk::Boolean;
use PFADMIN::Defs qw(:ALL);
use PFADMIN::Models::SystemStatus;

sub new ($$;$) {
	my ( $class, $pfadmin ) = @_;
	my $self = {
		logger          => Log::Log4perl::get_logger(__PACKAGE__),
		class_name      => $class,
		pfadmin         => $pfadmin,
        sec_mgr         => $pfadmin->{sec_mgr},
        info            => PFADMIN::Models::SystemStatus->new()
	};
	bless( $self, $class ); 
	#
	my $os_name = `uname`;
	$self->{info}->productName('Postfix admin');
	$self->{info}->productVersion('1.0.0');
	$self->{info}->instanceName('noname');
	$self->{info}->vmInfo('Perl '.$]);
	$self->{info}->osInfo($os_name);
	$self->{info}->uptime(0);
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
sub rpc_getStatus {
	my ($self, $sec_ctx) = @_;
    #        
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    my $info = $self->{info};
    my $ts_start = $self->{pfadmin}->{start_time};
    my $ts_cur = time();
    #
	$info->uptime(($ts_cur - $ts_start));
	#
	return $info;
}


# ---------------------------------------------------------------------------------------------------------------------------------
# private methods
# ---------------------------------------------------------------------------------------------------------------------------------
sub check_permissions {
    my ($self, $ctx, $roles) = @_;
    #
    my $ident = $self->{sec_mgr}->identify($ctx);
    $self->{sec_mgr}->pass($ident, $roles);
}

1;
