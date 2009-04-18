package Acme::Perl::VM::Scope;
use Mouse;

use Acme::Perl::VM qw(APVM_DEBUG);
use Acme::Perl::VM::B ();
use Scalar::Util ();

if(APVM_DEBUG){
	has saved_at => (
		is  => 'rw',

		builder => '_save',
	);
}

sub _save{
	my(undef, $file, $line) = caller(2);

	return join q{:}, $file, $line;
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

use Acme::Perl::VM qw(APVM_SCOPE deb @PL_cxstack);

has sv => (
	is  => 'ro',
	isa => 'B::SV',
);

sub leave{
	my($self) = @_;

	my $sv = $self->sv;
	return if $sv->REFCNT > 1 || $sv->STASH;

	if(APVM_SCOPE){
		deb "%s" . "clearsv %s\n", (q{>} x (@PL_cxstack+1)), $sv->object_2svref;
	}

	$sv->clear();
	return;
}

__PACKAGE__->meta->make_immutable();


package Acme::Perl::VM::Scope::Localizer; # ABSTRACT
use Mouse;
extends 'Acme::Perl::VM::Scope';

has gv => (
	is  => 'ro',
	isa => 'B::GV',
);

has old_ref => (
	is   => 'rw',
	isa => 'Ref',
);

sub BUILD{
	my($self) = @_;

	my $glob_ref = $self->gv->object_2svref;

	$self->old_ref( *{$glob_ref}{ $self->save_type } );
	*{$glob_ref} = $self->new_ref();

	return;
}

sub sv{
	my($self) = @_;
	return B::svref_2object(*{$self->gv->object_2svref}{ $self->save_type });
}

sub leave{
	my($self) = @_;

	my $glob_ref = $self->gv->object_2svref;
	*{$glob_ref} = $self->old_ref;
	return;
}

__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Scope::Scalar;
use Mouse;
extends 'Acme::Perl::VM::Scope::Localizer';
sub save_type(){ 'SCALAR' }
sub new_ref{
	my $scalar;
	return \$scalar;
}
__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Scope::Array;
use Mouse;
extends 'Acme::Perl::VM::Scope::Localizer';
sub save_type(){ 'ARRAY' }
sub new_ref{
	return [];
}
__PACKAGE__->meta->make_immutable();
package Acme::Perl::VM::Scope::Hash;
use Mouse;
extends 'Acme::Perl::VM::Scope::Localizer';
sub save_type(){ 'HASH' }
sub new_ref{
	return {};
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
