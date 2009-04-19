#!perl -w

use strict;
use Acme::Perl::VM::Run;

sub hello{
	my($s) = @_;

	print "Hello, $s world!\n";
}

hello("APVM");
