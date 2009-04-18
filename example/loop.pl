#!perl -w

use strict;
use Acme::Perl::VM;

sub f{
	my($x) = @_;
	$x += 1;
}

run_block {
	my $i;

	for($i = 0; $i < 1000; $i++){
		f($i);

		last FOO if $i == 100;
	}

	print $i, "\n";
};

print B::timing_info(), "\n";
