open Codegen
;;

let rec white (n:int) : string =
  if (n <= 0) then
    ""
  else
    " "^(white (n-1))
;;

type unparse_type =
  Prototype
| Implementation
;;

let rec ctype_of_expr (expr:expr) : ctype =
  match expr with
  | Var(ctype, _) -> ctype
;;

let make_signatures (l:'a list) : string list =
  List.map (fun expr -> (string_of_ctype (ctype_of_expr expr))^" "^(string_of_expr expr)) (l)
;;
 
let rec cpp_string_of_code (unparse_type:unparse_type) (n:int) (code : code) : string =
  match code with
  | Class(name,super,privates,methods) ->  
    (match unparse_type with
      Prototype -> 
	(white n) ^ "struct "^name^" : public "^super^" {\n" 
	^ (String.concat "" (List.map (fun x -> (white (n+4))^x^";\n") (make_signatures privates)))
	^ (white (n+4))
    | Implementation -> 
      (white n) ^ name ^ "::")
    ^ (String.concat "" (List.map (fun x -> cpp_string_of_cmethod unparse_type n name x) methods))
    ^ 
      (match unparse_type with
	Prototype -> (white n) ^ "private:" ^ "\n"
	  ^ (white (n+4)) ^ name ^ "(const " ^ name ^ "&);" ^ "\n"
	  ^ (white (n+4)) ^ name ^ "& operator=(const " ^ name ^"&);" ^ "\n"
	  ^ "};\n\n"
      | Implementation -> "\n")
      
	
  | Chain l -> String.concat "" (List.map (cpp_string_of_code unparse_type n) l)
  | PlacementNew(l, r) -> (white n)^"new ("^(string_of_expr l)^") "^(string_of_expr r)^";\n" 
  | Assign(l, r) -> (white n) ^ (string_of_expr l) ^ " = "^ (string_of_expr r) ^ ";\n"
  | Noop -> (white n)^"/* noop */\n"
  | Error str -> (white n)^"error(\""^str^"\");\n"
  | If (cond, path_a, path_b) -> (white n)^"if ("^(string_of_expr cond)^") {\n"^(cpp_string_of_code unparse_type (n+4) path_a)^(white n)^"} else {\n"^(cpp_string_of_code unparse_type (n+4) path_b)^(white n)^"}\n"
  | Loop(var, expr, code) -> (white n)^"for(int "^(string_of_expr var)^" = 0; "^(string_of_expr var)^" < "^(string_of_expr expr)^"; "^(string_of_expr var)^"++){\n"^(cpp_string_of_code unparse_type (n+4) code)^(white n)^"}\n" 
  | ArrayAllocate(expr,elttype,int) -> (white n)^(string_of_expr expr)^" = ("^(string_of_ctype(Ptr(elttype)))^") malloc (sizeof("^(string_of_ctype(elttype))^") * "^(string_of_expr int)^");\n"
  | ArrayDeallocate(buf, size) -> (white n)^"free("^(string_of_expr buf)^");\n"
  | Return(expr) -> (white n)^"return "^(string_of_expr expr)^";\n"
  | Declare(expr) -> (white n)^(string_of_ctype(ctype_of_expr expr))^" "^(string_of_expr expr)^";\n"
  | Ignore(expr) -> (white n)^(string_of_expr expr)^";\n"
and 
    cpp_string_of_cmethod (unparse_type:unparse_type) (n:int) (name:string) (cmethod:cmethod) : string =
  match cmethod with 
    Method(return_type, method_name, args, code) ->
      (match unparse_type with
      | Prototype -> (white (n+4))^(string_of_ctype return_type)^" "
      | Implementation -> (white (n))^(string_of_ctype return_type)^" "^name ^ "::")
      ^ method_name^"(" ^ (String.concat ", " (make_signatures args)) 
      ^ ")"^ 
	(match unparse_type with
	  Prototype -> ";\n"
	| Implementation -> "{\n"^(cpp_string_of_code unparse_type (n+4) code)^(white n)^"}\n")
  | Constructor(args, code) ->
    (white (n))^ name^"(" ^ (String.concat ", " (make_signatures args)) 
    ^ ")"^ 
      (match unparse_type with
	Prototype -> ";\n"
      | Implementation -> "\n"^(white (n+4))^": "^(String.concat ", " (List.map (fun x -> (string_of_expr x)^"("^(string_of_expr x)^")" ) args))^" {\n"^(cpp_string_of_code unparse_type (n+4) code)^(white n)^"}\n")
;;

let string_of_code (n:int) (code : code) : string = 
  "#include <new>\n"
  ^ "#include <string>\n"
  ^ "#include <stdlib.h>\n"
  ^ "#include <complex>\n\n"
  ^ "#include <vector>\n\n"
  ^ "static int divisor(int ) {return 2;} /*FIXME*/\n"
  ^ "static void error(std::string s) {throw s;}\n"

  ^ "// standard Eratosthene sieve\n"
  ^ "std::vector<std::pair<int, int> > _prime_factorization(int c){\n"
  ^ "    std::vector<std::pair<int, int> > v;\n"
  ^ "    int freq=0;\n"
  ^ "\n"
  ^ "    /* zero has no divisors */\n"
  ^ "    if(c==0) return v;\n"
  ^ "\n"
  ^ "    while ((c%2)==0) {\n"
  ^ "        freq++;\n"
  ^ "        c = c/2;\n"
  ^ "    }\n"
  ^ "    if (freq>0){\n"
  ^ "        std::pair<int, int> p(2, freq);\n"
  ^ "        v.push_back(p);\n"
  ^ "    }\n"
  ^ "\n"
  ^ "    for(int i=3; i<=(sqrt((double)c)+1); i+=2) {\n"
  ^ "        freq = 0;\n"
  ^ "        while ((c%i) == 0) {\n"
  ^ "            freq++;\n"
  ^ "            c = c/i;\n"
  ^ "        }\n"
  ^ "        if (freq>0){\n"
  ^ "            std::pair<int, int> p(i, freq);\n"
  ^ "            v.push_back(p);\n"
  ^ "        }\n"
  ^ "	}\n"
  ^ "\n"
  ^ "    if (c > 1){\n"
  ^ "        std::pair<int, int> p(c, 1);\n"
  ^ "        v.push_back(p);\n"
  ^ "    }\n"
  ^ "    return v;\n"
  ^ "    }\n"
  ^ "\n"
  ^ "\n"
  ^ "bool isPrime(int n) {\n"
  ^ "    std::vector<std::pair<int, int> > fac = _prime_factorization(n);\n"
  ^ "    // n = n^1, list contains (prime, power) entries\n"
  ^ "    return (fac.size()==1 && fac[0].first==n);\n"
  ^ "}\n"


  ^ "#define complex_t std::complex<float>\n"
  ^ "#define PI    3.14159265358979323846f\n"
  ^ "#define __I__ (complex_t(0,1))\n"
  ^ "static complex_t omega(int N, int k) { return cosf(2*PI*k/N) + __I__ * sinf(2*PI*k/N); }\n"
  ^ "struct RS { virtual ~RS(){}};\n"
  ^ "template<class T> struct TFunc_TInt_T : public RS { virtual T at(int) = 0; };\n"
  ^ "struct func : public TFunc_TInt_T<complex_t> {};\n\n"
  ^ (cpp_string_of_code Prototype n code)
  ^ (cpp_string_of_code Implementation n code)
;;

