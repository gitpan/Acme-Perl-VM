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


__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Context::SUB;
use Mouse;
use Acme::Perl::VM qw($PL_comppad);
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


sub CURPAD_SAVE{
	my($cx) = @_;

	$cx->oldcomppad($PL_comppad);
	return;
}

sub CURPAD_SV{
	my($cx, $ix) = @_;

	return$cx->oldcomppad->ARRAYelt($ix);
}


__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Context::EVAL;
use Mouse;
extends 'Acme::Perl::VM::Context::BLOCK';

__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Context::LOOP;
use Mouse;
use Acme::Perl::VM qw(is_not_null);
use Acme::Perl::VM::B qw(USE_ITHREADS NULL);

extends 'Acme::Perl::VM::Context::BLOCK';

has padloop => (
	is  => 'rw',
	isa => 'Bool',
);

has label => (
	is  => 'rw',
	isa => 'Maybe[Str]',
);
has resetsp => (
	is  => 'rw',
	isa => 'Int',
);
has my_op => (
	is  => 'rw',
	isa => 'B::LOOP',
);
has next_op => (
	is  => 'rw',
	isa => 'B::OP',
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
		isa => 'Ref[B::SV]',
	);
}
has itersave => (
	is => 'rw',
	isa => 'Maybe[B::SV]',
);
has iterlval => (
	is  => 'rw',
	isa => 'Maybe[B::SV]',
);
has iterary => (
	is  => 'rw',
	isa => 'Maybe[B::SV]',
);
has iterix => (
	is  => 'rw',
	isa => 'Int',
);
has itermax => (
	is  => 'rw',
	isa => 'Int',
);

sub ITERVAR{
	my($cx) = @_;
	if(USE_ITHREADS){
		my $itervar = $cx->iterdata
			? $cx->padloop
				? \$cx->CURPAD_SV($cx->iterdata)
				: \$cx->iterdata->SV
			: NULL;
		return is_not_null($itervar) ? $itervar : undef;
	}
	else{
		return $cx->itervar;
	}
}
sub ITERDATA_SET{
	my($cx, $idata) = @_;
	if(USE_ITHREADS){
		$cx->CURPAD_SAVE();
		if(is_not_null($idata)){
			$cx->iterdata($idata);
		}
	}
	else{
		if($idata){
			$cx->itervar($idata);
		}
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
