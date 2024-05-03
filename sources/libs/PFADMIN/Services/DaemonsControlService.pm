# ******************************************************************************************
#
# (C)2021 aks
# https://github.com/akscf/
# ******************************************************************************************
package PFADMIN::Services::DaemonsControlService;

use strict;

use Log::Log4perl;
use ReadBackwards;
use Wstk::Boolean;
use Wstk::WstkDefs qw(:ALL);
use Wstk::WstkException;
use Wstk::Models::SearchFilter;
use PFADMIN::Defs qw(:ALL);
use PFADMIN::Models::ServerStatus;

sub new ($$;$) {
	my ( $class, $pfadmin ) = @_;
	my $self = {
		logger              => Log::Log4perl::get_logger(__PACKAGE__),
		class_name          => $class,
		pfadmin             => $pfadmin,
        sec_mgr             => $pfadmin->{sec_mgr},
        domain_dao          => $pfadmin->dao_lookup('DomainsDAO'),
        alias_dao           => $pfadmin->dao_lookup('AliasDAO'),
        mailbox_dao         => $pfadmin->dao_lookup('MailboxDAO'),
        helo_filter_dao     => $pfadmin->dao_lookup('HeloFilterDAO'),
        sender_filter_dao   => $pfadmin->dao_lookup('SenderFilterDAO'),
        header_filter_dao   => $pfadmin->dao_lookup('HeaderFilterDAO'),
        body_filter_dao     => $pfadmin->dao_lookup('BodyFilterDAO')
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
sub rpc_postfixStart {
    my ($self, $sec_ctx) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    return $self->postfix_do_cmd('start');
}

sub rpc_postfixStop {
    my ($self, $sec_ctx) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    return $self->postfix_do_cmd('stop');
}

sub rpc_postfixReload {
    my ($self, $sec_ctx) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    return $self->postfix_do_cmd('reload');
}

sub rpc_postfixGetStatus {
    my ($self, $sec_ctx) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
	#
    my $status = PFADMIN::Models::ServerStatus->new(pid => 0, state => 'unknown', version => 'unknown');    
    my $cmd = $self->{pfadmin}->get_config('postfix','cmd_status');
    unless($cmd) { die Wstk::WstkException->new( 'Missing configuration property: postfix.cmd_status', RPC_ERR_CODE_INTERNAL_ERROR ); }
    my $st  = `$cmd`;
    # 
    my @tt  = split('\n', $st);    
    foreach my $l (@tt) {
        if($l =~ /Active:\s(.*)$/) { $status->{state} = $1; next; }
        if($l =~ /(\d+)\s.*\/sbin\/master$/) {
            $status->{pid} = $1;
            $status->{state}='active' unless($status->{state});
            last;
        }
    }
    # 
    my $tt = '/tmp/.xtmp1'.$$;
    system('postconf mail_version > '.$tt);
    my $r = open( my $x, "<".$tt );
    if($r) {
        $status->{version}=<$x>; close($x);		
        chomp($status->{version});
		my ($t) = $status->{version} =~ /mail_version\s=\s(.*)/;
		$status->{version} = $t;
    }
    unlink($tt);
    #
    return $status;
}

sub rpc_dovecotStart {
    my ($self, $sec_ctx) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    return $self->dovecot_do_cmd('start');
}

sub rpc_dovecotStop {
    my ($self, $sec_ctx) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    return $self->dovecot_do_cmd('stop');
}

sub rpc_dovecotReload {
    my ($self, $sec_ctx) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #
    return $self->dovecot_do_cmd('reload');
}

sub rpc_dovecotGetStatus {
    my ($self, $sec_ctx) = @_;
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
	#
    my $status = PFADMIN::Models::ServerStatus->new(pid => 0, state => 'unknown', version => 'unknown');
    my $cmd = $self->{pfadmin}->get_config('dovecot','cmd_status');
    unless($cmd) { die Wstk::WstkException->new( 'Missing configuration property: dovecot.cmd_status', RPC_ERR_CODE_INTERNAL_ERROR ); }
    my $st  = `$cmd`;
    #
    my @tt  = split('\n', $st);    
    foreach my $l (@tt) {
        if($l =~ /Active:\s(.*)$/) { $status->{state} = $1; next; }
        if($l =~ /Main PID\:\s(\d+)\s\((.*)\)$/) {
            $status->{pid} = $1;
            $status->{state}=$2 unless($status->{state});
            last;
        }
    }
    #
    my $tt = '/tmp/.xtmp2'.$$;
    system('dovecot --version > '.$tt);
    my $r = open( my $x, "<".$tt );
    if($r) {$status->{version}=<$x>; close($x); chomp($status->{version}); }
    unlink($tt);
    #
    return $status;
}

sub rpc_logRead {
	my ($self, $sec_ctx, $filter) = @_;
    my ($ftext, $fstart, $fcount) = (undef, 0, 250);
	my $result=[];	
    #
    check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
	#
    my $log_file = $self->{pfadmin}->get_config('postfix','log_file');
    unless($log_file) {
		die Wstk::WstkException->new( 'Missing configuration property: postfix.log_file', RPC_ERR_CODE_INTERNAL_ERROR );
	}
    unless( -e $log_file ) {
        die Wstk::WstkException->new( 'File not found: '.$log_file, RPC_ERR_CODE_NOT_FOUND );
    }
    #
    my $bw = File::ReadBackwards->new( $log_file ) || die Wstk::WstkException->new( "Couldn't read logfile: $!", RPC_ERR_CODE_NOT_FOUND );	
	if($filter) {
		$ftext  = $filter->text();
		$fstart = ($filter->resultsStart() ? $filter->resultsStart() : $fstart);
		$fcount = ($filter->resultsLimit() ? $filter->resultsLimit() : $fcount);
	}
    while(defined(my $l = $bw->readline())) {
        $fcount-- if($fcount >= 0);
        last unless($fcount);
		unless($ftext) {
			push(@{$result}, $l);
		} else {
			push(@{$result}, $l) if($l =~ m/\Q$ftext/);
		}        
    }
	#
    return $result;	
}

sub rpc_syncData {
	my ($self, $sec_ctx) = @_;
    #
	check_permissions($self, $sec_ctx, [ROLE_ADMIN]);
    #	
	$self->{domain_dao}->sync_data();
	$self->{domain_dao}->do_postmap();
	$self->{alias_dao}->sync_data();
	$self->{alias_dao}->do_postmap();
	$self->{mailbox_dao}->sync_data();
	$self->{mailbox_dao}->do_postmap();
	#
	$self->postfix_do_cmd('reload');
	$self->dovecot_do_cmd('reload');
	#
	return Wstk::Boolean::TRUE;
}

sub rpc_syncFilters {
    my ( $self, $sec_ctx ) = @_;
    #
    $self->check_permissions($sec_ctx, [ROLE_ADMIN]);
    #
    $self->{helo_filter_dao}->sync_data();
    $self->{sender_filter_dao}->sync_data();
    #
    $self->postfix_do_cmd('reload');   
    #
    return Wstk::Boolean::TRUE;
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

sub lock {
    my ($self, $action) = @_;
    my $wstk = $self->{pfadmin}->{wstk};
    if($action == 1) {
        my $v = $wstk->sdb_get('lock_daemons');
        if($v) { die Wstk::WstkException->new('Resource is locked, try again later', RPC_ERR_CODE_INTERNAL_ERROR); }
        $wstk->sdb_put('lock_daemons', 1);
    } else {
        $wstk->sdb_put('lock_daemons', undef);
    }
}

sub postfix_do_cmd {
    my ( $self, $cmd_name) = @_;
    #
    my $cmd = $self->{pfadmin}->get_config('postfix','cmd_'.$cmd_name);
    unless($cmd) {
        die Wstk::WstkException->new('Missing configuration property: postfix.cmd_'.$cmd_name, RPC_ERR_CODE_INTERNAL_ERROR);
    }
    lock($self, 1);
    system($cmd);
    my $res = $?;
    lock($self, 0);    
    if ($res == -1) {
        my $err = $!;
        $self->{logger}->error("Couldn't '.$cmd_name.' postfix: ".$err." (".$cmd.")");
        die Wstk::WstkException->new( "Couldn't '.$cmd_name.' server: ".$err, RPC_ERR_CODE_INTERNAL_ERROR);
    }
    return Wstk::Boolean::TRUE;
}

sub dovecot_do_cmd {
    my ( $self, $cmd_name) = @_;
    #
    my $cmd = $self->{pfadmin}->get_config('dovecot','cmd_'.$cmd_name);
    unless($cmd) {
        die Wstk::WstkException->new('Missing configuration property: dovecot.cmd_'.$cmd_name, RPC_ERR_CODE_INTERNAL_ERROR);
    }
    lock($self, 1);
    system($cmd);
    my $res = $?;
    lock($self, 0);    
    if ($res == -1) {
        my $err = $!;
        $self->{logger}->error("Couldn't '.$cmd_name.' dovecot: ".$err." (".$cmd.")");
        die Wstk::WstkException->new( "Couldn't '.$cmd_name.' server: ".$err, RPC_ERR_CODE_INTERNAL_ERROR );
    }
    return Wstk::Boolean::TRUE;
}


1;
