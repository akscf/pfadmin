# *****************************************************************************************
# Copyright (C) AlexandrinKS
# https://akscf.me/
# *****************************************************************************************
package PFADMIN::Defs;

use constant ROLE_ADMIN  	 => 'ADMIN';
use constant ROLE_ANONYMOUS  => 'ANONYMOUS';

use Exporter qw(import);
our @EXPORT_OK = qw(
    ROLE_ADMIN
    ROLE_ANONYMOUS
);
our %EXPORT_TAGS = ( 'ALL' => \@EXPORT_OK );

1;
