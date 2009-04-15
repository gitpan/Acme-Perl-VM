#!perl -w

use strict;
use Acme::Perl::VM;

sub hello{
	my($s) = @_;

	print "Hello, $s world!\n";
}

run_block {
	hello("Acme::Perl::VM");
	hello("APVM");
};
