# ******************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# ******************************************************************************************
package PFADMIN::Models::Alias;

use strict;
use constant CLASS_NAME => __PACKAGE__;

sub new ($$) {
        my ($class, %args) = @_;
        my %t = (
                class           => CLASS_NAME,
                domainId        => undef, # domain ref
                enabled         => undef, # true / false
                address         => undef, # email address
                targets         => undef, # aliases
                description     => undef
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

sub address {
        my ($self, $val) = @_;
        return $self->{address} unless(defined($val));
        $self->{address} = $val;
}

sub targets {
        my ($self, $val) = @_;
        return $self->{targets} unless(defined($val));
        $self->{targets} = $val;
}

sub description {
        my ($self, $val) = @_;
        return $self->{description} unless(defined($val));
        $self->{description} = $val;
}

sub export {
        return undef;
}

1;
