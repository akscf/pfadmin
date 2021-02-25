# ******************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# ******************************************************************************************
package PFADMIN::Models::Domain;

use strict;
use constant CLASS_NAME => __PACKAGE__;

sub new ($$) {
        my ($class, %args) = @_;
        my %t = (
                class           => CLASS_NAME,
                name            => undef,
                description     => undef
        );
        my $self= {%t, %args};
        bless( $self, $class );
}

sub get_class_name {
        my ($self) = @_;
        return $self->{class};
}

sub name {
        my ($self, $val) = @_;
        return $self->{name} unless(defined($val));
        $self->{name} = $val;
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
