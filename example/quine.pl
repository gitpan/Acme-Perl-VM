#!perl -w

use strict;
use Acme::Perl::VM;

open my $in, '<', $0;
run_block{
	while(<$in>){
		print;
	}
};
