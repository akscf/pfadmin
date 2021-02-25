# ******************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# ******************************************************************************************
package PFADMIN::DAO::MaildirDAO;

use strict;

use JSON qw(from_json);
use Log::Log4perl;
use File::Basename;
use File::Slurp;
use Wstk::Boolean;
use Wstk::WstkDefs qw(:ALL);
use Wstk::WstkException;
use Wstk::EntityHelper;
use Wstk::SearchFilterHelper;
use Wstk::Models::SearchFilter;
use PFADMIN::Defs qw(:ALL);
use PFADMIN::IOHelper;
use PFADMIN::DateHelper;
use PFADMIN::FilenameHelper;
use PFADMIN::Models::FileItem;

use constant ENTITY_CLASS_NAME => PFADMIN::Models::FileItem::CLASS_NAME;

sub new ($$;$) {
	my ( $class, $pfadmin) = @_;
	my $self = {
		logger          	=> Log::Log4perl::get_logger(__PACKAGE__),
		class_name      	=> $class,
		pfadmin         	=> $pfadmin,
		wstk				=> $pfadmin->{wstk},
		mailbox_base_path	=> $pfadmin->get_config('postfix','mailbox_base'),
        mailbox_chmod       => $pfadmin->get_config('postfix','mailbox_chmod', 0),
		mailbox_uid        	=> $pfadmin->get_config('postfix','mailbox_uid', 0),
		mailbox_gid        	=> $pfadmin->get_config('postfix','mailbox_gid', 0),
        mailbox_chmod_dir   => '0700',
        mailbox_chmod_file  => '0600',
		use_chown			=> 1
	};
	bless( $self, $class );
	#
	unless(defined $self->{mailbox_base_path}) {
		die Wstk::WstkException->new("Missing property: postfix.mailbox_base");
	}
	#
	$self->{logger}->debug('mailbox_base: '.$self->{mailbox_base_path});
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
sub mkdir {
    my ($self, $mailbox, $file_item) = @_;
    unless($mailbox) {
        die Wstk::WstkException->new("mailbox", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    validate_entity($self, $file_item);
    #
    my $mbox_home = ($self->{mailbox_base_path} .'/'. $mailbox->xpath());
    my $dir_name = $file_item->name();
    unless (is_valid_filename($dir_name)) {
        die Wstk::WstkException->new("Malformed file name", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    unless(is_empty($file_item->path())) {
        unless (is_valid_path($file_item->path())) {
            die Wstk::WstkException->new("Malformed path", RPC_ERR_CODE_INVALID_ARGUMENT);
        }
        $dir_name = ($file_item->path() .'/'. $file_item->name());
        $file_item->path($dir_name);
    } else {
        $file_item->path($dir_name);
    }
    $file_item->size(0);
    $file_item->directory(Wstk::Boolean::TRUE);
    $dir_name = $mbox_home .'/'. $dir_name;
    #
    if( -d $dir_name ) {
        die Wstk::WstkException->new($file_item->name(), RPC_ERR_CODE_ALREADY_EXISTS);
    }
    mkdir($dir_name);
    if($self->{use_chown}) { 
        chown($self->{mailbox_uid}, $self->{mailbox_gid}, $dir_name); 
        chmod(oct($self->{mailbox_chmod_dir}), $dir_name) if($self->{mailbox_chmod_dir});
    }
    $file_item->date( iso_format_datetime(io_get_file_lastmod($dir_name)) );
    return $file_item;
}

sub mkfile {
    my ($self, $mailbox, $file_item) = @_;
    unless($mailbox) {
        die Wstk::WstkException->new("mailbox", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    validate_entity($self, $file_item);
    #
    my $mbox_home = ($self->{mailbox_base_path} .'/'. $mailbox->xpath());
    my $file_name = $file_item->name();
    unless (is_valid_filename($file_name)) {
        die Wstk::WstkException->new("Malformed file name", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    unless(is_empty($file_item->path())) {
        unless (is_valid_path($file_item->path())) {
            die Wstk::WstkException->new("Malformed path", RPC_ERR_CODE_INVALID_ARGUMENT);
        }
        $file_name = ($file_item->path() .'/'. $file_item->name());
        $file_item->path($file_name);
    } else {
        $file_item->path($file_name);
    }
    $file_item->size(0);
    $file_item->directory(Wstk::Boolean::FALSE);
    $file_name = $mbox_home .'/'. $file_name;
    #
    if( -e $file_name ) {
        die Wstk::WstkException->new($file_item->name(), RPC_ERR_CODE_ALREADY_EXISTS);
    }
    open(my $ofile, '>', $file_name); close($ofile);
    if($self->{use_chown}) { 
        chown($self->{mailbox_uid}, $self->{mailbox_gid}, $ofile); 
        chmod(oct($self->{mailbox_chmod_file}), $ofile) if($self->{mailbox_chmod_file});
    }
    $file_item->date( iso_format_datetime(io_get_file_lastmod($file_name)) );
    return $file_item;

}

sub rename {
    my ($self, $mailbox, $new_name, $file_item) = @_;
    unless($mailbox) {
        die Wstk::WstkException->new("mailbox", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    validate_entity($self, $file_item);
    #    
    unless (is_valid_path($file_item->path())) {
        die Wstk::WstkException->new("Malformed path", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    unless (is_valid_filename($new_name)) {
        die Wstk::WstkException->new("new_name", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    #
    my $mbox_home = ($self->{mailbox_base_path} .'/'. $mailbox->xpath());
    my $old_path = $file_item->path();
    my $old_name = $mbox_home .'/'. $file_item->path();
    my $new_name_local = undef;

    if ($file_item->path() eq $file_item->name()) {
        $file_item->path($new_name);
        $file_item->name($new_name);
        $new_name_local = $mbox_home .'/'. $file_item->path();
    } else {
        my $tbase = dirname($file_item->path());
        $file_item->path($tbase .'/'. $new_name) ;
        $file_item->name($new_name);
        $new_name_local = $mbox_home .'/'. $file_item->path();
    }
    #
    if( -d $old_name ) {
        if( -d $new_name_local ) {
            die Wstk::WstkException->new($file_item->path(), RPC_ERR_CODE_ALREADY_EXISTS);
        }
        rename($old_name, $new_name_local);
        if($self->{use_chown}) { 
            chown($self->{mailbox_uid}, $self->{mailbox_gid}, $new_name_local); 
            chmod(oct($self->{mailbox_chmod_dir}), $new_name_local) if($self->{mailbox_chmod_dir});
        }
        return $file_item;
    }
    if( -e $old_name ) {
        if( -e $new_name_local ) {
            die Wstk::WstkException->new($file_item->path(), RPC_ERR_CODE_ALREADY_EXISTS);
        }
        rename($old_name, $new_name_local);
        if($self->{use_chown}) { 
            chown($self->{mailbox_uid}, $self->{mailbox_gid}, $new_name_local); 
            chmod(oct($self->{mailbox_chmod_file}), $new_name_local) if($self->{mailbox_chmod_file});
        }
        return $file_item;
    }
    die Wstk::WstkException->new($old_path, RPC_ERR_CODE_NOT_FOUND);
}

sub move {
    my ($self, $mailbox, $from, $to) = @_;
    unless($mailbox) {
        die Wstk::WstkException->new("mailbox", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    validate_entity($self, $from);
    validate_entity($self, $to);
    #
    my $to_path_name = ($to ? $to->path() : undef);
    unless (is_valid_path($to_path_name)) {
        die Wstk::WstkException->new("Malformed path 'to'", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    unless (is_valid_path($from->path())) {
        die Wstk::WstkException->new("Malformed path 'from'", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    my $mbox_home = ($self->{mailbox_base_path} .'/'. $mailbox->xpath());
    my $from_fqname = $mbox_home .'/'. $from->path();
    my $to_fqname = $mbox_home .'/'. $to_path_name;
    #
    if( -d $from_fqname ) {
        move($from_fqname, $to_fqname);
        if($self->{use_chown}) { 
            chown($self->{mailbox_uid}, $self->{mailbox_gid}, $to_fqname); 
            chmod(oct($self->{mailbox_chmod_dir}), $to_fqname) if($self->{mailbox_chmod_dir});
        }
        return PFADMIN::Models::FileItem->new(
            name => $from->name(), path => $to_path_name, size => $from->size(), date => $from->date(), directory => $from->directory()
        );
    }
    if( -e $from_fqname ) {
        move($from_fqname, $to_fqname);
		if($self->{use_chown}) { 
            chown($self->{mailbox_uid}, $self->{mailbox_gid}, $to_fqname); 
            chmod(oct($self->{mailbox_chmod_file}), $to_fqname) if($self->{mailbox_chmod_file});
        }
        return PFADMIN::Models::FileItem->new(
            name => $from->name(), path => $to_path_name, size => $from->size(), date => $from->date(), directory => $from->directory()
        );
    }
    die Wstk::WstkException->new($from->path(), RPC_ERR_CODE_NOT_FOUND);
}

sub delete {
    my ($self, $mailbox, $path) = @_;
    unless($mailbox) {
        die Wstk::WstkException->new("mailbox", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    unless (is_valid_path($path)) {
        die Wstk::WstkException->new("Malformed path", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    my $mbox_home = ($self->{mailbox_base_path} .'/'. $mailbox->xpath());
    my $tname = $mbox_home .'/'. $path;
    #    
    if( -d $tname ) {
        system("rm -rf ".$tname);
    }
    if( -e $tname ) {
        unlink($tname);
    }
    return 1;
}

sub get_meta {
    my ($self, $mailbox, $path) = @_;
    unless($mailbox) {
        die Wstk::WstkException->new("mailbox", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    unless (is_valid_path($path)) {
        die Wstk::WstkException->new("Malformed path", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    my $mbox_home = ($self->{mailbox_base_path} .'/'. $mailbox->xpath());
    my $tname = $mbox_home .'/'. $path;
    #
    if( -d $tname ) {
        return PFADMIN::Models::FileItem->new(
            name => basename($path),
            path => $path,
            date => iso_format_datetime( io_get_file_lastmod($tname) ),
            size => 0,
            directory => Wstk::Boolean::TRUE
        );
    }
    if( -e $tname ) {
        return PFADMIN::Models::FileItem->new(
            name => basename($path),
            path => $path,
            date => iso_format_datetime( io_get_file_lastmod($tname) ),
            size => io_get_file_size($tname),
            directory => Wstk::Boolean::FALSE
        );
    }
    return undef;
}

sub browse {
    my ($self, $mailbox, $path, $filter) = @_;
    unless($mailbox) {
        die Wstk::WstkException->new("mailbox", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    #
    my $ep = undef;
    my $fmask = filter_get_text($filter);
    my $mbox_home = ($self->{mailbox_base_path} .'/'. $mailbox->xpath());
    my $base_path_lenght = length($mbox_home) + 1;
    #
    if(is_empty($path)) {
        $ep = $mbox_home;
    } else {
        unless (is_valid_path($path)) {
            die Wstk::WstkException->new("Malformed path", RPC_ERR_CODE_INVALID_ARGUMENT);
        }
        $ep = ($mbox_home .'/'. $path);
        unless (-d $ep) {
            die Wstk::WstkException->new($path, RPC_ERR_CODE_NOT_FOUND);
        }
    }
    #
    my $dirs = [];
    list_dirs($self, $ep, sub {
        my $path = shift;
        my $fname = basename($path);
        #if($fmask) { }
        my $obj = PFADMIN::Models::FileItem->new(
            name => $fname,
            path => substr($path, $base_path_lenght),
            date => iso_format_datetime( io_get_file_lastmod($path) ),
            size => 0,
            directory => Wstk::Boolean::TRUE
        );
        push(@{$dirs}, $obj);
    });
    my $files = [];
    list_files($self, $ep, sub {
        my $path = shift;
        my $fname = basename($path);
        #if($fmask) { }
        my $obj = PFADMIN::Models::FileItem->new(
            name => $fname,
            path => substr($path, $base_path_lenght),
            date => iso_format_datetime( io_get_file_lastmod($path) ),
            size => io_get_file_size($path),
            directory => Wstk::Boolean::FALSE
        );
        push(@{$files}, $obj);
    });
    $dirs = [ sort { $a->{name} cmp $b->{name} } @{$dirs} ];
    $files = [ sort { $a->{name} cmp $b->{name} } @{$files} ];
    push(@{$dirs}, @{$files});
    #
    return $dirs;
}

# in mbox home
sub get_abs_path {
    my ($self, $mailbox, $path) = @_;
    #
    unless(defined($mailbox)) {
        die Wstk::WstkException->new("mailbox", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    my $ep = $self->{mailbox_base_path} .'/'. $mailbox->xpath();
    if(defined $path) {
        unless (is_valid_path($path)) {
            die Wstk::WstkException->new("path", RPC_ERR_CODE_INVALID_ARGUMENT);
        }
        $ep .= '/'.$path;
    }
    return $ep;
}

sub read_body {
    my ($self, $mailbox, $path) = @_;
    my $entity = undef;
    #
    unless(defined($mailbox)) {
        die Wstk::WstkException->new("mailbox", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    unless (is_valid_path($path)) {
        die Wstk::WstkException->new("path", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    my $ep = $self->{mailbox_base_path} .'/'. $mailbox->xpath() .'/'. $path;
    unless(-d $ep || -e $ep ) {
        die Wstk::WstkException->new($path, RPC_ERR_CODE_NOT_FOUND);
    }
    return read_file($ep);
}

sub write_body {
    my ($self, $mailbox, $path, $body) = @_;
    my $entity = undef;
    #
    unless (is_valid_path($path)) {
        die Wstk::WstkException->new("path", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    my $ep = $self->{mailbox_base_path} .'/'. $mailbox->xpath() .'/'. $path;
    if(-d $ep) {
        die Wstk::WstkException->new($path, RPC_ERR_CODE_NOT_FOUND);
    }
    write_file($ep, $body);
    return 1;
}

# ---------------------------------------------------------------------------------------------------------------------------------
sub validate_entity {
    my ($self, $entity) = @_;
    unless ($entity) {
        die Wstk::WstkException->new("entity", RPC_ERR_CODE_INVALID_ARGUMENT);
    }
    unless(entity_instance_of($entity, ENTITY_CLASS_NAME)) {
        die Wstk::WstkException->new("Type mismatch: " . entity_get_class($entity) . ", require: " . ENTITY_CLASS_NAME);
    }
}
    
sub list_dirs {
    my ( $self, $base, $cb ) = @_;
    #
    opendir( DIR, $base ) || die Wstk::WstkException->new("Couldn't read directory: $!");
    while( my $file = readdir(DIR) ) {
        my $cdir = "$base/$file";
        $cb->($cdir) if ( -d $cdir && ( $file ne "." && $file ne ".." ) );
    }
    closedir(DIR);
}

sub list_files {
    my ( $self, $base, $cb ) = @_;
    #
    opendir( DIR, $base ) || die Wstk::WstkException->new("Couldn't read directory: $!");
    while ( my $file = readdir(DIR) ) {
        my $cfile = "$base/$file";
        $cb->($cfile) if ( -f $cfile );
    }
    closedir(DIR);
}

1;