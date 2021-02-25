# ******************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# ******************************************************************************************
package PFADMIN::Models::Mailbox;

use strict;
use constant CLASS_NAME => __PACKAGE__;

sub new ($$) {
        my ($class, %args) = @_;
        my %t = (
                class           => CLASS_NAME,                
                enabled         => undef, # true/false
                domainId        => undef, # domain ref
                name            => undef, # email address
                password        => undef, # dovecot hash                
                plainPassword   => undef, # reserved
                title           => undef, # user name
                path            => undef, # mbox path
                xpath           => undef, # abs path (uses in pfadmin)
                quota           => undef,
                description     => undef,
                options         => undef 
        );
        my $self= {%t, %args};
        bless( $self, $class );
}

sub get_class_name {
        my ($self) = @_;
        return $self->{class};
}

sub enabled {
        my ($self, $val) = @_;
        return $self->{enabled} unless(defined($val));
        $self->{enabled} = $val;
}

sub domainId {
        my ($self, $val) = @_;
        return $self->{domainId} unless(defined($val));
        $self->{domainId} = $val;
}

sub name {
        my ($self, $val) = @_;
        return $self->{name} unless(defined($val));
        $self->{name} = $val;
}

sub password {
        my ($self, $val) = @_;
        return $self->{password} unless(defined($val));
        $self->{password} = $val;
}

sub plainPassword {
        my ($self, $val) = @_;
        return $self->{plainPassword} unless(defined($val));
        $self->{plainPassword} = $val;
}

sub title {
        my ($self, $val) = @_;
        return $self->{title} unless(defined($val));
        $self->{title} = $val;
}

sub path {
        my ($self, $val) = @_;
        return $self->{path} unless(defined($val));
        $self->{path} = $val;
}

sub xpath {
        my ($self, $val) = @_;
        return $self->{xpath} unless(defined($val));
        $self->{xpath} = $val;
}

sub quota {
        my ($self, $val) = @_;
        return $self->{quota} unless(defined($val));
        $self->{quota} = $val;
}

sub description {
        my ($self, $val) = @_;
        return $self->{description} unless(defined($val));
        $self->{description} = $val;
}


sub options {
        my ($self, $val) = @_;
        return $self->{options} unless(defined($val));
        $self->{options} = $val;
}

sub export {
        return undef;
}

1;
