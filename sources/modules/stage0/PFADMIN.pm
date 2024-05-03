# *********************************************************************************************************************************
#
# (C)2021 aks
# https://github.com/akscf/
# *********************************************************************************************************************************
package PFADMIN;

use strict;

use Log::Log4perl;
use Wstk::WstkException;
use Wstk::WstkDefs qw(RPC_ERR_CODE_INTERNAL_ERROR);

use PFADMIN::SecurityManager;
use PFADMIN::DAO::DomainsDAO;
use PFADMIN::DAO::MailboxDAO;
use PFADMIN::DAO::AliasDAO;
use PFADMIN::DAO::HeloFilterDAO;
use PFADMIN::DAO::SenderFilterDAO;
use PFADMIN::DAO::HeaderFilterDAO;
use PFADMIN::DAO::BodyFilterDAO;
use PFADMIN::DAO::MaildirDAO;
use PFADMIN::Services::SystemInformationService;
use PFADMIN::Services::AuthenticationService;
use PFADMIN::Services::DaemonsControlService;
use PFADMIN::Services::DomainsManagementService;
use PFADMIN::Services::MailboxesManagementService;
use PFADMIN::Services::AliasesManagementService;
use PFADMIN::Services::HeloFiltersManagementService;
use PFADMIN::Services::SenderFiltersManagementService;
use PFADMIN::Services::HeaderFiltersManagementService;
use PFADMIN::Services::BodyFiltersManagementService;
use PFADMIN::Services::MaildirsManagementService;
use PFADMIN::Services::DovecotHelperService;
use PFADMIN::Servlets::BlobsHelperServlet;

sub new ($$;$) {
        my ($class) = @_;
        my $self = {
                logger      	=> Log::Log4perl::get_logger(__PACKAGE__),
                class_name  	=> $class,
                version     	=> 1.1,
                description 	=> "Postfix admin",
                start_time		=> time(),
                wstk         	=> undef,
                sec_mgr	    	=> undef,
				dao				=> {}
        };
        bless( $self, $class );
        return $self;
}

sub get_class_name {
        my ($self) = @_;
        return $self->{class_name};
}

#---------------------------------------------------------------------------------------------------------------------------------
sub init {
        my ( $self, $wstk ) = @_;
        $self->{'wstk'} = $wstk;
}

sub start {
	my ( $self, $arg1, $arg2 ) = @_;

        $self->{'wstk'}->cfg_load(__PACKAGE__, sub {            
            my $cfg = shift;
			die("Missing configureation file!");
        });

		$self->{'sec_mgr'} = PFADMIN::SecurityManager->new($self);
	
		$self->dao_register(PFADMIN::DAO::DomainsDAO->new($self));
		$self->dao_register(PFADMIN::DAO::MailboxDAO->new($self));
		$self->dao_register(PFADMIN::DAO::AliasDAO->new($self));
		$self->dao_register(PFADMIN::DAO::HeloFilterDAO->new($self));
		$self->dao_register(PFADMIN::DAO::SenderFilterDAO->new($self));
		$self->dao_register(PFADMIN::DAO::HeaderFilterDAO->new($self));
		$self->dao_register(PFADMIN::DAO::BodyFilterDAO->new($self));
		$self->dao_register(PFADMIN::DAO::MaildirDAO->new($self));
				
		$self->{'wstk'}->mapper_alias_register('SystemStatus', PFADMIN::Models::SystemStatus::CLASS_NAME);
		$self->{'wstk'}->mapper_alias_register('FileItem', PFADMIN::Models::FileItem::CLASS_NAME);
		$self->{'wstk'}->mapper_alias_register('Alias', PFADMIN::Models::Alias::CLASS_NAME);
		$self->{'wstk'}->mapper_alias_register('Domain', PFADMIN::Models::Domain::CLASS_NAME);
		$self->{'wstk'}->mapper_alias_register('Mailbox', PFADMIN::Models::Mailbox::CLASS_NAME);
		$self->{'wstk'}->mapper_alias_register('FilterRule', PFADMIN::Models::FilterRule::CLASS_NAME);
		$self->{'wstk'}->mapper_alias_register('ServerStatus', PFADMIN::Models::ServerStatus::CLASS_NAME);

        $self->{'wstk'}->rpc_service_register('SystemInformationService', PFADMIN::Services::SystemInformationService->new($self));
        $self->{'wstk'}->rpc_service_register('AuthenticationService',	 PFADMIN::Services::AuthenticationService->new($self));
		$self->{'wstk'}->rpc_service_register('DaemonsControlService', 	 PFADMIN::Services::DaemonsControlService->new($self));
		$self->{'wstk'}->rpc_service_register('DomainsManagementService', PFADMIN::Services::DomainsManagementService->new($self));
		$self->{'wstk'}->rpc_service_register('MailboxesManagementService', PFADMIN::Services::MailboxesManagementService->new($self));
		$self->{'wstk'}->rpc_service_register('MaildirsManagementService', PFADMIN::Services::MaildirsManagementService->new($self));
		$self->{'wstk'}->rpc_service_register('AliasesManagementService', PFADMIN::Services::AliasesManagementService->new($self));
		$self->{'wstk'}->rpc_service_register('HeloFiltersManagementService', PFADMIN::Services::HeloFiltersManagementService->new($self));
		$self->{'wstk'}->rpc_service_register('SenderFiltersManagementService', PFADMIN::Services::SenderFiltersManagementService->new($self));
		$self->{'wstk'}->rpc_service_register('HeaderFiltersManagementService', PFADMIN::Services::HeaderFiltersManagementService->new($self));
		$self->{'wstk'}->rpc_service_register('BodyFiltersManagementService', PFADMIN::Services::BodyFiltersManagementService->new($self));
		$self->{'wstk'}->rpc_service_register('DovecotHelperService', PFADMIN::Services::DovecotHelperService->new($self));
		
		$self->{'wstk'}->servlet_register('/blobs/*', PFADMIN::Servlets::BlobsHelperServlet->new($self));		
		#
		$self->{logger}->info('pfadmin is ready (version '.$self->{version}.')');
}

sub stop {
	my ($self) = @_;
}

#---------------------------------------------------------------------------------------------------------------------------------
# module api
#---------------------------------------------------------------------------------------------------------------------------------
sub get_config {
	my ($self, $section, $property, $def_val) = @_;
	my $wstk = $self->{wstk}; 
	#
	my $val = $wstk->cfg_get(__PACKAGE__, $section, $property);
	unless(defined $val) { $val = $def_val; }
	return $val;
}

sub dao_register {
	my ($self, $inst) = @_;
    my $dao = $self->{dao};
    #
    unless($inst) {
		die Wstk::WstkException->new("Invalid argument: inst");
	}
	my @t = split('::', $inst->get_class_name());
	my $sz = scalar(@t);
	my $name = ($sz > 0 ? $t[$sz - 1] : $inst->get_class_name());
	#
	if(exists($dao->{$name})) {
		die Wstk::WstkException->new("Duplicate DAO: ".$name);
	}
	$dao->{$name} = $inst;
}

sub dao_lookup {
	my ($self, $name, $quiet) = @_;
	my $dao = $self->{dao};
	#
	unless(exists($dao->{$name})) {
		return undef if ($quiet);
		die Wstk::WstkException->new("Unknown DAO: ".$name);
	}
	return $dao->{$name};
}

#---------------------------------------------------------------------------------------------------------------------------------
return PFADMIN->new();
