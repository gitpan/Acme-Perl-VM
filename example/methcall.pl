#!perl -w

use strict;
use Acme::Perl::VM;

sub Foo::hello{
	my(undef, $s) = @_;

	print "Hello, $s world!\n";
}

run_block {
	Foo->hello("Acme::Perl::VM");
	Foo->hello("APVM");
};
