package Acme::Perl::VM::B;

use strict;
use warnings;

use Exporter qw(import);

use B();
our @EXPORT = grep{ /^[A-Z]/ } @B::EXPORT_OK; # constants
push @EXPORT, qw(sv_undef svref_2object);
B->import(@EXPORT);

unless(defined &OPpPAD_STATE){
	constant->import(OPpPAD_STATE => 0x00);
	push @EXPORT, qw(OPpPAD_STATE);
}

push @EXPORT, qw(NULL TRUE FALSE USE_ITHREADS sv_yes sv_no);
use constant {
	NULL         => bless(\do{ my $addr = 0 }, 'B::SPECIAL'),
	TRUE         => 1,
	FALSE        => 0,
	USE_ITHREADS => defined(&B::regex_padav),

	sv_yes       => B::sv_yes,
	sv_no        => B::sv_no,
};

package
	B::OBJECT;

sub dump{
	my($obj) = @_;
	require B::Debug;

	$obj->debug;
	return;
}

package
	B::SPECIAL;

my %special_sv = (
	${ B::sv_undef() } => \(undef),
	${ B::sv_yes() }   => \(1 == 1),
	${ B::sv_no() }    => \(1 != 1),
);

sub object_2svref{
	my($obj) = @_;

	return $special_sv{ $$obj } || do{
		my $name = $B::specialsv_name[$$obj] || sprintf 'SPECIAL(0x%x)', $$obj;
		Carp::confess($name, ' is not a normal SV object');
	};
}

sub setval{
	my($obj) = @_;

	my $name = $B::specialsv_name[$$obj] || sprintf 'SPECIAL(0x%x)', $$obj;
	Acme::Perl::VM::apvm_die("Modification of read-only value ($name) attempted");
}

package
	B::SV;

# for sv_setsv()
sub setsv{
	my($dst, $src) = @_;

	my $dst_ref = $dst->object_2svref;
	${$dst_ref} = ${$src->object_2svref};
	bless $dst, ref(B::svref_2object( $dst_ref ));

	return $dst;
}

# for sv_setpv()/sv_setiv()/sv_setnv() etc.
sub setval{
	my($dst, $val) = @_;

	my $dst_ref = $dst->object_2svref;
	${$dst_ref} = $val;
	bless $dst, ref(B::svref_2object( $dst_ref ));

	return $dst;
}

sub clear{
	my($sv) = @_;
	$sv->setsv(B::sv_undef);
	return;
}

sub toCV{
	my($sv) = @_;
	Carp::croak(sprintf 'Cannot convert %s to a CV', B::class($sv));
}

package
	B::CV;

sub toCV{ $_[0] }

package
	B::GV;

sub toCV{ $_[0]->CV }

package
	B::AV;

sub setsv{
	my($sv) = @_;
	Carp::croak('Cannot call setsv() for ' . B::class($sv));
}

sub clear{
	my($sv) = @_;

	@{$sv->object_2svref} = ();
	return;
}

sub fetch{
	my($av, $ix, $lval) = @_;

	if($lval){
		return B::svref_2object(\$av->object_2svref->[$ix]);
	}
	else{
		return $av->ARRAYelt($ix);
	}
}

unless(__PACKAGE__->can('OFF')){
	# some versions of B::Debug requires this
	constant->import(OFF => 0);
}

package
	B::HV;

*setsv = \&B::AV::setsv;

sub clear{
	my($sv) = @_;

	%{$sv->object_2svref} = ();
	return;
}

sub fetch{
	my($hv, $key, $lval) = @_;

	if($lval){
		return B::svref_2object(\$hv->object_2svref->{$key});
	}
	else{
		my $ref = $hv->object_2svref;

		if(exists $ref->{$key}){
			return B::svref_2object($ref->{$key});
		}
		else{
			return Acme::Perl::VM::B::NULL;
		}
	}
}


1;

__END__

=head1 NAME

Acme::Perl::VM::B - Extra B functions and constants

=head1 SYNOPSIS

	use Acme::Perl::VM;

=head1 SEE ALSO

L<Acme::Perl::VM>.

=cut
