package Acme::Perl::VM::PP;
use strict;

use Acme::Perl::VM qw(:perl_h);
use Acme::Perl::VM::B;

#NOTE:
#          XS  APVM
#
#         dSP  (nothing)
#          SP  $#PL_stack
#         *SP  $PL_stack[-1]
#       dMARK  my $mark = POPMARK
#        MARK  $mark
#       *MARK  $PL_stack[$mark]
#   dORIGMARK  my $origmark = $mark
#    ORIGMARK  $origmark
#     SPAGAIN  (nothing)
#     PUTBACK  (nothing)

sub pp_nextstate{
	$PL_curcop = $PL_op;

	$#PL_stack = $PL_cxstack[-1]->oldsp;
	FREETMPS;

	return $PL_op->next;
}

sub pp_pushmark{
	PUSHMARK;

	return $PL_op->next;
}

sub pp_const{
	my $sv = is_not_null($PL_op->sv) ? $PL_op->sv : PAD_SV($PL_op->targ);

	PUSH($sv);

	return $PL_op->next;
}

sub pp_gv{
	PUSH( GVOP_gv($PL_op) );
	return $PL_op->next;
}

sub pp_rv2av{
	my $sv = TOP;

	if($sv->ROK){
		not_implemented 'pp_rv2av for RV';
	}

	if($sv->isa('B::AV')){
		if($PL_op->flags & OPf_REF){
			SET($sv);
			return $PL_op->next;
		}
		elsif(LVRET){
			not_implemented 'lvalue';
		}
	}
	else{
		$sv->isa('B::GV') or apvm_die 'Not a GLOB';
		$sv = $sv->AV;

		if($PL_op->flags & OPf_REF){
			SET($sv);
			return $PL_op->next;
		}
		elsif(LVRET){
			not_implemented 'lvalue';
		}
	}

	my $gimme = GIMME_V;
	if($gimme == G_ARRAY){
		POP;

		foreach my $elem( @{$sv->object_2svref} ){
			PUSH($elem);
		}
	}
	elsif($gimme == G_SCALAR){
		SETval( $sv->FILL + 1 );
	}

	return $PL_op->next;
}

sub pp_padsv{
	my $targ = GET_TARGET;
	PUSH($targ);

	if($PL_op->flags & OPf_MOD){
		if($PL_op->private & OPpLVAL_INTRO){
			if(!($PL_op->private & OPpPAD_STATE)){
				SAVECLEARSV($targ);
			}
		}
	}
	return $PL_op->next;
}


sub pp_list{
	my $mark = POPMARK;

	if(GIMME_V != G_ARRAY){
		if(++$mark <= $#PL_stack){
			$PL_stack[$mark] = $PL_stack[-1];
		}
		else{
			$PL_stack[$mark] = sv_undef;
		}
		$#PL_stack = $mark;
	}
	return $PL_op->next;
}


sub _method_common{
	my($meth) = @_;

	my $name = SvPV($meth);
	my $sv   = $PL_stack[ TOPMARK() + 1];

	if(!sv_defined($sv)){
		apvm_die q{Can't call method "%s" on an undefined value}, $name;
	}

	my $invocant = ${$sv->object_2svref};

	my $code = $invocant->can($name);

	if(!$code){
		apvm_die q{Can't locate object method "%s" via package "%s"}, $name, ref($invocant) || $invocant;
	}

	return svref_2object($code);
}

sub pp_method{
	my $sv = TOP;

	if($sv->ROK){
		if($sv->RV->isa('B::CV')){
			SET($sv->RV);
			return $PL_op->next;
		}
	}

	SET(_method_common($sv));
	return $PL_op->next;
}
sub pp_method_named{
	my $sv = is_not_null($PL_op->sv) ? $PL_op->sv : PAD_SV($PL_op->targ);

	PUSH(_method_common($sv));
	return $PL_op->next;
}

sub pp_entersub{
	my $sv = POP;
	my $cv = $sv->toCV();

	my $hasargs = ($PL_op->flags & OPf_STACKED) != 0;

	ENTER;
	SAVETMPS;

	my $mark  = POPMARK;
	my $gimme = GIMME_V;

	PUSHBLOCK(SUB => $mark, $gimme);
	my $cx = $PL_cxstack[-1];

	PUSHSUB($cx,
		cv      => $cv,
		hasargs => $hasargs,
	);
	$cx->retop($PL_op->next);

	#XXX: How to do {$cv->DEPTH++}?
	PAD_SET_CUR($cv->PADLIST, $cv->DEPTH+1);

	if($hasargs){
		my $av = PAD_SV(0);

		$cx->savearray(\@_);
		*_ = $av->object_2svref;
		$cx->CURPAD_SAVE();
		$cx->argarray($av);
		@_ = mark_list($mark);
	}

	return $cv->START;
}

sub pp_leavesub{
	my $cx    = POPBLOCK;
	my $newsp = $cx->oldsp;
	my $gimme = $cx->gimme;

	if($gimme == G_SCALAR){
		my $mark = $newsp + 1;

		if($mark <= $#PL_stack){
			$PL_stack[$mark] = sv_mortalcopy(TOP);
		}
		else{
			$PL_stack[$mark] = sv_undef;
		}
		$#PL_stack = $mark;
	}
	elsif($gimme == G_ARRAY){
		for(my $mark = $newsp + 1; $mark <= $#PL_stack; $mark++){
			$PL_stack[$mark] = sv_mortalcopy($PL_stack[$mark]);
		}
	}

	LEAVE;

	POPSUB($cx);
	# XXX: How to do {$cv->DEPTH = $cx->olddepth}?

	return $cx->retop;
}
sub pp_return{
	my $mark = POPMARK;

	my $cxix = dopoptosub($#PL_cxstack);
	if($cxix < 0){
		apvm_die q{Can't return outside a subroutine};
	}

	if($cxix < $#PL_cxstack){
		dounwind($cxix);
	}

	my $cx = POPBLOCK;
	my $popsub2;
	my $retop;

	if($cx->type eq 'SUB'){
		$popsub2 = TRUE;
		$retop   = $cx->retop;
	}
	else{
		not_implemented 'pp_return for ' . $cx->type
	}

	my $newsp = $cx->oldsp;
	my $gimme = $cx->gimme;
	if($gimme == G_SCALAR){
		if($mark < $#PL_stack){
			$PL_stack[++$newsp] = sv_mortalcopy(TOP);
		}
		else{
			$PL_stack[++$newsp] = sv_undef;
		}
	}
	elsif($gimme == G_ARRAY){
		while(++$mark <= $#PL_stack){
			$PL_stack[++$newsp] = sv_mortalcopy($PL_stack[$mark]);
		}
	}
	$#PL_stack = $newsp;

	LEAVE;

	if($popsub2){
		POPSUB($cx);
	}
	return $retop;
}

sub pp_enter{

	my $gimme = OP_GIMME($PL_op, -1);

	if($gimme == -1){
		if(@PL_cxstack){
			$gimme = $PL_cxstack[-1]->gimme;
		}
		else{
			$gimme = G_SCALAR;
		}
	}

	ENTER;
	SAVETMPS;

	PUSHBLOCK(BLOCK => $#PL_stack, $gimme);

	return $PL_op->next;
}
sub pp_leave{

	my $cx    = POPBLOCK;
	my $newsp = $cx->oldsp;
	my $gimme = OP_GIMME($PL_op, -1);
	if($gimme == -1){
		if(@PL_cxstack){
			$gimme = $PL_cxstack[-1]->gimme;
		}
		else{
			$gimme = G_SCALAR;
		}
	}

	if($gimme == G_VOID){
		$#PL_stack = $newsp;
	}
	elsif($gimme == G_SCALAR){
		my $mark = $newsp + 1;
		if($mark <= $#PL_stack){
			$PL_stack[$mark] = sv_mortalcopy(TOP);
		}
		else{
			$PL_stack[$mark] = sv_undef;
		}
		$#PL_stack = $mark;
	}
	else{ # G_ARRAY
		for(my $mark = $newsp + 1; $mark <= $#PL_stack; $mark++){
			$PL_stack[$mark] = sv_mortalcopy($PL_stack[$mark]);
		}
	}

	LEAVE;

	return $PL_op->next;
}

sub pp_enterloop{

	ENTER;
	SAVETMPS;
	ENTER;

	PUSHBLOCK(LOOP => $#PL_stack, GIMME_V);
	PUSHLOOP($PL_cxstack[-1],
		sp => $#PL_stack,
	);

	return $PL_op->next;
}

sub pp_leaveloop{
	my $cx = POPBLOCK;

	my $mark  = $cx->oldsp;
	my $gimme = $cx->gimme;
	my $newsp = $cx->resetsp;

	if($gimme == G_SCALAR){
		if($mark < $#PL_stack){
			$PL_stack[++$newsp] = sv_mortalcopy($PL_stack[-1]);
		}
		else{
			$PL_stack[++$newsp] = sv_undef;
		}
	}
	elsif($gimme == G_ARRAY){
		while($mark < $#PL_stack){
			$PL_stack[++$newsp] = sv_mortalcopy($PL_stack[++$mark]);
		}
	}

	$#PL_stack = $newsp;

	POPLOOP($cx);

	LEAVE;
	LEAVE;

	return $PL_op->next;
}

sub pp_lineseq{
	return $PL_op->next;
}
sub pp_stub{
	if(GIMME_V == G_SCALAR){
		PUSH(sv_undef);
	}
	return $PL_op->next;
}
sub pp_unstack{
	$#PL_stack = $PL_cxstack[-1]->oldsp;
	FREETMPS;
	my $oldsave = $PL_scopestack[-1];
	LEAVE_SCOPE($oldsave);
	return $PL_op->next;
}

sub pp_sassign{
	my $right = POP;
	my $left  = TOP;

	if($PL_op->private & OPpASSIGN_BACKWARDS){
		($left, $right) = ($right, $left);
	}

	$right->setsv($left);
	SET($right);
	return $PL_op->next;
}

sub pp_aassign{
	my $last_l_elem  = $#PL_stack;
	my $last_r_elem  = POPMARK();
	my $first_r_elem = POPMARK() + 1;
	my $first_l_elem = $last_r_elem + 1;

	my @lhs = @PL_stack[$first_l_elem .. $last_l_elem];
	my @rhs = @PL_stack[$first_r_elem .. $last_r_elem];

	if($PL_op->private & OPpASSIGN_COMMON){
		for(my $r_elem = $first_r_elem; $r_elem <= $last_r_elem; $r_elem++){
			$PL_stack[$r_elem] = sv_mortalcopy($PL_stack[$r_elem]);
		}
	}

	my $ary_ref;
	my $hash_ref;
	my $duplicates = 0;

	my $l_elem = $first_l_elem;
	my $r_elem = $first_r_elem;

	my $gimme = GIMME_V;

	while($l_elem <= $last_l_elem){
		my $sv = $PL_stack[$l_elem++];

		if($sv->isa('B::AV')){
			$ary_ref = $sv->object_2svref;
			@{ $ary_ref } = ();
			while($r_elem <= $last_r_elem){
				push @{$ary_ref}, ${ $PL_stack[$r_elem]->object_2svref };
				$PL_stack[$r_elem++] = svref_2object(\$ary_ref->[-1]);
			}
		}
		elsif($sv->isa('B::HV')){
			not_implemented 'pp_aassign for HV';
		}
		else{
			if($$sv == ${sv_undef()}){ # (undef) = (...)
				if($r_elem <= $last_r_elem){
					$r_elem++;
				}
			}
			elsif($r_elem <= $last_r_elem){
				$sv->setsv($PL_stack[$r_elem]);
				$PL_stack[$r_elem++] = $sv;
			}
		}
	}

	if($gimme == G_VOID){
		$#PL_stack = $first_r_elem - 1;
	}
	elsif($gimme == G_SCALAR){
		$#PL_stack = $first_r_elem;
		SETval($last_r_elem - $first_r_elem + 1);
	}
	else{
		$l_elem = $first_l_elem + ($r_elem + $first_r_elem);
		while($r_elem <= $#PL_stack){
			$PL_stack[$r_elem++] = ($l_elem <= $last_l_elem) ? $PL_stack[$l_elem++] : sv_undef;
		}

		if($ary_ref){
			$#PL_stack = $last_r_elem;
		}
		elsif($hash_ref){
			not_implemented 'pp_aassign for HV';
		}
		else{
			$#PL_stack = $first_r_elem + ($last_l_elem - $first_l_elem);
		}
	}

	return $PL_op->next;
}
sub pp_cond_expr{
	if(SvTRUE(POP)){
		return $PL_op->other;
	}
	else{
		return $PL_op->next;
	}
}

sub pp_and{
	if(SvTRUE(TOP)){
		pop @PL_stack;
		return $PL_op->other;
	}
	else{
		return $PL_op->next;
	}
}

sub pp_range{
	if(GIMME_V == G_ARRAY){
		return $PL_op->next;
	}

	if(SvTRUE(GET_TARGET)){
		return $PL_op->other;
	}
	else{
		return $PL_op->next;
	}
}

sub pp_preinc{
	${ TOP()->object_2svref }++;

	return $PL_op->next;
}

sub pp_lt{
	my $right = POP;
	my $left  = TOP;

	SET(SvNV($left) < SvNV($right) ? sv_yes : sv_no);
	return $PL_op->next;
}

sub pp_add{
	my $targ  = GET_ATARGET;
	my $right = POP;
	my $left  = TOP;

	SET( $targ->setval(SvNV($left) + SvNV($right)) );
	return $PL_op->next;
}

sub pp_concat{
	my $targ = GET_ATARGET;
	my $right= POP;
	my $left = TOP;

	SET( $targ->setval(SvPV($left) . SvPV($right)) );
	return $PL_op->next;
}

sub pp_print{
	my $mark     = POPMARK;
	my $origmark = $mark;
	my $gv   = ($PL_op->flags & OPf_STACKED) ? $PL_stack[++$mark]->object_2svref : defoutgv;

	my $ret  = print {$gv} map{ SvPV($_) } mark_list($mark);

	$#PL_stack = $origmark;
	PUSH( $ret ? sv_yes : sv_no );
	return $PL_op->next;
}

sub pp_aelemfast{
	my $av   = $PL_op->flags & OPf_SPECIAL ? PAD_SV($PL_op->targ) : GVOP_gv($PL_op)->AV;
	my $lval = $PL_op->flags & OPf_MOD;

	my $sv   = $av->fetch($PL_op->private, $lval);
	PUSH( is_not_null($sv) ? $sv : sv_undef );

	return $PL_op->next;
}

sub pp_aelem{
	my $elemsv = POP;
	my $av     = POP;
	my $lval  = $PL_op->flags & OPf_MOD;

	my $sv = $av->fetch(SvNV($elemsv), $lval);
	PUSH( is_not_null($sv) ? $sv : sv_undef );
	return $PL_op->next;
}

sub pp_helem{
	my $keysv = POP;
	my $hv    = TOP;
	my $lval  = $PL_op->flags & OPf_MOD;

	my $sv = $hv->fetch(SvPV($keysv), $lval);
	PUSH( is_not_null($sv) ? $sv : sv_undef );

	return $PL_op->next;
}

sub pp_undef{
	if(!$PL_op->private){
		PUSH(sv_undef);
		return $PL_op->next;
	}

	not_implemented 'undef(expr)';
}

sub pp_scalar{
	return $PL_op->next;
}

1;
__END__

=head1 NAME

Acme::Perl::VM::PP - ppcodes for APVM

=head1 SYNOPSIS

	use Acme::Perl::VM;

=head1 PPCODE

Implemented ppcodes:

=over 4

=item pp_nextstate

=item pp_pushmark

=item pp_const

=item pp_gv

=item pp_rv2av

=item pp_padsv

=item pp_list

=item pp_method

=item pp_method_named

=item pp_entersub

=item pp_leavesub

=item pp_return

=item pp_enter

=item pp_leave

=item pp_enterloop

=item pp_leaveloop

=item pp_lineseq

=item pp_stub

=item pp_unstack

=item pp_sassign

=item pp_aassign

=item pp_cond_expr

=item pp_and

=item pp_range

=item pp_preinc

=item pp_lt

=item pp_add

=item pp_concat

=item pp_print

=item pp_aelemfast

=item pp_undef

=item pp_scalar

=back

=cut

