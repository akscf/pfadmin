# ******************************************************************************************
#
# (C)2021 aks
# https://github.com/akscf/
# ******************************************************************************************
package PFADMIN::Services::MaildirsManagementService;

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
        mailbox_dao		=> $pfadmin->dao_lookup('MailboxDAO'),
        maildir_dao		=> $pfadmin->dao_lookup('MaildirDAO'),
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
sub rpc_mkdir {
	my ($self, $sec_ctx, $mbox, $file_item) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    my $mailbox = $self->{mailbox_dao}->get($mbox);
    unless($mailbox) {
        die Wstk::WstkException->new($mbox, RPC_ERR_CODE_NOT_FOUND);
    }
    return $self->{maildir_dao}->mkdir($mailbox, $file_item);
}

sub rpc_mkfile {
	my ($self, $sec_ctx, $mbox, $file_item) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    my $mailbox = $self->{mailbox_dao}->get($mbox);
    unless($mailbox) {
        die Wstk::WstkException->new($mbox, RPC_ERR_CODE_NOT_FOUND);
    }
	return $self->{maildir_dao}->mkfile($mailbox, $file_item);
}

sub rpc_rename {
	my ($self, $sec_ctx, $mbox, $new_name, $file_item) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    my $mailbox = $self->{mailbox_dao}->get($mbox);
    unless($mailbox) { 
    	die Wstk::WstkException->new($mbox, RPC_ERR_CODE_NOT_FOUND);
    }
    return $self->{maildir_dao}->rename($mailbox, $new_name, $file_item);
}

sub rpc_move {
	my ($self, $sec_ctx, $mbox, $from, $to) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    my $mailbox = $self->{mailbox_dao}->get($mbox);
    unless($mailbox) { 
    	die Wstk::WstkException->new($mbox, RPC_ERR_CODE_NOT_FOUND);
    }
    return $self->{maildir_dao}->move($mailbox, $from, $to);
}

sub rpc_delete {
    my ($self, $sec_ctx, $mbox, $path) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    my $mailbox = $self->{mailbox_dao}->get($mbox);
    unless($mailbox) { 
    	die Wstk::WstkException->new($mbox, RPC_ERR_CODE_NOT_FOUND);
    }    
    return ($self->{maildir_dao}->delete($mailbox, $path) ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
}

sub rpc_getMeta {
    my ($self, $sec_ctx, $mbox, $path) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    my $mailbox = $self->{mailbox_dao}->get($mbox);
    unless($mailbox) { 
    	die Wstk::WstkException->new($mbox, RPC_ERR_CODE_NOT_FOUND);
    }
    return $self->{maildir_dao}->get_meta($mailbox, $path);
}

sub rpc_browse {
	my ($self, $sec_ctx, $mbox, $path, $filter) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    my $mailbox = $self->{mailbox_dao}->get($mbox);
    unless($mailbox) { 
    	die Wstk::WstkException->new($mbox, RPC_ERR_CODE_NOT_FOUND);
    }
    return $self->{maildir_dao}->browse($mailbox, $path, $filter);
}

sub rpc_readBody {
    my ($self, $sec_ctx, $mbox, $path) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    my $mailbox = $self->{mailbox_dao}->get($mbox);
    unless($mailbox) { 
    	die Wstk::WstkException->new($mbox, RPC_ERR_CODE_NOT_FOUND);
    }    
    return $self->{maildir_dao}->read_body($mailbox, $path);
}

sub rpc_writeBody {
    my ($self, $sec_ctx, $mbox, $path, $data) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    my $mailbox = $self->{mailbox_dao}->get($mbox);
    unless($mailbox) { 
    	die Wstk::WstkException->new($mbox, RPC_ERR_CODE_NOT_FOUND);
    }        
    return ($self->{maildir_dao}->write_body($mailbox, $path, $data) ? Wstk::Boolean::TRUE : Wstk::Boolean::FALSE);
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
