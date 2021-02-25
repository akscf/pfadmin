# ******************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# ******************************************************************************************
package PFADMIN::Models::FilterRule;

use strict;
use constant CLASS_NAME => __PACKAGE__;

sub new ($$) {
        my ($class, %args) = @_;
        my %t = (
                class           => CLASS_NAME,
                id              => undef,
                enabled         => undef, # true / false
                regex           => undef,
                action		=> undef, # reject/permit/redirect/...
                message         => undef,
                description	=> undef
        );
        my $self= {%t, %args};
        bless( $self, $class );
}

sub get_class_name {
        my ($self) = @_;
        return $self->{class};
}

sub id {
        my ($self, $val) = @_;
        return $self->{id} unless(defined($val));
        $self->{id} = $val;
}

sub enabled {
        my ($self, $val) = @_;
        return $self->{enabled} unless(defined($val));
        $self->{enabled} = $val;
}

sub regex {
        my ($self, $val) = @_;
        return $self->{regex} unless(defined($val));
        $self->{regex} = $val;
}

sub action {
        my ($self, $val) = @_;
        return $self->{action} unless(defined($val));
        $self->{action} = $val;
}

sub message {
        my ($self, $val) = @_;
        return $self->{message} unless(defined($val));
        $self->{message} = $val;
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
