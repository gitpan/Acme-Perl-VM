package Acme::Perl::VM::Scope;
use Mouse;

use Acme::Perl::VM qw(APVM_DEBUG $PL_op);
use Acme::Perl::VM::B ();
use Scalar::Util ();

if(APVM_DEBUG){
	has saved_at => (
		is  => 'rw',

		builder => '_save',
	);
}

sub type{
	my($self) = @_;
	my $class = ref $self;
	$class =~ s/^Acme::Perl::VM::Scope:://;
	return $class;
}

sub _save{
	my(undef, $file, $line) = caller(2);
	my $proc = $PL_op ? ('in '.$PL_op->name.' ') : '';
	return $proc . sprintf q{at %s line %d}, $file, $line;
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

package Acme::Perl::VM::Scope::Tmps;
use Mouse;
extends 'Acme::Perl::VM::Scope::Value';
__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Scope::Comppad;
use Mouse;
extends 'Acme::Perl::VM::Scope';

use Acme::Perl::VM qw($PL_comppad $PL_comppad_name @PL_curpad);

has comppad => (
	is  => 'ro',
	isa => 'Maybe[B::AV]',
);
has comppad_name => (
	is  => 'ro',
	isa => 'Maybe[B::AV]',
);

sub leave{
	my($self) = @_;

	my $comppad = $self->comppad;
	$PL_comppad = $comppad;
	@PL_curpad  = $comppad ? ($comppad->ARRAY) : ();

	$PL_comppad_name = $self->comppad_name;
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
	if(APVM_SCOPE){
		my $skipped = $sv->REFCNT > 1 || $sv->STASH;
		deb "%s" . "clearsv %s saved at %s%s\n", (q{>} x (@PL_cxstack+1)),
			$self->sv->object_2svref, $self->saved_at, $skipped ? ' (skipped)' : '';
	}
	return if $sv->REFCNT > 1 || $sv->STASH;


	$sv->clear();
	return;
}

__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Scope::Padsv;
use Mouse;
extends 'Acme::Perl::VM::Scope';

use Acme::Perl::VM qw(APVM_SCOPE deb @PL_cxstack ddx);

has value => (
	is  => 'ro',
);
has comppad => (
	is  => 'ro',
	isa => 'B::AV',
);
has off => (
	is  => 'ro',
	isa => 'Int',
);

sub leave{
	my($self) = @_;

	my $comppad_ref = $self->comppad->object_2svref;

	if(APVM_SCOPE){
		my $old = ddx([${ $self->comppad->ARRAYelt($self->off)->object_2svref }]);
		my $new = ddx([$self->value]);
		$old->Indent(0);
		$new->Indent(0);
		deb "%s" . "padsv (%s -> %s) saved at %s\n", (q{>} x (@PL_cxstack+1)),
			$old->Dump, $new->Dump, $self->saved_at;
	}

	#delete $comppad_ref->[$self->off];
	$comppad_ref->[$self->off] = $self->value;

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

sub save_type;
sub create_ref;
sub sv;

sub BUILD{
	my($self) = @_;

	my $glob_ref = $self->gv->object_2svref;

	$self->old_ref( *{$glob_ref}{ $self->save_type } );
	*{$glob_ref} = $self->create_ref();

	return;
}

sub leave{
	my($self) = @_;

	*{$self->gv->object_2svref} = $self->old_ref;
	return;
}

__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Scope::Scalar;
use Mouse;
extends 'Acme::Perl::VM::Scope::Localizer';
sub save_type(){ 'SCALAR' }
sub create_ref{
	my($self) = @_;
	return \local(${*{ $self->gv->object_2svref }}); # to copy MAGIC
}
sub sv{
	my($self) = @_;
	return $self->gv->SV;
}
__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Scope::Array;
use Mouse;
extends 'Acme::Perl::VM::Scope::Localizer';
sub save_type(){ 'ARRAY' }
sub create_ref{
	my($self) = @_;
	return \local @{*{ $self->gv->object_2svref }};
}
sub sv{
	my($self) = @_;
	return $self->gv->AV;
}
__PACKAGE__->meta->make_immutable();

package Acme::Perl::VM::Scope::Hash;
use Mouse;
extends 'Acme::Perl::VM::Scope::Localizer';
sub save_type(){ 'HASH' }
sub create_ref{
	my($self) = @_;
	return \local %{*{ $self->gv->object_2svref }};
}
sub sv{
	my($self) = @_;
	return $self->gv->HV;
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
