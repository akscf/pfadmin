# ******************************************************************************************
#
# (C)2021 aks
# https://github.com/akscf/
# ******************************************************************************************
package PFADMIN::Services::DomainsManagementService;

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
        sec_mgr         => $pfadmin->{sec_mgr},
        domain_dao		=> $pfadmin->dao_lookup('DomainsDAO')
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
sub rpc_add {
	my ($self, $sec_ctx, $entity)= @_;
	#
	check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
	#
	return $self->{domain_dao}->add($entity);
}

sub rpc_update {
	my ($self, $sec_ctx, $entity)= @_;
	#
	check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
	#
	return $self->{domain_dao}->update($entity);	
}

sub rpc_delete {
	my ($self, $sec_ctx, $entityId)= @_;
	#
	check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
	#
	return ($self->{domain_dao}->delete($entityId) ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
}

sub rpc_get {
	my ($self, $sec_ctx, $entityId)= @_;
	#
	check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
	#
	return $self->{domain_dao}->get($entityId);
}

sub rpc_list {
	my ($self, $sec_ctx, $filter)= @_;
	#
	check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
	#
	return $self->{domain_dao}->list($filter);
}

sub rpc_syncData {
	my ($self, $sec_ctx) = @_;
	#
	check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
	#
	return ($self->{domain_dao}->sync_data() ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
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
