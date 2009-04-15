package Acme::Perl::VM::Scope;
use Mouse;

use Acme::Perl::VM qw(APVM_DEBUG);
use Acme::Perl::VM::B ();

if(APVM_DEBUG){
	has saved_at => (
		is  => 'rw',

		default => sub{
			my(undef, $file, $line) = caller(2);

			return join q{:}, $file, $line;
		},
	);
}

__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Scope::Value;
use Mouse;
extends 'Acme::Perl::VM::Scope';

has value => (
	is  => 'ro',

	required => 1,
);

has value_ref => (
	is  => 'ro',
	isa => 'Ref',

	required => 1,
);

sub leave{
	my($self) = @_;

	${ $self->value_ref } = $self->value;
	return;
}

__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Scope::Comppad;
use Mouse;
extends 'Acme::Perl::VM::Scope';

has comppad => (
	is  => 'ro',
	isa => 'Maybe[B::AV]',
);

sub leave{
	my($self) = @_;

	my $comppad = $self->comppad;
	$Acme::Perl::VM::PL_comppad = $comppad;
	@Acme::Perl::VM::PL_curpad  = $comppad ? ($comppad->ARRAY) : ();
	return;
}

__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Scope::Clearsv;
use Mouse;
extends 'Acme::Perl::VM::Scope';

has sv => (
	is  => 'ro',
	isa => 'B::SV',
);

sub leave{
	my($self) = @_;

	$self->sv->clear();
	return;
}

__PACKAGE__->meta->make_immutable();

__END__

=head1 NAME

Acme::Perl::VM::Scope - Scope classes for APVM

=head1 SYNOPSIS

	use Acme::Perl::VM;

=head1 SEE ALSO

L<Acme::Perl::VM>.

=cut
