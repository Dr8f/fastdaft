open Lib
;;

type ctype = 
  Int
| Env of string
| Func
| Ptr of ctype
| Char
| Complex
| Void
| Bool
;;

type expr = 
| Var of ctype * string
| Nth of expr * expr
| Cast of expr * ctype
| Equal of expr * expr
| New of expr
| Mul of expr * expr
| Plus of expr * expr
| Minus of expr * expr
| UniMinus of expr
| Mod of expr * expr
| Divide of expr * expr
| FunctionCall of string (*functionname*) * expr list (*arguments*)
| MethodCall of expr (*object*) * string (*method name*) * expr list (*arguments*)
| Const of int
| AddressOf of expr
;;

type cmethod = 
  Constructor of expr list(*args*) * code 
| Method of ctype (*return type*) * string (* functionname *) * expr list(* args*)  * code
and
code =
  Class of string(*class name*) * string (*class template from which it is derived*) * expr list (*member variables*) * cmethod list (*methods*)
| Chain of code list
| Noop
| Error of string
| Assign of expr(*dest*) * expr (*origin*)
| ArrayAllocate of expr (*pointer*) * ctype (*element type*) * expr (*element count*)
| PlacementNew of expr (*address*) * expr (*content*)
| If of expr (*condition*) * code (*true branch*) * code (*false branch*)
| Loop of expr (*loop variable*) * expr (*count*) * code 
| ArrayDeallocate of expr (*pointer*) * expr (*element count*)
| Return of expr
| Declare of expr
| Ignore of expr (*expression with side effect*)
;; 

let _rs = "RS"
;;

let _func = "func"
;;

let _at = "at"
;;

let _compute = "compute"
;;

let _rule = Var(Int, "_rule")
;;

let _dat = Var(Ptr(Complex), "_dat")
;;

let build_child_var (num:int) : expr =
  Var(Ptr(Env(_rs)),"child"^(string_of_int num))
;;

let expr_of_intexpr (intexpr : Spl.intexpr) : expr =
  match intexpr with
    Spl.IConstant x -> Const x
  | x -> Var(Int, Spl.string_of_intexpr intexpr)
;;

let _output = Var(Ptr(Complex),"Y")
;;

let _input = Var(Ptr(Complex),"X")
;;

module IntSet = Set.Make( 
  struct
    let compare = Pervasives.compare
    type t = int
  end )
;;

let rec string_of_ctype (t : ctype) : string =
  match t with
  |Int -> "Int"
  |Func -> "Func"
  |Env(rs) -> "Env(\""^rs^"\")"
  |Ptr(ctype)->"Ptr("^(string_of_ctype ctype)^")"
  |Char -> "Char"
  |Complex -> "Complex"
  |Void -> "Void"
  |Bool -> "Bool"
;;

let rec string_of_expr (expr:expr) : string = 
  match expr with
  | Equal(a,b) -> "Equal(" ^ (string_of_expr a) ^ ", " ^ (string_of_expr b) ^ ")"
  | New(f) -> "New("^(string_of_expr f) ^")"
  | Nth(expr, count) ->"Nth("^(string_of_expr expr)^", "^(string_of_expr count)^")"
  | Var(a, b) -> "Var("^ (string_of_ctype a) ^ ", \"" ^ b ^ "\")"
  | Cast(expr, ctype) -> "Cast("^(string_of_expr expr)^", "^(string_of_ctype ctype)^")"
  | MethodCall(expr, methodname,args) -> "MethodCall("^(string_of_expr expr) ^ ", \""^methodname^"\", ["^(String.concat "; " (List.map string_of_expr args))^"])"
  | FunctionCall(functionname, args) -> "FunctionCall(\""^functionname^"\", ["^(String.concat "; " (List.map string_of_expr args))^"])"
  | Plus(a,b) -> "Plus("^(string_of_expr a)^", "^(string_of_expr b)^")"
  | Minus(a,b) -> "Minus("^(string_of_expr a)^", "^(string_of_expr b)^")"
  | Mul(a,b) -> "Mul("^(string_of_expr a)^", "^(string_of_expr b)^")"
  | Mod(a,b) -> "Mod("^(string_of_expr a)^", "^(string_of_expr b)^")"
  | Divide(a,b) -> "Divide("^(string_of_expr a)^", "^(string_of_expr b)^")"
  | UniMinus(a) -> "UniMinus("^(string_of_expr a)^")"
  | Const(a) -> "Const("^ (string_of_int a) ^")"
  | AddressOf(a) -> "AddressOf("^ (string_of_expr a) ^")"
;;


let rec expr_of_idxfunc (idxfunc : Spl.idxfunc) : expr =
  match idxfunc with
  | Spl.FArg(n, _) -> Var(Func, n)
  | Spl.PreWrap(n, l, funcs, _) -> FunctionCall(n, ((List.map expr_of_intexpr l)@(List.map expr_of_idxfunc funcs)))
;;


(*FIXME, move count somewhere else, rename genvar*)
let count = ref 0
;;
let genvar (ctype:ctype) : expr = 
  count := !count + 1;
  Var(ctype, "t"^(string_of_int (!count)))
;;

let rec code_of_func (func : Spl.idxfunc) ((input,code):expr * code list) : expr * code list =
  match func with
  |Spl.FH(_,_,b,s) -> let output = genvar(Int) in
		      (output,code@[Declare(output);Assign(output, Plus((expr_of_intexpr b), Mul((expr_of_intexpr s),input)))])
  |Spl.FD(n,k) -> let output = genvar(Complex) in
		  (output,code@[Declare(output);Assign(output, FunctionCall("omega", [(expr_of_intexpr n);UniMinus(Mul(Mod(input,(expr_of_intexpr k)), Divide(input,(expr_of_intexpr k))))]))])
  |Spl.FArg(_,_) -> let output = genvar(Complex) in
		    (output,code@[Declare(output);Assign(output, MethodCall(expr_of_idxfunc func, _at, [input]))])  
  |Spl.FCompose l -> List.fold_right code_of_func l (input,[])
;;

let rec white (n:int) : string =
  if (n <= 0) then
    ""
  else
    " "^(white (n-1))
;;

let rec ctype_of_expr (expr:expr) : ctype =
  match expr with
  | Var(ctype, _) -> ctype
;;


let rec string_of_code (n:int) (code : code) : string =
  (white n)^(
    match code with
      Chain l -> "Chain( [\n"^(String.concat ";\n" (List.map (string_of_code (n+4)) l))^"\n"^(white n)^"] )"
    | PlacementNew(l, r) -> "PlacementNew("^(string_of_expr l)^", "^(string_of_expr r)^")"
    | Assign(l, r) -> "Assign("^(string_of_expr l) ^ ", "^ (string_of_expr r) ^ ")"
    | Loop(var, expr, code) -> "Loop("^(string_of_expr var)^", "^(string_of_expr expr)^", \n"^(string_of_code  (n+4) code)^"\n"^(white n)^")"
    | ArrayAllocate(expr,elttype,int) -> "ArrayAllocate("^(string_of_expr expr)^", "^(string_of_ctype(elttype))^", "^(string_of_expr int)^")"
    | ArrayDeallocate(buf, size) -> "ArrayDeallocate("^(string_of_expr buf)^", "^(string_of_expr size)^")"
    | Return(expr) -> "Return("^(string_of_expr expr)^")"
    | Declare(expr) -> "Declare("^(string_of_expr expr)^")"
    | Noop -> "Noop"
   )   
;;

let meta_transform_code_on_code (recursion_direction: Spl.recursion_direction) (f : code -> code) : (code -> code) =
  let z (g : code -> code) (e : code) : code = 
    match e with
    | Chain l -> Chain (List.map g l)
    | Loop(var, expr, code) -> Loop(var, expr, (g code))
    | PlacementNew _ | Assign _ | ArrayAllocate _ | ArrayDeallocate _ | Return _ | Declare _ | Noop _ -> e
  in
  Spl.recursion_transform recursion_direction f z
;;

let meta_transform_expr_on_expr (recursion_direction: Spl.recursion_direction) (f : expr -> expr) : (expr -> expr) =
  let z (g : expr -> expr) (e : expr) : expr = 
    match e with
    | Equal(a,b) -> Equal(g a, g b)
    | Plus(a,b) -> Plus(g a, g b)
    | Mul(a,b) -> Mul(g a, g b)
    | Cast(expr,ctype) -> Cast(g expr, ctype)
    | Nth(expr, count) -> Nth(g expr, g count)
    | Var _ | Const _ -> e
    | x -> failwith ("Pattern_matching failed:\n"^(string_of_expr x))
  in
  Spl.recursion_transform recursion_direction f z
;;

let meta_transform_expr_on_code (recursion_direction: Spl.recursion_direction) (f : expr -> expr) : (code -> code) =
  let g = meta_transform_expr_on_expr recursion_direction f in
  meta_transform_code_on_code recursion_direction ( function 
  | Declare e -> Declare (g e)
  | Assign(l, r) -> Assign(g l, g r)
  | Chain _ as x -> x 
  | x -> failwith ("Pattern_matching failed:\n"^(string_of_code 0 x))
  )
;;

let expr_substitution_on_expr (target : expr) (replacement : expr) : (expr -> expr) =
  let g (e: expr) : expr = 
    if (e = target) then replacement else e
  in
  meta_transform_expr_on_expr Spl.TopDown g
;;

let expr_substitution_on_code (target : expr) (replacement : expr) : (code -> code) =
  let g (e: expr) : expr = 
    if (e = target) then replacement else e
  in
  meta_transform_expr_on_code Spl.TopDown g
;;

let rec range i j = if i > j then [] else i :: (range (i+1) j)
;;


let meta_chain_code (recursion_direction: Spl.recursion_direction) (f : code list -> code list) : (code -> code) =
  meta_transform_code_on_code recursion_direction ( function 
  | Chain (l) -> Chain (f l) 
  | x -> x)
;;

let rule_flatten_chain : (code -> code) =
  let rec f (l : code list) : code list = 
  match l with
  | Chain(a)::tl -> f (a @ tl)
  | Noop::tl -> f(tl)
  | a::tl -> a :: (f tl)
  | [] -> []
  in
  meta_chain_code Spl.BottomUp f
;;  

let remove_decls : (code -> code) =
  meta_transform_code_on_code Spl.BottomUp ( function
  | Declare x -> Noop
  | x -> x
  )
;;

let declare_free_vars (l: code list) : code list =
  (* compute all free variables *)
  (* declare all free variables *)
  l
;;

let rec reintroduce_decls : (code -> code) =
  meta_transform_code_on_code Spl.BottomUp ( function 
  | Chain (l) -> let decls = declare_free_vars l in Chain (decls @ l) 
  | x -> x)
;;

(* FIXME write the code *)
let rec flatten_chain (code:code) : code =
  rule_flatten_chain (remove_decls code) 
;;



(* takes the code into a multidecl form*)
let rec unroll_loops (code:code) : code =
  meta_transform_code_on_code Spl.TopDown ( function 
  | Loop(var, Const n, c) -> 
    let g (i:int) = expr_substitution_on_code var (Const i) c in
    Chain (List.map g (range 0 (n-1)))
  | x -> x
  ) code
;;

let compile_basic_bloc (code:code) : code = 
  let res = flatten_chain (unroll_loops code) in
  print_string(string_of_code 0 res);
  print_string "\n\n\n\n\n";
  res
;;

let code_of_rstep (rstep_partitioned : rstep_partitioned) : code =
  let collect_children ((name, rstep, cold, reinit, hot, funcs, breakdowns ) : rstep_partitioned) : expr list =
    let res = ref IntSet.empty in  
    let g ((condition,freedoms,desc,desc_with_calls,desc_cons,desc_comp):breakdown_enhanced) : _ =
      Spl.meta_iter_spl_on_spl (function
      | Spl.Construct(numchild, _, _, _) | Spl.ISumReinitConstruct(numchild, _, _, _, _, _, _) -> res := IntSet.add numchild !res
      | _ -> ()
      ) desc_cons;    
    in
    List.iter g breakdowns;
    List.map build_child_var (IntSet.elements !res)
  in

(*we should probably generate content while we are generating it instead of doing another pass*)
  let collect_freedoms ((name, rstep, cold, reinit, hot, funcs, breakdowns ) : rstep_partitioned) : expr list =
    let res = ref [] in  
    let g ((condition,freedoms,desc,desc_with_calls,desc_cons,desc_comp):breakdown_enhanced) : _ =
      res := (List.map (fun (l,r)->expr_of_intexpr l) freedoms) @ !res    
    in
    List.iter g breakdowns;
    !res  
  in

  let cons_code_of_rstep ((name, rstep, cold, reinit, hot, funcs, breakdowns ) : rstep_partitioned) : code =
    let rec prepare_cons (e:Spl.spl) : code =
      (* print_string ("BOOM:"^(Spl.string_of_spl e)^"\n"); *)
      match e with
      | Spl.Compose l -> Chain (List.map prepare_cons (List.rev l)) 
      | Spl.Construct(numchild, rs, args, funcs) -> Assign(build_child_var(numchild), New(FunctionCall(rs, (List.map expr_of_intexpr (args))@(List.map (fun(x)->New(expr_of_idxfunc x)) funcs))))
      | Spl.ISumReinitConstruct(numchild, i, count, rs, cold, reinit, funcs) ->
	let child = build_child_var(numchild) in
	Chain([
	  ArrayAllocate(child, Env(rs), (expr_of_intexpr count));
	  Loop(expr_of_intexpr i, expr_of_intexpr count, (
	    PlacementNew( 
	      (AddressOf(Nth(Cast(child, Ptr(Env(rs))), expr_of_intexpr i))),
	      (FunctionCall(rs, (List.map expr_of_intexpr (cold@reinit))@(List.map (fun(x)->New(expr_of_idxfunc x)) funcs))))
	  ))
	])
      | Spl.Diag Spl.Pre(idxfunc) -> let var = genvar(Int) in
				     let (precomp, codelines) = code_of_func idxfunc (var,[]) in			    
				     Chain([
				       ArrayAllocate(_dat, Complex, expr_of_intexpr(Spl.range(e)));
				       Loop(var, expr_of_intexpr(Spl.range(e)),
					    Chain(codelines@[
					      Assign((Nth(Cast(_dat,Ptr(Complex)),var)),precomp)]))
				     ])
      | Spl.S _ | Spl.G _ | Spl.F _ -> Chain([])
      | Spl.BB spl -> prepare_cons spl

    in
    let rulecount = ref 0 in
    let g (stmt:code) ((condition,freedoms,desc,desc_with_calls,desc_cons,desc_comp):breakdown_enhanced) : code  =
      let freedom_assigns = List.map (fun (l,r)->Assign(expr_of_intexpr l, expr_of_intexpr r)) freedoms in
      rulecount := !rulecount + 1;      
      If( Var(Bool, Spl.string_of_boolexpr condition), 
	 Chain( [Assign(_rule, expr_of_intexpr(Spl.IConstant !rulecount))] @ freedom_assigns @ [prepare_cons desc_cons]),
	 stmt)	
    in
    List.fold_left g (Error("no applicable rules")) breakdowns
  in

  let comp_code_of_rstep ((name, rstep, cold, reinit, hot, funcs, breakdowns ) : rstep_partitioned) (output:expr) (input:expr): code =
    let rec prepare_comp (output:expr) (input:expr) (e:Spl.spl): code =
      match e with
      | Spl.Compose l -> let ctype = Complex in
			 let buffernames = 
			   let count = ref 0 in
			   let g (res:expr list) (_:Spl.spl) : expr list = 
			     count := !count + 1; 
			     (Var(Ptr(ctype), "T"^(string_of_int !count))) :: res 
			   in
			   List.fold_left g [] (List.tl l) in
			 let out_in_spl = (List.combine (List.combine (buffernames @ [ output ]) (input :: buffernames)) (List.rev l)) in
			 let buffers = (List.combine (buffernames) (List.map Spl.range (List.rev (List.tl l)))) in
			 Chain (
			   (List.map (fun (output,size)->(Declare output)) buffers)
			   @ (List.map (fun (output,size)->(ArrayAllocate(output,ctype,expr_of_intexpr(size)))) buffers)
			   @ (List.map (fun ((output,input),spl)->(prepare_comp output input spl)) out_in_spl)
			   @ (List.map (fun (output,size)->(ArrayDeallocate(output,expr_of_intexpr(size)))) buffers)
			 )
      | Spl.ISum(i, count, content) -> Loop(expr_of_intexpr i, expr_of_intexpr count, (prepare_comp output input content))
      | Spl.Compute(numchild, rs, hot,_,_) -> Ignore(MethodCall (Cast((build_child_var(numchild)),Ptr(Env(rs))), _compute, output::input::(List.map expr_of_intexpr hot)))
      | Spl.ISumReinitCompute(numchild, i, count, rs, hot,_,_) -> 
	Loop(expr_of_intexpr i, expr_of_intexpr count, Ignore(MethodCall(
	  (AddressOf(Nth(Cast(build_child_var(numchild), Ptr(Env(rs))), expr_of_intexpr i)))
	  , _compute, output::input::(List.map expr_of_intexpr hot))))
      | Spl.F 2 -> Chain([
	Assign ((Nth(output,(Const 0))), (Plus (Nth(input, (Const 0)), (Nth(input, (Const 1))))));
	Assign ((Nth(output,(Const 1))), (Minus (Nth(input, (Const 0)), (Nth(input, (Const 1))))))])
      | Spl.S idxfunc -> let var = genvar(Int) in
			 let (index, codelines) = code_of_func idxfunc (var,[]) in			    
			     Loop(var, expr_of_intexpr(Spl.domain(e)),
				  Chain(codelines@[Assign((Nth(output,index)), (Nth(input,var)))])) 
      | Spl.G idxfunc -> let var = genvar(Int) in
			 let (index, codelines) = code_of_func idxfunc (var,[]) in			    
			     Loop(var, expr_of_intexpr(Spl.range(e)),
				  Chain(codelines@[Assign((Nth(output,var)), (Nth(input,index)))])) 
      | Spl.Diag _ -> let var = genvar(Int) in
		      Loop(var, expr_of_intexpr(Spl.range(e)),
			   Assign((Nth(output,var)), Mul(Nth(input,var),Nth(Cast(_dat,Ptr(Complex)),var))))
      | Spl.BB spl -> compile_basic_bloc(prepare_comp output input spl)
    in
    let rulecount = ref 0 in
    let g (stmt:code) ((condition,freedoms,desc,desc_with_calls,desc_cons,desc_comp):breakdown_enhanced) : code  =
      rulecount := !rulecount + 1;
      
      If(Equal(_rule, expr_of_intexpr(Spl.IConstant !rulecount)),
	 prepare_comp output input desc_comp, 
	 stmt)
	
    in
    List.fold_left g (Error("internal error: no valid rule has been selected")) breakdowns
  in

  let (name, rstep, cold, reinit, hot, funcs, breakdowns) = rstep_partitioned in 
  let cons_args = (List.map expr_of_intexpr ((IntExprSet.elements (cold))@(IntExprSet.elements (reinit))))@(List.map expr_of_idxfunc funcs) in
  Class (name, _rs, _rule::_dat::cons_args@(collect_children rstep_partitioned) @ (collect_freedoms rstep_partitioned), [
    Constructor(cons_args, cons_code_of_rstep rstep_partitioned);	       
    Method(Void, _compute, _output::_input::List.map expr_of_intexpr (IntExprSet.elements hot), comp_code_of_rstep rstep_partitioned _output _input)])
;;

let code_of_envfunc ((name, f, args, fargs) : envfunc) : code =  
  let input = genvar(Int) in
  let(output, code) = (code_of_func f (input,[])) in
  let cons_args = (List.map expr_of_intexpr args)@(List.map expr_of_idxfunc fargs) in
  Class(name, _func, cons_args, [
    Constructor(cons_args, Noop);
    Method(Complex, _at, [input], Chain(code@[Return(output)]))])
;;

let code_of_lib ((funcs,rsteps) : lib) : code list = 
  (List.map code_of_envfunc funcs)@(List.map code_of_rstep rsteps)
;;

