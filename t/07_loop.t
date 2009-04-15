#!perl -w

use strict;
use Test::More tests => 12;

use Acme::Perl::VM;
use Acme::Perl::VM qw(:perl_h);

my $j = 10;
my $x = run_block{
	my $i;
	for($i = 1; $i < 10; $i++){
		$j++;
	}
	return $i;
};
is $x, 10, 'for loop';
is $j, 19, 'for loop';

$x = run_block{
	my $c = 0;

	for(my $i = 0; $i < 10; $i++){
		for(my $j = 0; $j < 10; $j++){
			$c += 10;
		}
	}
	return $c;
};
is $x, 10*10*10, 'nested for loop';

$x = run_block{
	my $i = 0;
	while($i < 10){
		$i++;
	}
	return $i;
};
is $x, 10, 'while loop';
$x = run_block{
	my $c = 0;

	my $i = 0;
	while($i < 10){
		$i++;

		my $j = 0;
		while($j < 10){
			$j++;

			$c += 10;
		}
	}
	return $c;
};
is $x, 10*10*10, 'nested while loop';

$x = run_block{
	for(;;){
		return 42;
	}
};
is $x, 42, 'return in loop';

is_deeply \@PL_stack,      [], '@PL_stack is empty';
is_deeply \@PL_markstack,  [], '@PL_markstack is empty';
is_deeply \@PL_scopestack, [], '@PL_scopestack is empty';
is_deeply \@PL_cxstack,    [], '@PL_cxstack is empty';
is_deeply \@PL_savestack,  [], '@PL_savestack is empty';
is_deeply \@PL_tmps,       [], '@PL_tmps is empty';
