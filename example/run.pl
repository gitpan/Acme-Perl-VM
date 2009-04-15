#!perl -w

use strict;
use Acme::Perl::VM::Run;

sub Foo::hello{
	my(undef, $msg) = @_;

	print "Hello, $msg world!\n";
}

for(my $i = 1; $i < 3; $i++){
	print "[$i]";
	Foo->hello('APVM');
}

