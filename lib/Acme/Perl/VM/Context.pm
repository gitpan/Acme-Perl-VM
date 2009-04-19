package Acme::Perl::VM::Context;
use Mouse;

sub type{
	my $type = ref( $_[0] );
	$type =~ s/^Acme::Perl::VM::Context:://;

	return $type;
}

__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Context::BLOCK;
use Mouse;
use Acme::Perl::VM qw($PL_comppad);

extends 'Acme::Perl::VM::Context';

has gimme => (
	is  => 'rw',
	isa => 'Int',
);
has oldsp => (
	is  => 'rw',
	isa => 'Int',
);
has oldcop => (
	is  => 'rw',
	isa => 'B::COP',
);
has oldmarksp => (
	is  => 'rw',
	isa => 'Int',
);
has oldscopesp => (
	is  => 'rw',
	isa => 'Int',
);

sub CURPAD_SAVE{
	my($cx) = @_;

	$cx->oldcomppad($PL_comppad);
	return;
}

sub CURPAD_SV{
	my($cx, $ix) = @_;

	return $cx->oldcomppad->ARRAYelt($ix);
}


__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Context::SUB;
use Mouse;
extends 'Acme::Perl::VM::Context::BLOCK';

has cv => (
	is  => 'rw',
	isa => 'B::CV',
);

has olddepth => (
	is  => 'rw',
	isa => 'Int',
);
has hasargs => (
	is  => 'rw',
	isa => 'Bool',
);

has retop => (
	is  => 'rw',
	isa => 'B::OBJECT', # NULL or B::OP
);

has oldcomppad => (
	is  => 'rw',
	isa => 'B::AV',
);
has savearray => (
	is  => 'rw',
	isa => 'ArrayRef',
);
has argarray => (
	is  => 'rw',
	isa => 'B::AV',
);

has lval => (
	is  => 'rw',
	isa => 'Bool',
);

__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Context::EVAL;
use Mouse;
extends 'Acme::Perl::VM::Context::BLOCK';

__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Context::LOOP;
use Mouse;
extends 'Acme::Perl::VM::Context::BLOCK';

has label => (
	is  => 'rw',
	isa => 'Maybe[Str]',
);
has resetsp => (
	is  => 'rw',
	isa => 'Int',
);
has myop => (
	is  => 'rw',
	isa => 'B::LOOP',
);
has nextop => (
	is  => 'rw',
	isa => 'B::OP',
);

sub ITERVAR(){ undef }

__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Context::FOREACH;
use Mouse;
use Acme::Perl::VM::B qw(USE_ITHREADS);
extends 'Acme::Perl::VM::Context::LOOP';

has padvar => (
	is  => 'rw',
	isa => 'Bool',

);
has for_def => (
	is => 'rw',
	isa => 'Bool',
);

if(USE_ITHREADS){
	has iterdata => (
		is => 'rw',
	);
	has oldcomppad => (
		is  => 'rw',
		isa => 'B::AV',
	);
}
else{
	has itervar => (
		is => 'rw',
	);
}

has itersave => (
	is => 'rw',
);
has iterlval => (
	is  => 'rw',
);
has iterary => (
	is  => 'rw',
);
has iterix => (
	is  => 'rw',
	isa => 'Int',
);
has itermax => (
	is  => 'rw',
	isa => 'Int',
);

sub type(){ 'LOOP' } # this is a LOOP


sub ITERVAR{
	my($cx) = @_;
	if(USE_ITHREADS){
		if($cx->padvar){
			return $cx->CURPAD_SV($cx->iterdata);
		}
		else{
			return $cx->iterdata->SV;
		}
	}
	else{
		return $cx->itervar;
	}
}
sub ITERDATA_SET{
	my($cx, $idata) = @_;
	if(USE_ITHREADS){
		$cx->CURPAD_SAVE();
		$cx->iterdata($idata);
	}
	else{
		$cx->itervar($idata);
	}
	$cx->itersave($cx->ITERVAR);
}

__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Context::GivenWhen;
use Mouse;
extends 'Acme::Perl::VM::Context::BLOCK';

__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Context::GIVEN;
use Mouse;
extends 'Acme::Perl::VM::Context::GivenWhen';

__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Context::WHEN;
use Mouse;
extends 'Acme::Perl::VM::Context::GivenWhen';

__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Context::SUBST;
use Mouse;
extends 'Acme::Perl::VM::Context';

__PACKAGE__->meta->make_immutable();

__END__

=head1 NAME

Acme::Perl::VM::Context - Context classes for APVM

=head1 SYNOPSIS

	use Acme::Perl::VM;

=head1 SEE ALSO

L<Acme::Perl::VM>.

=cut
