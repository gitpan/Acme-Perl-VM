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
	foreach my $i(1 .. 1000){
		$sum += f($i);
	}

	print "\n", $sum, "\n";
};

print B::timing_info(), "\n";
