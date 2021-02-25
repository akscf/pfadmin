# ******************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# ******************************************************************************************
package PFADMIN::Servlets::BlobsHelperServlet;

use strict;

use Log::Log4perl;
use MIME::Base64;
use Wstk::Boolean;
use Wstk::WstkException;
use Wstk::WstkDefs qw(:ALL);
use PFADMIN::Defs qw(:ALL);
use PFADMIN::IOHelper;

sub new ($$;$) {
	my ( $class, $pfadmin) = @_;
	my $self = {
		logger          	=> Log::Log4perl::get_logger(__PACKAGE__),
		class_name 			=> $class,
		pfadmin        		=> $pfadmin,
        sec_mgr         	=> $pfadmin->{sec_mgr},
        body_filter_dao		=> $pfadmin->dao_lookup('BodyFilterDAO'),
        header_filter_dao	=> $pfadmin->dao_lookup('HeaderFilterDAO'),
        mailbox_dao			=> $pfadmin->dao_lookup('MailboxDAO'),
        maildir_dao			=> $pfadmin->dao_lookup('MaildirDAO')
	};
	bless( $self, $class );
	return $self;
}

sub get_class_name {
	my ($self) = @_;
	return $self->{class_name};
}

sub execute_request {
	my ( $self, $cgi ) = @_;
	my $credentials = undef;	
	my $auth_hdr    = $ENV{'HTTP_AUTHORIZATION'};
	#
	if ($auth_hdr) {
		my ( $basic, $ucred ) = split( ' ', $auth_hdr );
		if ($basic) {
			my ( $user, $pass ) = split( ':', decode_base64($ucred) );
			if ( defined($user) && defined($pass) ) {
				$credentials = { method => $basic, user => $user, password => $pass };
			}
		}
	}
	my $session_id = $cgi->http("X-SESSION-ID");
	unless($session_id) { $session_id = $cgi->param('x-session-id'); }
	unless($session_id) { $session_id = $cgi->param('sid'); }
	my $ctx = {
		time       	=> time(),
		sessionId 	=> $session_id,
		userAgent	=> $cgi->http("HTTP_USER_AGENT"),
		remoteIp   	=> $ENV{'REMOTE_ADDR'},
		credentials => $credentials
	};
	$@ = "";	
	eval { 
		$self->{sec_mgr}->pass($self->{sec_mgr}->identify($ctx), [ROLE_ADMIN]); 
	} || do {
		die Wstk::WstkException->new('Permission denied', 403);
  	};
	my $type = $cgi->param('type');
   	if($ENV{'REQUEST_METHOD'} eq 'GET') {
   		my $data = undef;
    	if('header' eq $type) {
    		my $body = $self->{header_filter_dao}->read();
    		send_response($self, $body);
    		return 1;
    	}
    	if('body' eq $type) {
    		my $body = $self->{body_filter_dao}->read();
    		send_response($self, $body);
    		return 1;
    	} 
    	if('mbox_file' eq $type) {
    		my $path = $cgi->param('path');
    		my $mbox = $cgi->param('mbox');
    		unless(defined $path) {
    			die Wstk::WstkException->new('Missing paraments: path', 400);
    		}
    		unless(defined $mbox) {
    			die Wstk::WstkException->new('Missing paraments: mbox', 400);
    		}
    		my $mailbox = $self->{mailbox_dao}->get($mbox);
    		unless ($mailbox) {
    			die Wstk::WstkException->new('Unknown mailbox: '.$mbox, 404);
    		}
    		my $abs_path = $self->{maildir_dao}->get_abs_path($mailbox, $path);
			unless(-d $abs_path || -e $abs_path) {				
				die Wstk::WstkException->new('File not found: '.$path, 404);
			}
   			my $ctype = get_content_type($self, $path);
			send_binary($self, $ctype, $abs_path, $path);
			return 1;
    	}
    	die Wstk::WstkException->new('Unsupported type: '.$type, 400);
   	}   	
   	if($ENV{'REQUEST_METHOD'} eq 'PUT') {   		
   		my $data = $cgi->param('data');
   		my $empty_data = (!defined($data) || length($data) <=1);

    	if('header' eq $type) {
    		if($empty_data && $self->{header_filter_dao}->is_file_empty()) {
    			# do nothing
    		} else {
    			$self->{header_filter_dao}->write($data);
    		}
    		send_response($self, Wstk::Boolean::TRUE);
    		return 1;
    	}
    	if('body' eq $type) {
    		if($empty_data && $self->{body_filter_dao}->is_file_empty()) {
    			# do nothing
    		} else {
				$self->{body_filter_dao}->write($data);
    		}
    		send_response($self, Wstk::Boolean::TRUE);
    		return 1;
    	}
    	if('mbox_file' eq $type) {
    		my $path = $cgi->param('path');
    		my $mbox = $cgi->param('mbox');
    		unless(defined $path) {
    			die Wstk::WstkException->new('Missing paraments: path', 400);
    		}
    		unless(defined $mbox) {
    			die Wstk::WstkException->new('Missing paraments: mbox', 400);
    		}
    		my $mailbox = $self->{mailbox_dao}->get($mbox);
    		unless ($mailbox) {
    			die Wstk::WstkException->new('Unknown mailbox: '.$mbox, 404);
    		}
    		$self->{maildir_dao}->write_body($mailbox, $path, $data);
    		send_response($self, Wstk::Boolean::TRUE);
			return 1;
    	}
    	die Wstk::WstkException->new('Unsupported type: '.$type, 400);
   	}
	die Wstk::WstkException->new('Unsupported request type', 400);
}

# ---------------------------------------------------------------------------------------------------------------------------------
# helper methods
# ---------------------------------------------------------------------------------------------------------------------------------
sub get_content_type {
	my ($self, $fileName) = @_;                       
	if($fileName =~ /\.txt\z/) {
		return "text/plan";
	} elsif ($fileName =~ /\.html\z/) {
		return "text/html";
	} elsif ($fileName =~ /\.xml\z/) {
		return "text/xml";
	}
	return "application/octet-stream";
}
                        
sub send_response {
	my ($self, $response ) = @_;
	print "Content-type: text/plain; charset=UTF-8\n";
	print "Date: " . localtime( time() ) . "\n\n";
	print $response;
}
 
sub send_binary {
	my ($self, $ctype, $abs_path, $rel_path) = @_;
	my $bsize = io_get_file_size($abs_path);
	my ($rd, $bread, $buffer) = (0, 0, undef);
	#
	unless($bsize) {
		print "Content-type: ".$ctype."\n";
		print "Content-length: ".$bsize."\n";
		print "Date: " . localtime(time())."\n\n";
		return;
	}
	open(my $fio, "<".$abs_path) || die Wstk::WstkException->new("Couldn't open file: ".$rel_path, 500);
	#
	print "Content-type: ".$ctype."\n";
	print "Content-length: ".$bsize."\n";
	print "Date: " . localtime( time() ) . "\n\n";
	#
	while(1) {
		if($bread == $bsize) { last; }
		if($bread > $bsize) {
			$rd = $bsize - $bread;
			unless($rd) {last; }
		} else { $rd = 1024; }
		$rd = sysread($fio, $buffer, $rd);
		if($rd <= 0) { last; }
		$bread += $rd;
		print $buffer;
	}
	close($fio);
	return 1;
}


1;