# ******************************************************************************************
#
# (C)2021 aks
# https://github.com/akscf/
# ******************************************************************************************
package PFADMIN::Services::DovecotHelperService;

use strict;

use Log::Log4perl;
use ReadBackwards;
use Wstk::Boolean;
use Wstk::WstkException;
use Wstk::WstkDefs qw(:ALL);
use PFADMIN::Defs qw(:ALL);

sub new ($$;$) {
	my ( $class, $pfadmin ) = @_;
	my $self = {
		logger          => Log::Log4perl::get_logger(__PACKAGE__),
		class_name      => $class,
		pfadmin         => $pfadmin,
        sec_mgr         => $pfadmin->{sec_mgr}
	};
	bless( $self, $class ); 
	return $self;
}

sub get_class_name {
	my ($self) = @_;
	return $self->{class_name};
}

# ---------------------------------------------------------------------------------------------------------------------------------
# public methods
# ---------------------------------------------------------------------------------------------------------------------------------
sub rpc_sendMessage {
	my ($self, $sec_ctx, $mbox, $text)= @_;
	#
	check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
	#
	# TODO
	#system("doveadm kick ".$entity->name());
	#
	return Wstk::Boolean::FALSE;
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
