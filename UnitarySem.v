Require Export SQIMP.
Require Export Quantum.

Open Scope ucom_scope.

(** Denotation of Unitaries *)

Definition pad {n} (start dim : nat) (A : Square (2^n)) : Square (2^dim) :=
  if start + n <=? dim then I (2^start) ⊗ A ⊗ I (2^(dim - n - start)) else I (2^dim).

Lemma WF_pad : forall n start dim (A : Square (2^n)),
  WF_Matrix _ _ A ->
  WF_Matrix _ _ (pad start dim A).
Proof.
  intros n start dim A. unfold pad.
  bdestruct (start + n <=? dim); auto with wf_db.
Qed.  

(* k must be 1, but dependent types... *)
Definition ueval1 {k} (dim n : nat) (u : Unitary k) : Square (2^dim) :=
  @pad 1 n dim
  match u with  
  | U_H         => hadamard 
  | U_X         => σx
  | U_Y         => σy
  | U_Z         => σz
  | U_R ϕ       => phase_shift ϕ
  | _           => I (2^1)
  end.

(* Restriction: m <> n and m, n < dim *)
Definition ueval_cnot (dim m n: nat) : Square (2^dim) :=
  if (m <? n) then
    @pad (1+(n-m-1)+1) m dim (∣1⟩⟨1∣ ⊗ I (2^(n-m-1)) ⊗ σx .+ ∣0⟩⟨0∣ ⊗ I (2^(n-m)))
  else if (n <? m) then
    @pad (1+(m-n-1)+1) n dim (σx ⊗ I (2^(m-n-1)) ⊗ ∣1⟩⟨1∣ .+ I (2^(m-n)) ⊗ ∣0⟩⟨0∣)
  else
    I (2^dim).

Definition ueval {n} (dim : nat) (u : Unitary n) (l : list nat) : Square (2^dim) :=
  match n, l with
  | 1, [i]   => ueval1 dim i u
  | 2, i::[j] => ueval_cnot dim i j
  | _, _     => I _
  end.

(** Denotation of ucoms **)

Fixpoint uc_eval (dim : nat) (c : ucom) : Matrix (2^dim) (2^dim) :=
  match c with
  | uskip    => I (2^dim)
  | uapp u l => ueval dim u l
  | c1 ; c2  => uc_eval dim c2 × uc_eval dim c1 
  end.

(** Well-formedness **)

Lemma WF_ueval1 : forall dim n (u : Unitary 1), WF_Matrix _ _ (ueval1 dim n u).
Proof.
  intros dim n u.
  apply WF_pad.
  destruct u; auto with wf_db.
Qed.  
  
Lemma WF_ueval_cnot : forall dim m n, WF_Matrix _ _ (ueval_cnot dim m n). 
Proof.
  intros dim m n.
  unfold ueval_cnot.
  bdestruct (m <? n); [|bdestruct (n <? m)];
    try apply WF_pad; unify_pows_two; auto 10 with wf_db.    
Qed.  

Lemma WF_ueval : forall n dim (u : Unitary n) l, WF_Matrix _ _ (ueval dim u l).
Proof.
  intros n dim u l.
  destruct n as [|[|[|n']]]; simpl; auto with wf_db.
  - destruct l as [|i [| j l]]; simpl; auto with wf_db.
    apply WF_ueval1.
  - destruct l as [|i [| j [| k l]]]; simpl; auto with wf_db.
    apply WF_ueval_cnot.
Qed.  

Lemma WF_uc_eval : forall dim c, WF_Matrix _ _ (uc_eval dim c).
Proof.
  intros dim c.
  induction c; simpl; auto with wf_db.
  apply WF_ueval.
Qed.

Hint Resolve WF_ueval WF_uc_eval : wf_db.


(* Some unit tests *)

Lemma eval_H : uc_eval 1 (H 0) = hadamard.
Proof.
  simpl. unfold ueval1, pad. (* have these automatically simplify *)
  simpl. Msimpl. reflexivity.
Qed.

Lemma eval_HHpar : uc_eval 2 (H 0; H 1) = hadamard ⊗ hadamard.
Proof.
  simpl. unfold ueval1, pad. (* have these automatically simplify *)
  simpl. Msimpl. reflexivity.
Qed.

Lemma eval_HHseq : uc_eval 2 (H 0; H 0) = I 4.
Proof.
  simpl. unfold ueval1, pad. (* have these automatically simplify *)
  simpl. Msimpl. solve_matrix.
Qed.

Lemma eval_CNOT : uc_eval 2 (CNOT 0 1) = cnot.
Proof.
  unfold uc_eval. simpl.
  simpl. unfold ueval_cnot, pad. (* have these automatically simplify *)
  simpl. Msimpl. solve_matrix.
Qed.


(** Equivalence and Structural Rules **)

(* Precondition about typing? *)
Definition uc_equiv (c1 c2 : ucom) := forall dim, uc_eval dim c1 = uc_eval dim c2.

Infix "≡" := uc_equiv : ucom_scope.

Lemma useq_assoc : forall c1 c2 c3, ((c1 ; c2) ; c3) ≡ (c1 ; (c2 ; c3)).
Proof.
  intros c1 c2 c3 dim. simpl.
  rewrite Mmult_assoc. easy.
Qed.

Lemma useq_congruence : forall c1 c1' c2 c2',
    c1 ≡ c1' ->
    c2 ≡ c2' ->
    c1 ; c2 ≡ c1' ; c2'.
Proof.
  intros c1 c1' c2 c2' Ec1 Ec2 dim.
  simpl.
  rewrite Ec1, Ec2.
  reflexivity.
Qed.

(* Optimization: Remove skips *)

Lemma uskip_id_l : forall (c : ucom),
   (uskip ; c) ≡ c.
Proof.
  intros c dim.
  simpl; Msimpl; reflexivity.
Qed.

Lemma uskip_id_r : forall (c : ucom),
   (c ; uskip) ≡ c.
Proof.
  intros c dim.
  simpl; Msimpl; reflexivity.
Qed.

Fixpoint rm_uskips (c : ucom) : ucom :=
  match c with
  | c1 ; c2 => match rm_uskips c1, rm_uskips c2 with
              | uskip, c2' => c2'
              | c1', uskip => c1'
              | c1', c2'   => c1'; c2'
              end
  | c'      => c'
  end.

(* We don't really need this anymore *)
Hint Constructors uc_well_typed : type_db.

Lemma WT_rm_uskips : forall c dim, uc_well_typed dim c <-> uc_well_typed dim (rm_uskips c).
Proof.
  intros c dim.
  split; intros H.
  - induction H.
    + constructor.
    + simpl.
      destruct (rm_uskips c1), (rm_uskips c2); auto with type_db.
    + simpl. auto with type_db.
  - induction c.
    + constructor.
    + destruct (rm_uskips (c1; c2)) eqn:E.
      * simpl in E.
        destruct (rm_uskips c1), (rm_uskips c2); auto with type_db; discriminate.
      * simpl in E.
        destruct (rm_uskips c1) eqn:E1, (rm_uskips c2) eqn:E2; auto with type_db;
        rewrite <- E in H; inversion H; auto with type_db.
      * simpl in E.
        destruct (rm_uskips c1) eqn:E1, (rm_uskips c2) eqn:E2; auto with type_db;
        rewrite <- E in H; inversion H; auto with type_db.
    + simpl in H; easy.
Qed.
      

Lemma rm_uskips_sound : forall c,
  c ≡ (rm_uskips c).
Proof.
  induction c; intros dim; trivial.
  simpl.
  destruct (rm_uskips c1) eqn:E1, (rm_uskips c2) eqn:E2; trivial;
    rewrite IHc1, IHc2; simpl; Msimpl; easy.
Qed.

Inductive skip_free : ucom -> Prop :=
  | SF_seq : forall c1 c2, skip_free c1 -> skip_free c2 -> skip_free (c1; c2)
  | SF_app : forall n l (u : Unitary n), skip_free (uapp u l).

Lemma rm_uskips_correct : forall c,
  (rm_uskips c) = uskip \/ skip_free (rm_uskips c).
Proof.
  intro c.
  induction c.
  - left; easy.
  - destruct IHc1; destruct IHc2.
    + left. simpl. rewrite H. rewrite H0. reflexivity.
    + right. simpl. rewrite H. assumption.
    + right. simpl. rewrite H0. 
      destruct (rm_uskips c1); try easy.
    + right. simpl. 
      destruct (rm_uskips c1); try assumption;
      destruct (rm_uskips c2); try (apply SF_seq); easy. 
  - right; simpl. apply SF_app.
Qed.

Close Scope C_scope.
Close Scope R_scope.

Fixpoint count_ops (c : ucom) : nat :=
  match c with
  | c1; c2 => (count_ops c1) + (count_ops c2)
  | _ => 1
  end.

Lemma rm_uskips_reduces_count : forall c,
  count_ops (rm_uskips c) <= count_ops c.
Proof.
  intro c.
  induction c.
  - simpl. omega.
  - simpl. destruct (rm_uskips c1); try omega; 
    destruct (rm_uskips c2); 
    simpl; simpl in IHc1; simpl in IHc2;
    omega.
  - simpl. omega.
Qed.

Lemma pad_dims : forall c n k,
  uc_well_typed n c ->
  (uc_eval n c) ⊗ I (2^k) = uc_eval (n + k) c.  
Proof.
  intros c n k H.
  induction c.
  - simpl. rewrite id_kron. unify_pows_two. reflexivity.
  - inversion H; subst.
    simpl. rewrite <- IHc1, <- IHc2; trivial.
    Msimpl'; reflexivity.
  - simpl.
    unfold ueval.
    destruct n0 as [|[|[|]]]; simpl; try (rewrite id_kron; unify_pows_two; reflexivity).
    + destruct l as [| a []]; try (rewrite id_kron; unify_pows_two; reflexivity).
      unfold ueval1.
      repeat match goal with
      | [|- context [pad _ _ ?U ]] => remember U as U'
      end.
      unfold pad.
      assert(L : a + 1 <= n).
      { inversion H; subst.
        unfold SQIMP.bounded in H5; simpl in H5.
        rewrite andb_true_r in H5.
        apply Nat.ltb_lt in H5.
        omega. }
      bdestruct (a + 1 <=? n); bdestructΩ (a + 1 <=? n+k).
      setoid_rewrite (kron_assoc _ _ _ _ _ _ (I (2^a) ⊗ U')).
      rewrite id_kron. unify_pows_two.
      replace (n - 1 - a + k) with (n + k - 1 - a) by omega.
      reflexivity.
    + destruct l as [| a [|b[|]]]; try (rewrite id_kron; unify_pows_two; reflexivity).
      unfold ueval_cnot.
      inversion H; subst.
      inversion H5; subst.
      apply andb_true_iff in H2 as [La Lb].
      clear -La Lb.
      rewrite andb_true_r in Lb.
      apply Nat.ltb_lt in La.
      apply Nat.ltb_lt in Lb.
      unfold pad.
      bdestruct (a <? b); bdestructΩ (b <? a); try (rewrite id_kron; unify_pows_two; reflexivity).
      * bdestructΩ (a + S (b - a - 1 + 1) <=? n).
        bdestructΩ (a + S (b - a - 1 + 1) <=? n + k).
        setoid_rewrite (kron_assoc _ _ _ _ _ _ _ _  (I (2^k))).
        rewrite id_kron.
        unify_pows_two.
        rewrite Nat.sub_add by omega.
        rewrite Nat.add_sub_swap by omega.
        rewrite Nat.add_sub_swap by omega.
        reflexivity.
      * bdestructΩ (b + S (a - b - 1 + 1) <=? n).
        bdestructΩ (b + S (a - b - 1 + 1) <=? n + k).
        setoid_rewrite (kron_assoc _ _ _ _ _ _ _ _  (I (2^k))).
        rewrite id_kron.
        unify_pows_two.
        rewrite Nat.sub_add by omega.
        rewrite Nat.add_sub_swap by omega.
        rewrite Nat.add_sub_swap by omega.
        reflexivity.
Qed.
  
Open Scope ucom.

Lemma slide1 : forall (m n : nat) (U V : Unitary 1),
  m <> n ->
  (m *= U ; n *= V) ≡ (n *= V ; m *= U). 
Proof.
  intros m n U V NE dim.
  simpl.
  simpl in *.
  unfold ueval1. 
  repeat match goal with
  | [|- context [pad m _ ?U ]] => remember U as U'
  | [|- context [pad n _ ?V ]] => remember V as V'
  end.
  assert (WFU : WF_Matrix _ _ U') by 
      (destruct U; subst; auto with wf_db).
  assert (WFV : WF_Matrix _ _ V') by 
      (destruct V; subst; auto with wf_db).
  clear HeqU' HeqV' U V.
  unfold pad.
  bdestruct (n + 1 <=? dim); bdestruct (m + 1 <=? dim);
    try Msimpl; trivial.
  bdestruct (m <? n).
  - remember (n - m - 1) as k.
    replace n with (m + 1 + k) by omega.
    replace (2 ^ (m+1+k)) with (2^m * 2 * 2^k) by unify_pows_two.
    remember (dim - 1 - (m + 1 + k)) as j.
    replace (dim - 1 - m) with (k + 1 + j) by omega.
    replace (2 ^ (k + 1 + j)) with (2^k * 2 * 2^ j) by unify_pows_two.
    repeat rewrite <- id_kron.
    simpl in *.
    repeat rewrite kron_assoc.
    repeat rewrite Nat.mul_assoc.
    Msimpl'.
    reflexivity.
  - rename m into n, n into m.
    remember (n - m - 1) as k.
    replace n with (m + 1 + k) by omega.
    replace (2 ^ (m+1+k)) with (2^m * 2 * 2^k) by unify_pows_two.
    remember (dim - 1 - (m + 1 + k)) as j.
    replace (dim - 1 - m) with (k + 1 + j) by omega.
    replace (2 ^ (k + 1 + j)) with (2^k * 2 * 2^ j) by unify_pows_two.
    repeat rewrite <- id_kron.
    simpl in *.
    repeat rewrite kron_assoc.
    repeat rewrite Nat.mul_assoc.
    Msimpl'.
    reflexivity.
Qed.

(** Flattening sequences **)
Fixpoint flat_append (c1 c2 : ucom) : ucom := 
  match c1 with
  | c1'; c2' => c1' ; (flat_append c2' c2)
  | _ => c1 ; c2
  end.

Fixpoint flatten (c: ucom) : ucom :=
  match c with
  | c1; c2 => flat_append (flatten c1) (flatten c2)
  | _ => c
  end.

Lemma denote_flat_append : forall c1 c2 dim,
  uc_eval dim (flat_append c1 c2) = uc_eval dim c2 × uc_eval dim c1.
Proof.
  intros c1 c2 dim.
  induction c1; try easy.
  simpl.
  rewrite IHc1_2.
  apply Mmult_assoc.
Qed.

Lemma flatten_sound : forall c,  
  c ≡ flatten c.
Proof.
  intros c dim.
  induction c; try easy.
  simpl.
  rewrite IHc1, IHc2.
  rewrite denote_flat_append.
  reflexivity.
Qed.

Definition q1 : nat := 0.
Definition q2 : nat := 1.
Definition q3 : nat := 2.
Definition example1 : ucom := ((X q1; H q2); ((X q1; X q2); (CNOT q3 q2; X q2))).
Compute (flatten example1).
