#!perl -w

use strict;
use Acme::Perl::VM;

sub f{
	my($x) = @_;
	print $x, "\r";
	return $x;
}

run_block {
	local $| = 1;

	my $sum = 0;
	for(my $i = 1; $i <= 1000; $i++){
		$sum += f($i);
	}

	print "\n", $sum, "\n";
};

print B::timing_info(), "\n";
