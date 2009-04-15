package Acme::Perl::VM;

use 5.008_001;
use strict;
use warnings;

BEGIN{
	require version; our $VERSION = version::qv('0.0.1_02');
}

use constant APVM_DEBUG  => ($ENV{APVM_DEBUG} || do{ our $VERSION->is_alpha || 0 });
use constant {
	APVM_TRACE => scalar(APVM_DEBUG =~ /\b trace \b/xmsi),
	APVM_SCOPE => scalar(APVM_DEBUG =~ /\b scope \b/xmsi),

	APVM_DUMMY => scalar(APVM_DEBUG =~ /\b dummy \b/xmsi),
};

use Exporter qw(import);
BEGIN{
	our @EXPORT      = qw(run_block call_sv);
	our @EXPORT_OK   = qw(
		$PL_op $PL_curcop
		@PL_stack @PL_markstack @PL_cxstack @PL_scopestack @PL_savestack @PL_tmps
		$PL_tmps_floor
		$PL_comppad @PL_curpad
		$PL_runops

		PUSHMARK POPMARK TOPMARK
		PUSH POP TOP SET SETval
		GET_TARGET
		GET_TARGETSTACKED
		GET_ATARGET

		PUSHBLOCK POPBLOCK
		PUSHSUB POPSUB
		PUSHLOOP POPLOOP

		dounwind

		ENTER LEAVE LEAVE_SCOPE
		SAVETMPS FREETMPS
		SAVE SAVECOMPPAD SAVECLEARSV

		OP_GIMME GIMME_V LVRET

		PAD_SV PAD_SET_CUR_NOSAVE PAD_SET_CUR
		CX_CURPAD_SAVE CX_CURPAD_SV

		dopoptosub

		deb apvm_warn apvm_die

		GVOP_gv

		sv_newmortal sv_mortalcopy
		SvPV SvNV SvTRUE
		defoutgv

		sv_defined is_null is_not_null
		mark_list
		not_implemented
		dump_object dump_value dump_stacks
		APVM_DEBUG
	);
	our %EXPORT_TAGS = (
		perl_h => \@EXPORT_OK,
	);
}

use Acme::Perl::VM::Context;
use Acme::Perl::VM::Scope;
use Acme::Perl::VM::PP;
use Acme::Perl::VM::B;

use Carp ();

if(APVM_DEBUG){
	require Carp::Heavy;
	require Carp::Always;
}

our $PL_op;
our $PL_curcop;

our @PL_stack;
our @PL_markstack;
our @PL_cxstack;
our @PL_scopestack;
our @PL_savestack;
our @PL_tmps;

our $PL_tmps_floor;

our $PL_comppad;
our @PL_curpad;

our $PL_runops = \&runops_standard;

{
	our %ppaddr;
	while(my($name, $value) = each %Acme::Perl::VM::PP::){
		if($name =~ s/^pp_//){
			$ppaddr{$name} = *{$value}{CODE};
		}
	}
}

if(APVM_TRACE){
	$PL_runops = \&runops_trace;
}

sub runops_standard{ # run.c
	our %ppaddr;
	1 while(is_not_null( $PL_op = &{$ppaddr{ $PL_op->name } || not_implemented($PL_op->ppaddr)} ));
	return;
}

sub runops_trace{
	our %ppaddr;

	while(is_not_null( $PL_op = &{$ppaddr{ $PL_op->name } || not_implemented($PL_op->ppaddr)} )){

		deb '%s%s', (q{.} x @PL_cxstack), uc($PL_op->name);
		if($PL_op->isa('B::COP')){
			deb ' (%s:%d)', $PL_op->file, $PL_op->line;
		}
		elsif($PL_op->name eq 'entersub'){
			my $gv = TOP;
			if(!$gv->isa('B::GV')){
				$gv = $gv->GV;
			}
			deb ' &%s::%s', $gv->STASH->NAME, $gv->NAME;
		}

		deb "\n";
	}
	return;
}

sub deb{
	my($fmt, @args) = @_;
	printf STDERR $fmt, @args if APVM_DEBUG;
	return;
}

sub mess{ # util.c
	my($fmt, @args) = @_;
	my $msg = sprintf $fmt, @args;

	return sprintf "[APVM] %s in %s at %s line %d.\n",
		$msg, $PL_op->desc, $PL_curcop->file, $PL_curcop->line;
}

sub apvm_warn{
	warn mess(@_)
}
sub apvm_die{
	die mess(@_);
}

sub PUSHMARK(){
	push @PL_markstack, $#PL_stack;
	return;
}
sub POPMARK(){
	return pop @PL_markstack;
}
sub TOPMARK(){
	return $PL_markstack[-1];
}

sub PUSH{
	my($sv) = @_;

	if(!defined $sv){
		$PL_op->dump();
		Carp::confess('PUSH(NULL)');
	}

	push @PL_stack, $sv;
	return;
}
sub POP(){
	return pop @PL_stack;
}
sub TOP(){
	return $PL_stack[-1];
}
sub SET{
	my($sv) = @_;
	$PL_stack[-1] = $sv;
	return;
}
sub SETval{
	my($val) = @_;
	$PL_stack[-1] = PAD_SV( $PL_op->targ )->setval($val);
	return;
}

sub GET_TARGET{
	return PAD_SV($PL_op->targ);
}
sub GET_TARGETSTACKED{
	return $PL_op->flags & OPf_STACKED ? POP : PAD_SV($PL_op->targ);
}
sub GET_ATARGET{
	return $PL_op->flags & OPf_STACKED ? $PL_stack[$#PL_stack-1] : PAD_SV($PL_op->targ);
}

sub PUSHBLOCK{
	my($type, $sp, $gimme) = @_;

	my $cx_class = 'Acme::Perl::VM::Context::' . $type;

	push @PL_cxstack, $cx_class->new(
		oldsp      => $sp,
		oldcop     => $PL_curcop,
		oldmarksp  => $#PL_markstack,
		oldscopesp => $#PL_scopestack,
		gimme      => $gimme,
	);

	if(APVM_SCOPE){
		deb "%s" . "Entering %s\n", (q{>} x @PL_cxstack), $type;
	}

	return;
}

sub POPBLOCK{
	my $cx = pop @PL_cxstack;

	$PL_curcop      = $cx->oldcop;
	$#PL_markstack  = $cx->oldmarksp;
	$#PL_scopestack = $cx->oldscopesp;

	if(APVM_SCOPE){
		deb "%s" . "Leaving %s\n", (q{>} x (1+@PL_cxstack)), $cx->type;
	}

	return $cx;
}

sub PUSHSUB{
	my($cx, %args) = @_;
	$cx->cv($args{cv});
	$cx->hasargs($args{hasargs});
	$cx->olddepth($args{cv}->DEPTH);
	return;
}
sub POPSUB{
	my($cx) = @_;
	if($cx->hasargs){
		*_ = $cx->savearray;

		@{ $cx->argarray->object_2svref } = ();
	}
	return;
}
sub PUSHLOOP{
	my($cx, %args) = @_;

	$cx->label($PL_curcop->label);
	$cx->resetsp($args{sp});
	$cx->my_op($PL_op);
	$cx->next_op($PL_op->nextop);

	if($args{data}){
		$cx->ITERDATA_SET($args{data});
	}

	return;
}
sub POPLOOP{
	my($cx) = @_;

	if($cx->ITERVAR){
		not_implemented('foreach');
	}
	return;
}

sub dounwind{
	my($cxix) = @_;

	while($#PL_cxstack > $cxix){
		my $cx   = $PL_cxstack[-1];

		if($cx->type eq 'SUBST'){
			POPSUBST($cx);
		}
		elsif($cx->type eq 'SUB'){
			POPSUB($cx);
		}
		elsif($cx->type eq 'EVAL'){
			POPEVAL($cx);
		}
		elsif($cx->type eq 'LOOP'){
			POPLOOP($cx);
		}
		$#PL_cxstack--;
	}
	return;
}

sub ENTER{
	push @PL_scopestack, $#PL_savestack;
	return;
}

sub LEAVE{
	my $oldsave = pop @PL_scopestack;
	LEAVE_SCOPE($oldsave);
	return;
}
sub LEAVE_SCOPE{
	my($oldsave) = @_;

	while( $oldsave < $#PL_savestack ){
		my $ss = pop @PL_savestack;

		$ss->leave();
	}
	return;
}

sub SAVETMPS{
	push @PL_savestack, Acme::Perl::VM::Scope::Value->new(
		value     =>  $PL_tmps_floor,
		value_ref => \$PL_tmps_floor,
	);
	$PL_tmps_floor = $#PL_tmps;
	return;
}
sub FREETMPS{
	$#PL_tmps = $PL_tmps_floor;
	return;
}

sub SAVE{
	push @PL_savestack, Acme::Perl::VM::Scope::Value->new(
		value     =>  $_[0],
		value_ref => \$_[0],
	);
	return;
}
sub SAVECOMPPAD{
	push @PL_savestack, Acme::Perl::VM::Scope::Comppad->new(
		comppad => $PL_comppad,
	);
	return;
}
sub SAVECLEARSV{
	my($sv) = @_;
	push @PL_savestack, Acme::Perl::VM::Scope::Clearsv->new(
		sv => $sv,
	);
	return;
}

sub PAD_SET_CUR_NOSAVE{
	my($padlist, $nth) = @_;

	$PL_comppad = $padlist->ARRAYelt($nth);
	@PL_curpad  = ($PL_comppad->ARRAY);

	return;
}
sub PAD_SET_CUR{
	my($padlist, $nth) = @_;

	SAVECOMPPAD();
	PAD_SET_CUR_NOSAVE($padlist, $nth);

	return;
}

sub PAD_SV{
	my($targ) = @_;

	return $PL_curpad[$targ];
}

sub dopoptosub{
	my($startingblock) = @_;

	for(my $i = $startingblock; $i >= 0; $i--){
		my $type = $PL_cxstack[$i]->type;

		if($type eq 'EVAL' or $type eq 'SUB'){
			return $i;
		}
	}
	return -1;
}

sub OP_GIMME{ # op.h
	my($op, $default) = @_;
	my $op_gimme = $op->flags & OPf_WANT;

	return $op_gimme == OPf_WANT_VOID   ? G_VOID
		:  $op_gimme == OPf_WANT_SCALAR ? G_SCALAR
		:  $op_gimme == OPf_WANT_LIST   ? G_ARRAY
		:                                 $default;
}
sub OP_GIMME_REVERSE{ # op.h
	my($flags) = @_;

	return $flags & G_VOID  ? OPf_WANT_VOID
		:  $flags & G_ARRAY ? OPf_WANT_LIST
		:                     OPf_WANT_SCALAR;
}

sub gimme2want{
	my($gimme) = @_;

	return $gimme == G_VOID   ? undef
		:  $gimme == G_SCALAR ? 0
		:                       1;
}
sub want2gimme{
	my($wantarray) = @_;

	return !defined($wantarray) ? G_VOID
		:          !$wantarray  ? G_SCALAR
		:                         G_ARRAY;
}
sub block_gimme{
	my $cxix = dopoptosub($#PL_cxstack);

	if($cxix < 0){
		return G_VOID;
	}

	return $PL_cxstack[$cxix]->gimme;
}

sub GIMME_V(){ # op.h
	return OP_GIMME($PL_op, block_gimme());
}

sub LVRET(){ # cf. is_lvalue_sub() in pp_ctl.h
	if($PL_op->flags & OPpMAYBE_LVSUB){
		my $cxix = dopoptosub($#PL_cxstack);

		if($PL_cxstack[$cxix]->lval && $PL_cxstack[$cxix]->cv->CvFLAGS & CVf_LVALUE){
			not_implemented 'lvalue';
			return TRUE;
		}
	}
	return FALSE;
}

sub GVOP_gv{
	my($op) = @_;

	return USE_ITHREADS ? PAD_SV($op->padix) : $op->gv;
}

sub sv_newmortal{
	my $sv;

	push @PL_tmps, \$sv;
	return B::svref_2object(\$sv);
}

sub sv_mortalcopy{
	my($sv) = @_;

	if(!defined $sv){
		Carp::confess('sv_mortalcopy(NULL)');
	}

	my $newsv =${$sv->object_2svref};
	push @PL_tmps, \$newsv;
	return B::svref_2object(\$newsv);
}

sub SvTRUE{
	my($sv) = @_;

	return ${ $sv->object_2svref } ? TRUE : FALSE;
}
sub SvPV{
	my($sv) = @_;
	my $ref = $sv->object_2svref;

	if(!defined ${$ref}){
		apvm_warn 'Use of uninitialized value';

		return q{};
	}

	return "${$ref}";
}
sub SvNV{
	my($sv) = @_;

	my $ref = $sv->object_2svref;

	if(!defined ${$ref}){
		apvm_warn 'Use of uninitialized value';
		return 0;
	}

	return ${$ref} + 0;
}

sub defoutgv{
	no strict 'refs';
	return \*{ select() };
}

# Utilities

sub sv_defined{
	my($sv) = @_;

	return $sv && ${$sv} && defined(${ $sv->object_2svref });
}

sub is_not_null{
	my($sv) = @_;
	return ${$sv} != 0;
}
sub is_null{
	my($sv) = @_;
	return ${$sv} == 0;
}

sub mark_list{
	my($mark) = @_;
	return splice @PL_stack, $mark+1;
}

sub _ddx{
	require Data::Dumper;
	my $ddx = Data::Dumper->new(@_);
	$ddx->Indent(1);
	$ddx->Terse(1);
	$ddx->Quotekeys(0);
	return $ddx if defined wantarray;

	my $name = ( split '::', (caller 2)[3] )[-1];
	print STDERR $name, ': ', $ddx->Dump();
	return;
}
sub dump_object{
	_ddx([[ map{ $_ ? $_->object_2svref : $_ } @_ ]]);
}

sub dump_value{
	_ddx([\@_]);
}
sub dump_stacks{
	my $stacks = {
		stack     => \@PL_stack,
		markstack => \@PL_markstack,
		cxstack   => \@PL_cxstack,
		scopstack => \@PL_scopestack,
		savestack => \@PL_savestack,
		tmps      => \@PL_tmps,
	};

	_ddx([$stacks]);
}

sub not_implemented{
	my($name) = @_;

	Carp::confess $name, ' is not implemented';
}


sub call_sv{ # perl.h
	my($sv, $flags) = @_;

	if(APVM_TRACE){
		deb "%s" . "ENTERSUB (call_sv)\n", (q{.} x @PL_cxstack);
	}

	if($flags & G_DISCARD){
		ENTER;
		SAVETMPS;
	}

	my $cv = $sv->toCV();

	$PL_curcop ||= bless \do{ my $addr = 0 }, 'B::COP'; # dummy cop

	my $oldop = $PL_op;
	$PL_op = Acme::Perl::VM::OP_CallSV->new(
		cv    => $cv,
		next  => NULL,
		flags => OP_GIMME_REVERSE($flags || 0x00),
	);
	PUSH($cv);

	my $oldmark  = TOPMARK;

	$PL_op = Acme::Perl::VM::PP::pp_entersub();
	$PL_runops->();

	my $retval = $#PL_stack - $oldmark;

	if($flags & G_DISCARD){
		$#PL_stack = $oldmark;
		$retval = 0;
		FREETMPS;
		LEAVE;
	}

	$PL_op = $oldop;

	return $retval;
}

sub run_block(&@){
	my($code, @args) = @_;

	if(APVM_DUMMY){
		return $code->(@args);
	}

	ENTER;
	SAVETMPS;

	PUSHMARK;
	PUSH($_) for @args;

	my $mark   = $#PL_stack - call_sv(B::svref_2object($code), want2gimme(wantarray));
	my @retval = map{ ${ $_->object_2svref } } mark_list($mark);

	FREETMPS;
	LEAVE;

	if(wantarray){ # list context
		return @retval;
	}
	elsif(defined wantarray){ # scalar context
		return $retval[-1];
	}
	else{ # void context
		return;
	}
}

package
	Acme::Perl::VM::OP_CallSV;
	
use Mouse;

has cv => (
	is  => 'ro',
	isa => 'B::CV',

	required => 1,
);

has next => (
	is  => 'ro',
	isa => 'B::OBJECT',

	required => 1,
);

has flags => (
	is  => 'ro',
	isa => 'Int',

	required => 1,
);

__PACKAGE__->meta->make_immutable();

sub name{
	return 'entersub';
}

1;
__END__

=head1 NAME

Acme::Perl::VM - An implementation of Perl5 Virtual Machine in Pure Perl (APVM)

=head1 VERSION

This document describes Acme::Perl::VM version 0.01.

=head1 SYNOPSIS

	use Acme::Perl::VM;

	run_block{
		print "Hello, APVM world!\n",
	};

=head1 DESCRIPTION

C<Acme::Perl::VM> is a Perl5 Virtual Machine implemented in Pure Perl.

=head1 DEPENDENCIES

Perl 5.8.1 or later.

=head1 BUGS

No bugs have been reported.

Please report any bugs or feature requests to the author.

=head1 AUTHOR

Goro Fuji (gfx) E<lt>gfuji(at)cpan.orgE<gt>.

=head1 SEE ALSO

F<pp.h> for PUSH/POP macros.

F<pp.c>, F<pp_ctl.c>, and F<pp_hot.c> for ppcodes.

C<op.h> for opcodes.

F<cop.h> for COP and context blocks.

F<scope.h> and F<scope.c> for scope stacks.

F<pad.h> and F<pad.c> for pad variables.

F<run.c> for runops.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2009, Goro Fuji (gfx). Some rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
