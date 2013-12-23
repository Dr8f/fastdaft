(******    TYPES    *******)

open Spl
;;

module SplMap = Map.Make (struct
  type t = spl
  let compare = Pervasives.compare
end)

module IntExprSet = Set.Make (struct
  type t = intexpr
  let compare = Pervasives.compare
end)
;;

type breakdown = (boolexpr * (intexpr * intexpr) list * spl * spl)
;;

type rstep_unpartitioned = (string * spl * IntExprSet.t * breakdown list )
;;

type closure = rstep_unpartitioned list
;;

type breakdown_enhanced = (boolexpr * (intexpr * intexpr) list * spl * spl * spl * spl)
;;

type rstep_partitioned = (string * spl * IntExprSet.t * IntExprSet.t * IntExprSet.t * breakdown_enhanced list)
;;

type lib = rstep_partitioned list
;;

type specified_arg = string * int
;;

module SpecArgMap = Map.Make (struct
  type t = specified_arg
  let compare = Pervasives.compare
end)
;;

module SpecArgSet = Set.Make (struct
  type t = specified_arg
  let compare = Pervasives.compare
end)
;;


(******** PRINTING *******)

let string_of_breakdown_enhanced ((condition, freedoms, desc, desc_with_calls, desc_with_calls_cons, desc_with_calls_comp):breakdown_enhanced) : string = 
  "APPLICABLE\t\t"^(string_of_boolexpr condition)^"\n"
  ^"FREEDOM\t\t\t"^(String.concat ", " (List.map string_of_intexpr_intexpr freedoms))^"\n"
  ^"DESCEND\t\t\t"^(string_of_spl desc)^"\n"
  ^"DESCEND - CALLS\t\t"^(string_of_spl desc_with_calls)^"\n"
  ^"DESCEND - CALLS CONS\t"^(string_of_spl desc_with_calls_cons)^"\n"
  ^"DESCEND - CALLS COMP\t"^(string_of_spl desc_with_calls_comp)^"\n"
;;

let string_of_rstep_partitioned ((name, rstep, cold, reinit, hot, breakdowns ): rstep_partitioned) : string =
  "NAME\t\t\t"^name^"\n"
  ^"RS\t\t\t"^(string_of_spl rstep)^"\n"
  ^"COLD\t\t\t"^(String.concat ", " (List.map string_of_intexpr (IntExprSet.elements cold)))^"\n"
  ^"REINIT\t\t\t"^(String.concat ", " (List.map string_of_intexpr (IntExprSet.elements reinit)))^"\n"
  ^"HOT\t\t\t"^(String.concat ", " (List.map string_of_intexpr (IntExprSet.elements hot)))^"\n"
  ^(String.concat "" (List.map string_of_breakdown_enhanced breakdowns))^"\n"
  ^"\n"
;;

let string_of_lib (lib: lib) : string =
  String.concat "" (List.map string_of_rstep_partitioned lib)
;;


(**********************
      CLOSURE
***********************)

let mark_RS : spl -> spl =
  meta_transform_spl_on_spl BottomUp ( function
  |DFT n -> RS(DFT(n))
  | x -> x)
;;  

let collect_RS: spl -> spl list =
  meta_collect_spl_on_spl ( function
  | RS(x) -> [x]
  | _ -> []
)
;;

let rec extract_constraints_func (e : idxfunc) : (intexpr * intexpr) list =
  let rec extract_constraints_within_fcompose (e : idxfunc list) (res : (intexpr * intexpr) list) : (intexpr * intexpr) list = 
    match e with
      x :: (y :: tl as etl) -> let dmn = func_domain x in
			       let rng = func_range y in
			       (* print_string ("!!!!"^(string_of_intexpr dmn)^"="^(string_of_intexpr rng)^"\n") ;   *)
			       extract_constraints_within_fcompose etl ((dmn, rng) :: res)
    | [x] -> res;
    | [] -> res
  in
  match e with
  | FCompose l -> extract_constraints_within_fcompose l (List.flatten (List.map extract_constraints_func l))
  | Pre x -> extract_constraints_func x 
  | _ -> []
;;


let rec extract_constraints_spl (e : spl) : (intexpr * intexpr) list =
  let rec extract_constraints_within_compose (e : spl list) ( res : (intexpr * intexpr) list) : (intexpr * intexpr) list = 
    match e with
      x :: (y :: tl as etl) -> let dmn = domain x in
			       let rng = range y in
			       (* print_string ((string_of_intexpr dmn)^"="^(string_of_intexpr rng)^"\n") ;  *)
			       extract_constraints_within_compose etl ((dmn, rng) :: res)
    | [x] -> res;
    | [] -> res
  in
  match e with 
    Compose l -> extract_constraints_within_compose l (List.flatten (List.map extract_constraints_spl l))
  | Diag x -> extract_constraints_func x
  | _ -> []    
;;

let rec reconcile_constraints (constraints : (intexpr * intexpr) list) (spl : spl) : spl =
  match constraints with
    (l,r) :: tl -> let f (e : intexpr) : intexpr = if (e=r) then l else e in
		   reconcile_constraints (List.map (fun (l,r) -> (f l, f r)) tl) ((meta_transform_intexpr_on_spl TopDown f) spl)
  | [] -> spl
;;

let wrap_intexprs_naively (e :spl) : spl =
  let count = ref 0 in
  let f (i : intexpr) : intexpr = 
    match i with 
      IMul _ | IPlus _ | IDivPerfect _ | IFreedom _ | ILoopCounter _ | IArg _ -> 
	count := !count + 1;
	ICountWrap(!count, i)
    | x -> x
  in
  (meta_transform_intexpr_on_spl TopDown f) e
;;

let wrap_intexprs (e : spl) : spl  =
  let wrapup = wrap_intexprs_naively e in
  let constraints = extract_constraints_spl wrapup in
  let res = reconcile_constraints constraints wrapup in
  res
;;

let reintegrate_RS (e: spl) (canonized : spl list) : spl =
  let rem = ref canonized in
  let f (e:spl) : spl =
    match e with
    | RS _ -> let hd = List.hd !rem in 
	      rem := List.tl !rem;
	      RS (hd)
    | x -> x
  in
  (meta_transform_spl_on_spl TopDown f) e
;;

let unwrap (e:spl) : spl =
  let g (e:intexpr) : intexpr = 
    match e with
      ICountWrap(l,r)->IArg l
    | x -> x
  in
  (meta_transform_intexpr_on_spl TopDown g) e
;;

let drop_RS : (spl -> spl) =
  let g (e : spl) : spl = 
    match e with
    | RS(x) -> x
    | x -> x
  in
  meta_transform_spl_on_spl BottomUp g
;;

let replace_by_a_call ((spl,name):spl * string) : spl =
  let collect_binds (spl:spl) : 'a list = 
    let binds (i : intexpr) : 'a list =
      match i with
	ICountWrap _ -> [i]
      | _ -> []
    in
    ((meta_collect_intexpr_on_spl binds) spl) in
  let rec mapify (binds : intexpr list) (map : 'a IntMap.t) : 'a IntMap.t =
    match binds with
      [] -> map
    | ICountWrap(p,expr)::tl -> mapify tl (IntMap.add p expr map)
    | _ -> failwith "type is not supported"
  in
  UnpartitionnedCall(name, (mapify (collect_binds spl) IntMap.empty ))
;;

let collect_args (rstep : spl) : IntExprSet.t = 
  let args = ref  IntExprSet.empty in
  let g (e : intexpr) : _ =
    match e with
    | IArg _ -> args := IntExprSet.add e !args
    | _ -> ()
  in
  meta_iter_intexpr_on_spl g rstep;
  !args
;;


let compute_the_closure (stems : spl list) (algo : spl -> boolexpr * (intexpr*intexpr) list * spl) : closure = 
  let under_consideration = ref [] in
  let rsteps = ref [] in
  let namemap = ref SplMap.empty in
  let count = ref 0 in
  let register_name (rstep:spl) : _ =
    count := !count + 1;
    let name = "RS"^(string_of_int !count) in
    namemap := SplMap.add rstep name !namemap;
    under_consideration := !under_consideration@[rstep];    
  in
  let ensure_name (rstep:spl) : string =
    if not(SplMap.mem rstep !namemap) then (
      register_name rstep;
    );
    SplMap.find rstep !namemap
  in
  List.iter register_name stems;
  while (List.length !under_consideration != 0) do
    let rstep = List.hd !under_consideration in
    under_consideration := List.tl !under_consideration;
    let name = ensure_name rstep in
    let args = collect_args rstep in
    let (condition, freedoms, naive_desc) = algo rstep in
    let desc = apply_rewriting_rules (mark_RS(naive_desc)) in
    let wrapped_RSes = List.map wrap_intexprs (collect_RS desc) in
    let new_steps = List.map unwrap wrapped_RSes in
    let new_names = List.map ensure_name new_steps in
    let extracts_with_calls = List.map replace_by_a_call (List.combine wrapped_RSes new_names) in
    let desc_with_calls = drop_RS (reintegrate_RS desc extracts_with_calls) in
    rsteps := !rsteps @ [(name, rstep, args, [(condition, freedoms, desc, desc_with_calls)])];
  done;
  !rsteps
;;

let dependency_map_of_closure (closure : closure) : SpecArgSet.t SpecArgMap.t =
  let depmap = ref SpecArgMap.empty in 
  let per_rstep ((name, _, _, breakdowns) : rstep_unpartitioned) : _=   
    let per_rule ((_,_,_,desc_with_calls):breakdown) : _ = 
      meta_iter_spl_on_spl ( function
      | UnpartitionnedCall(callee,vars) ->
	let g (arg:int) (expr:intexpr) : _ =
    	  let key = (callee,arg) in
    	  let h (e:intexpr): _ =
    	    match e with
    	      IArg i ->
    		let new_content = (name,i) in
    		depmap :=
    		  if (SpecArgMap.mem key !depmap) then
    		    SpecArgMap.add key (SpecArgSet.add new_content (SpecArgMap.find key !depmap)) !depmap
    		  else
    		    SpecArgMap.add key (SpecArgSet.singleton new_content) !depmap
    	    | _ -> ()
    	  in
    	  meta_iter_intexpr_on_intexpr h expr
	in
	IntMap.iter g vars
      | _ -> ()
      ) desc_with_calls	
    in
    List.iter per_rule breakdowns
  in
  List.iter per_rstep closure;
  (!depmap)
;;

let initial_hots_of_closure (closure: closure) : SpecArgSet.t =
  let hot_set = ref SpecArgSet.empty in
  let per_rstep ((name, _, _, breakdowns) : rstep_unpartitioned) : _=   
    let per_rule ((_,_,_,desc_with_calls):breakdown) : _ = 
      meta_iter_spl_on_spl ( function
      | UnpartitionnedCall(callee,vars) ->
	let g (arg:int) (expr:intexpr) : _ =
    	  let h (e:intexpr): _ =
    	    match e with
    	    | ILoopCounter _ -> hot_set := SpecArgSet.add (callee,arg) !hot_set 
    	    | _ -> ()
    	  in
    	  meta_iter_intexpr_on_intexpr h expr
	in
	IntMap.iter g vars
      | _ -> ()
      ) desc_with_calls	
    in
    List.iter per_rule breakdowns
  in
  List.iter per_rstep closure;
  !hot_set
;;



let initial_colds_of_closure (closure: closure) : SpecArgSet.t =
  let cold_set = ref SpecArgSet.empty in

  let init_rstep ((name, rstep, args, breakdowns) : rstep_unpartitioned) : _=
    let add_args_to_cold (e:intexpr) : _ =
      match e with
	IArg i -> 
	  cold_set := SpecArgSet.add (name,i) !cold_set
      | x -> ()
    in
    (* all arguments in the pre() marker must be cold *)
    let add_all_pre_to_cold (e:idxfunc) : _ =
      match e with 
      | Pre x -> 
	meta_iter_intexpr_on_idxfunc add_args_to_cold x
      | _ -> ()
    in
    meta_iter_idxfunc_on_spl add_all_pre_to_cold rstep;
    
    let init_rule ((condition,freedoms,desc,desc_with_calls):breakdown) : _ = 
      (* all arguments in condition (intexpr list) *)
      meta_iter_intexpr_on_boolexpr add_args_to_cold condition;
      
      (* all arguments in freedoms ((intexpr*intexpr) list) must be cold *)
      List.iter (meta_iter_intexpr_on_intexpr add_args_to_cold) (List.map snd freedoms)
    in
    List.iter init_rule breakdowns
  in
  List.iter init_rstep closure;
  !cold_set
;;


let backward_propagation (init_set:SpecArgSet.t) (dependency_map:SpecArgSet.t SpecArgMap.t) : SpecArgSet.t =
  let res = ref init_set in
  let dirty = ref true in
  let f (callee:specified_arg) (caller_set:SpecArgSet.t) : _ = 
    if SpecArgSet.mem callee !res then
      (
	let g (caller:specified_arg) : _= 
	  if not(SpecArgSet.mem caller !res) then
	  (
	    res := SpecArgSet.add caller !res;
	    dirty := true;
	  )	    
	in
	SpecArgSet.iter g caller_set;
      )
  in
  while (!dirty) do 
    dirty := false;
    SpecArgMap.iter f dependency_map;
  done ;
  !res
;;

let forward_propagation (init_set:SpecArgSet.t) (dependency_map:SpecArgSet.t SpecArgMap.t) : SpecArgSet.t =
  let res = ref init_set in
  let dirty = ref true in
  let forward_hot_propagation (callee:specified_arg) (caller_set:SpecArgSet.t) : _ = 
    if not(SpecArgSet.mem callee !res) then
      (
	let g (caller:specified_arg) : _= 
	  if SpecArgSet.mem caller !res then
	  (
	    res := SpecArgSet.add callee !res;
	    dirty := true;
	  )	    
	in
	SpecArgSet.iter g caller_set;
      )
  in
  while (!dirty) do 
    dirty := false;
    SpecArgMap.iter forward_hot_propagation dependency_map;
  done ;
  !res
;;

let filter_by_rstep (name:string) (s:SpecArgSet.t) : IntExprSet.t =
  let res = ref IntExprSet.empty in
  let f ((rs,i):specified_arg) : _ =
    if (rs = name) then
      res := IntExprSet.add (IArg i) !res
  in
  SpecArgSet.iter f s;
  !res
;;

let partition_map_of_closure (closure: closure) : (IntExprSet.t StringMap.t * IntExprSet.t StringMap.t * IntExprSet.t StringMap.t) = 
  let dependency_map = dependency_map_of_closure closure in
  let initial_colds = initial_colds_of_closure closure in
  let initial_hots = initial_hots_of_closure closure in
  let all_colds = backward_propagation initial_colds dependency_map in
  let all_hots = forward_propagation initial_hots dependency_map in

  let colds = ref StringMap.empty in
  let reinits = ref StringMap.empty in
  let hots = ref StringMap.empty in
  let partition_args ((name, rstep, args, breakdowns) : rstep_unpartitioned) : _=
    let necessarily_colds = filter_by_rstep name all_colds in
    let necessarily_hots = filter_by_rstep name all_hots in
    let not_constrained = IntExprSet.diff args (IntExprSet.union necessarily_colds necessarily_hots) in
    let reinit = IntExprSet.inter necessarily_colds necessarily_hots in
    reinits := StringMap.add name reinit !reinits;
    colds := StringMap.add name (IntExprSet.diff necessarily_colds reinit) !colds;
    hots := StringMap.add name (IntExprSet.diff (IntExprSet.union necessarily_hots not_constrained) reinit) !hots (* as hot as possible *)
  in
  List.iter partition_args closure;
  (!colds,!reinits,!hots)
;;

let lib_from_closure (closure: closure) : lib =
  let filter_by (args:intexpr IntMap.t) (set:IntExprSet.t) : intexpr list =
    List.map snd (List.filter (fun ((i,expr):int*intexpr) -> IntExprSet.mem (IArg i) set) (IntMap.bindings args))
  in
  let (cold,reinit,hot) = partition_map_of_closure closure in
  let f ((name, rstep, _, breakdowns) : rstep_unpartitioned) : rstep_partitioned =
    let g ((condition, freedoms, desc, desc_with_calls):breakdown) : breakdown_enhanced = 
      let h (e:spl) : spl =
	match e with
	| UnpartitionnedCall (callee, args) ->
  	  PartitionnedCall(callee, (filter_by args (StringMap.find callee cold)), (filter_by args (StringMap.find callee reinit)), (filter_by args (StringMap.find callee hot)))
	| x -> x
      in
      let partitioned = (meta_transform_spl_on_spl BottomUp h) desc_with_calls in
      let j (e:spl) : spl =
	match e with
	  ISum(_, _, PartitionnedCall(callee, cold, [], _)) -> Construct(callee, cold)
	| ISum(i, high, PartitionnedCall(callee, cold, reinit, _)) -> ISumReinitConstruct(i, high, callee, cold, reinit)
	| x -> x
      in
      let k (e:spl) : spl =
	match e with
	  PartitionnedCall(callee, _, [], hot) -> Compute(callee, hot)
	| ISum(i, high, PartitionnedCall(callee, _, _, hot)) -> ISumReinitCompute(i, high, callee, hot)
	| x -> x
      in
      (condition, freedoms, desc, partitioned, (meta_transform_spl_on_spl BottomUp j) partitioned, (meta_transform_spl_on_spl BottomUp k) partitioned) in
    (name, rstep, (StringMap.find name cold), (StringMap.find name reinit), (StringMap.find name hot), (List.map g breakdowns))
  in
  List.map f closure
;;

let make_lib (functionalities: spl list) (algo: spl -> boolexpr * (intexpr*intexpr) list * spl) : lib =
  let closure = compute_the_closure functionalities algo in
  lib_from_closure closure
;;

