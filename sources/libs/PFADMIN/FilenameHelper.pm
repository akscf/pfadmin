# ******************************************************************************************
#
# (C)2021 aks
# https://github.com/akscf/
# ******************************************************************************************
package PFADMIN::FilenameHelper;

use Exporter qw(import);
our @EXPORT = qw(is_valid_path is_valid_filename);

sub is_valid_path {
	my ($path) = @_;
	return undef unless(defined($path));
	#
	return undef if($path =~ /(\.\.|\.\/)/);
	return 1;
}

sub is_valid_filename {
	my ($fname) = @_;
	return undef unless(defined($fname));
	#
	return 1 if($fname =~ /^([a-zA-Z0-9\s\-\.\_])+$/);
	return undef;
}

1;
