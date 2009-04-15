#!perl -w

use strict;
use Acme::Perl::VM;

run_block {
	print "Hello,", " world!", "\n";
};

my $x = shift || 0;

run_block {
	if($x){
		print $x, " is true\n";
	}
	else{
		print $x, " is false\n";
	}
};
