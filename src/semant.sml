signature SEMANT =
sig
    type venv = Env.enventry Symbol.table
    type tenv = Types.ty Symbol.table

    type expty = {exp: Translate.exp, ty: Types.ty}

    val transExp: Translate.level * venv * tenv * Absyn.exp * Temp.label option  -> expty
(*    val transVar: venv * tenv * Abysn.dec -> expty *)
    val transDecs: Translate.level * venv * tenv * Absyn.dec list * Translate.exp list ref * Temp.label option-> {venv: venv, tenv: tenv}
    val transTy : tenv * Absyn.ty -> Types.ty
    val transProg: Absyn.exp -> Translate.fraglist
end

(* TODO: Function still refers to the parent level while processig the body. Fix that *)

structure Semant : SEMANT =
struct

structure E = Env
structure A = Absyn
structure T = Translate

type expty = {exp: Translate.exp, ty: Types.ty}

type venv = E.enventry Symbol.table
type tenv = Types.ty Symbol.table


fun checkInt ({exp, ty}, pos) = case ty of
   Types.INT => true
  | _  => (ErrorMsg.error pos "Integer expected"; false)


fun checkUnit ({exp = _, ty=Types.UNIT}, _) = ()
  | checkUnit (_, pos) = ErrorMsg.error pos "unit required"

fun lookupActualType(pos, tenv, ty) =
    case Symbol.look(tenv, ty)
     of SOME ty => actual_ty ty
      | NONE => (ErrorMsg.error pos ("Type '" ^ Symbol.name ty ^ "' is not defined"); Types.NIL)

and

 actual_ty (Types.NAME (s, tyref)) = (case !tyref of
                                      SOME t => actual_ty t
                                    | NONE => Types.NIL)
  | actual_ty t = t


fun find_type (tenv, sym, pos) =
    let
        val ty = Symbol.look (tenv, sym)
    in case ty of
           SOME t => t
         | NONE => (
             (ErrorMsg.error pos ("Unknown type " ^ Symbol.name sym));
                 Types.NIL)
    end

fun is_list_size_eq (a, b) = length a = length b

fun check_type_equality (ty1: Types.ty, ty2: Types.ty, pos, errormsg) =
    let
        fun types_equal (Types.INT, Types.INT) = true
          | types_equal (Types.STRING, Types.STRING) = true
          | types_equal (Types.UNIT, Types.UNIT) = true
          | types_equal (Types.NIL, Types.NIL) = true
          | types_equal (Types.ARRAY (t1, _), Types.ARRAY(t2, _)) =
            types_equal (actual_ty t1, actual_ty t2)
          | types_equal (Types.RECORD (fields1, _), Types.RECORD(fields2, _)) =
            length fields1 = length fields2 andalso
                        List.all (fn ((name1, ty1), (name2, ty2)) =>
                         name1 = name2 andalso types_equal (actual_ty ty1, actual_ty ty2))
                       (ListPair.zip (fields1, fields2))
          | types_equal (Types.NAME (s1, _), Types.NAME (s2, _)) = s1=s2
          | types_equal (ty1, ty2) = false
    in
        case types_equal (actual_ty ty1, actual_ty ty2) of
            true => ()
          | false => ErrorMsg.error pos errormsg
    end

(* Absyn.exp *)
fun transExp (level, venv, tenv, exp, breakpoint: Temp.label option) =
    let
        fun check_arth_param (left, right, pos, oper) =
        let
            val left_res = trexp left
            val right_res = trexp right
            val {exp = left_exp, ty=_} = left_res
            val {exp = right_exp, ty=_} = right_res
            val exp' = (Translate.arthExpr left_exp right_exp oper)
        in
                checkInt (left_res, pos);
                checkInt (right_res, pos);
                {exp = exp', ty=Types.INT}
        end

        and

        check_eq_noteq_param (left, right, pos) =
            let
                val {exp = exp_left, ty = ltype} = trexp left
                val {exp = exp_right, ty = rtype} = trexp right
                val exp_res = Translate.arthExpr exp_left exp_right A.EqOp
            in
                case (ltype, rtype) of
                    (Types.INT, Types.INT) => {exp = exp_res, ty=Types.INT}
                    | (Types.RECORD _, Types.RECORD _) => {exp = exp_res, ty=Types.INT}
                    | (Types.ARRAY _, Types.ARRAY _) => {exp = exp_res, ty=Types.INT}
                    | (_, _) => ((ErrorMsg.error pos "Cannot compare the two expression");
                                                    {exp = exp_res, ty=Types.NIL})
            end

        and

        find_ty (_, []) = NONE
        | find_ty (sym1, (sym2, typ2)::rest) =
          if (sym1 = sym2) then SOME typ2
          else find_ty (sym1, rest)

        and

        find_record_index _ [] pos _ = ((ErrorMsg.error pos "Cannot find the field to access in the record"); 0)
        | find_record_index fin_sym ((d_sym, _)::rest) pos index = 
            if (fin_sym = d_sym) then index
            else find_record_index fin_sym rest pos index+1

        and

         trexp A.NilExp = {exp =T.to_be_replaced, ty = Types.UNIT}

         | trexp (A.OpExp {left, oper=A.PlusOp, right, pos}) =
            check_arth_param (left, right, pos, A.PlusOp)

          | trexp  (A.OpExp {left, oper=A.MinusOp, right, pos}) =
            check_arth_param (left, right, pos, A.MinusOp)

          | trexp  (A.OpExp {left, oper=A.TimesOp, right, pos}) =
            check_arth_param (left, right, pos, A.TimesOp)

          | trexp  (A.OpExp {left, oper=A.DivideOp, right, pos}) =
            check_arth_param (left, right, pos, A.DivideOp)

          | trexp  (A.OpExp {left, oper=A.LtOp, right, pos}) =
            check_arth_param (left, right, pos, A.LtOp)

          | trexp  (A.OpExp {left, oper=A.LeOp, right, pos}) =
            check_arth_param (left, right, pos, A.LeOp)

          | trexp  (A.OpExp {left, oper=A.GtOp, right, pos}) =
            check_arth_param (left, right, pos, A.GtOp)

          | trexp  (A.OpExp {left, oper=A.GeOp, right, pos}) =
            check_arth_param (left, right, pos, A.GeOp)

          | trexp  (A.OpExp {left, oper=_, right, pos}) =
            check_eq_noteq_param (left, right, pos)

          | trexp (A.VarExp var) = trvar var

          | trexp (A.IntExp arg) = {exp = (Translate.intExp level arg), ty = Types.INT}

          | trexp  (A.StringExp (arg, _)) = {exp = (Translate.handleString arg), ty = Types.STRING} (* TODO: Handle string later *)

          | trexp (A.LetExp {decs, body, pos=_}) =
              let 
                val exps : Translate.exp list ref = ref []
                val {venv=venv', tenv=tenv'} = transDecs(level, venv, tenv, decs, exps, breakpoint)
                val {exp=body_exp, ty=let_ty} = transExp (level, venv', tenv', body, breakpoint)
              in 
                {exp=(Translate.letExp (!exps) body_exp), ty=let_ty}
              end

          | trexp (A.BreakExp pos) = (case breakpoint of
                                     NONE => ((ErrorMsg.error pos "break statment not allowed here"); 
                                     {exp=T.to_be_replaced, ty=Types.UNIT})
                                   | SOME bp_label => {exp=(Translate.breakExp bp_label), ty=Types.UNIT}
                                 )

          | trexp (A.RecordExp {fields, typ, pos}) = (
            case Symbol.look (tenv, typ) of
                SOME (Types.RECORD (record_typs, unique )) =>
                let
                    fun loop [] = []                        

                      | loop ((symbol, exp, pos)::rest) = (
                        case find_ty (symbol, record_typs) of
                            SOME ty => let val {exp = t_exp, ty=expty} = trexp exp
                                        in
                                            if (expty = ty ) then t_exp :: (loop rest)
                                            else ((ErrorMsg.error pos ("Type of record " ^ Symbol.name typ ^ " does not match" ));
                                                      [])
                                        end
                          | NONE => ((ErrorMsg.error pos (Symbol.name symbol ^ " not found in record: " ^ Symbol.name typ));
                                         [])
                    )
                    val t_exp_list = loop fields
                in
                    {exp = (Translate.recordInit level t_exp_list), ty = Types.RECORD (record_typs, unique)}
                end
              | _ => ((ErrorMsg.error pos ("No record of type " ^ Symbol.name typ ^ " found"));
                             {exp = T.to_be_replaced, ty=Types.NIL})
          )

          | trexp (A.ArrayExp {typ, size, init, pos}) = (
            case lookupActualType(pos, tenv, typ) of
                Types.ARRAY (arr_ty, _) => (
                 case trexp size of
                    {exp = size_exp, ty=Types.INT} =>
                              let val {exp = init_exp, ty = init_ty} = trexp init
                              in
                                  if (actual_ty init_ty = actual_ty arr_ty)
                                  then {exp= (Translate.initArray level size_exp init_exp), 
                                  ty=(Types.ARRAY (arr_ty, ref ()))}
                                  else ((ErrorMsg.error pos (Symbol.name typ ^ " does not match the type of initialization"));
                                            {exp=T.to_be_replaced, ty=Types.NIL})
                              end
                            | _ => (ErrorMsg.error pos "size should be always of integer type";
                                        {exp=T.to_be_replaced, ty = Types.NIL})
            )
              | _ => (ErrorMsg.error pos (Symbol.name typ ^ " should be of array type");
                                      {exp=T.to_be_replaced, ty=Types.NIL})
          )

          | trexp (A.AssignExp {var, exp, pos}) = 
              let
                  val {exp=t_exp1, ty=var_ty} = trvar var
                  val {exp=value, ty=exp_ty} = trexp exp
            in
                 if (var_ty = exp_ty) then {exp=(Translate.assignVar t_exp1 value), 
                                            ty = Types.UNIT} 
                                            else
                    ((ErrorMsg.error pos "type is assign statement does not match");
                        {exp=T.to_be_replaced, ty = Types.NIL})
            end

          | trexp (A.SeqExp exps) =
            let fun loop [] = {exp=T.to_be_replaced, ty = Types.UNIT}
                  | loop ((exp, _)::[]) = trexp exp
                  | loop ((exp, _)::exps) = ((trexp exp);
                                        loop exps )

                val {exp=exp', ty=ty'} = loop exps                                   
            in
                {exp=exp', ty=ty'}
            end

          | trexp  (A.CallExp {func, args, pos}) =
          (
              case Symbol.look (venv, func) of
                  SOME (Env.FunEntry {formals, result, level=func_level, label}) => 
                   let
                       fun check_type_param (formal::formals, arg::args) =
                           let 
                                val {exp=t_exp, ty=t'} = trexp arg
                           in 
                            (if not (actual_ty formal = actual_ty t') then
                                (ErrorMsg.error pos "type does not match")                                   
                                else ());
                                t_exp :: check_type_param (formals, args)
                           end
                         | check_type_param  ([], []) = []
                         | check_type_param (_, _) = (ErrorMsg.error pos (Symbol.name func ^ " length of parameters does not match the ones passed");
                          [])
                        
                        val t_exp_list = check_type_param (formals, args)
                      val call_exp = Translate.callExp label level func_level t_exp_list
                       in
                           {exp=call_exp, ty=result}
                       end
               |  _ => ((ErrorMsg.error pos (Symbol.name func ^ " not a function variable"));
                            {exp=T.to_be_replaced, ty=Types.NIL})
          )

          | trexp (A.IfExp {test, then', else'=SOME els_exp, pos}) =
            let
                val testA = trexp test
                val {exp = then_exp, ty = thenA} = trexp then'
                val {exp = else_exp, ty = elseA} = trexp els_exp
            in
                checkInt(testA, pos);
                check_type_equality(thenA, elseA, pos, "then and else should have same type");
                {exp=(Translate.ifElseExp (#exp testA) then_exp else_exp), ty = elseA}
            end

          | trexp (A.IfExp {test, then', else'= NONE, pos}) =
            let
                val testA = trexp test
                val thenA = trexp then'
            in
                checkInt(testA, pos);
                checkUnit(thenA, pos);
               {exp=(Translate.ifExp (#exp testA) (#exp thenA)) , ty = Types.UNIT}
            end

          | trexp (A.WhileExp {test, body, pos}) =
            let val test_ty = trexp test
                val done_label = Temp.newlabel()
                val body_ty = transExp (level, venv, tenv, body, SOME done_label)
            in
                checkInt (test_ty, pos);
                checkUnit (body_ty, pos);
                {exp=(Translate.whileLoop (#exp test_ty) (#exp body_ty) done_label), ty = Types.UNIT}
            end

        | trexp (A.ForExp {var, escape, lo, hi, body, pos}) = 
            let
                val limit_sym = Symbol.symbol "limit"
                val decs = [
                    Absyn.VarDec {name=var, escape=escape, typ=NONE, init=lo, pos=pos},
                    Absyn.VarDec {name=limit_sym, escape=escape, typ=NONE, init=hi, pos=pos}
                ]
                val exp_test = Absyn.OpExp{
                    left=Absyn.VarExp (Absyn.SimpleVar (var, pos)),
                    oper = Absyn.LeOp,
                    right= Absyn.VarExp (Absyn.SimpleVar (limit_sym, pos)),
                    pos=pos
                    }
                val whileExp = Absyn.WhileExp {test = exp_test, body=body, pos=pos}
                val letExp = Absyn.LetExp {decs = decs, body=whileExp, pos=pos}
            in
                trexp letExp
            end

        and trvar (A.SimpleVar (id, pos)) =
            (case Symbol.look(venv, id)
              of SOME(E.VarEntry{ty, access}) =>
                           let
                               val t_exp = Translate.simpleVar (access, level)
                           in
                               {exp=t_exp, ty = actual_ty ty}
                           end

               | _ => ((ErrorMsg.error pos ("undefined variable " ^ Symbol.name id));
                       {exp = T.to_be_replaced, ty=Types.NIL}))

          | trvar (A.SubscriptVar (var, exp, pos)) = (
            case (trvar var) of
                {exp=t_exp, ty = Types.ARRAY (var_ty, _)} => (
                        case (trexp exp) of
                            {exp = index, ty = Types.INT} => {exp = (Translate.subscript t_exp index),
                                                             ty=var_ty}
                            | _ => ((ErrorMsg.error pos "Array subscript type should be Integer");
                                                          {exp = T.to_be_replaced, ty = Types.NIL})
            )
                      | _ => ((ErrorMsg.error pos "Variable should be an array");
                                                          {exp = T.to_be_replaced, ty = Types.NIL})
          )

          | trvar (A.FieldVar (var, sym, pos)) = (
              case (trvar var) of
                  {exp = t_exp , ty = (Types.RECORD (sym_list, _))} =>
                            (case find_ty (sym, sym_list) of
                                 SOME rc_ty => let
                                                    val record_index = Translate.intExp level (find_record_index sym sym_list pos 0)
                                               in
                                                {exp = (Translate.subscript t_exp record_index), ty = rc_ty}
                                               end
                                | NONE => (ErrorMsg.error pos (Symbol.name sym ^ " not found in record");
                                            {exp = T.to_be_replaced, ty = Types.INT})
                            )
                          | _ => (ErrorMsg.error pos "Not a record type";
                                                 {exp = T.to_be_replaced, ty = Types.INT})
          )

    in
        trexp exp
    end

(* Absyn.dec *)
and transDecs (level, venv, tenv, dec::decs, exps, bp: Temp.label option) =
    let
        (* variables declarations *)

        fun transDec (venv, tenv, A.VarDec {name, typ=NONE, init, escape, pos}) =
            let val {exp, ty} = transExp(level, venv, tenv, init, bp)
                val access' = T.allocLocal level (!escape)
            in
                exps := (Translate.initVar access' level exp) :: (!exps);
                {tenv = tenv,
                venv = Symbol.enter (venv, name, Env.VarEntry {ty=ty, access=access'})
                }
            end

         (* TODO: some more changes are required -> if type failed to add or not *)

          | transDec (venv, tenv, A.VarDec {name, typ=SOME(sym_ty, sym_pos), pos, init, escape}) = (
            case Symbol.look (tenv, sym_ty) of
                SOME(res_ty) =>
                             let
                                 val {exp, ty} = transExp(level, venv, tenv, init, bp)
                                 val access' = T.allocLocal level (!escape)
                             in
                                check_type_equality(ty, res_ty, pos,
                                        ("result type of " ^ Symbol.name name ^ " and " ^ Symbol.name sym_ty ^ " does not match"));
                                exps := (Translate.initVar access' level exp) :: (!exps);
                                 {tenv = tenv,
                                  venv = Symbol.enter (venv, name, Env.VarEntry {ty=ty, access=access'})
                                 }
                             end
               | NONE => ((ErrorMsg.error sym_pos (Symbol.name sym_ty ^ " type not found"));
                {venv=venv, tenv=tenv})
          )

          | transDec (venv, tenv, A.TypeDec declars) =
            let
                fun cycle_check (pos, sym, SOME(Types.NAME (sym2, tyref))) =
                    if (sym2 = sym) then ((ErrorMsg.error pos ("Illegal cycle detected in type " ^ Symbol.name sym)); true)
                    else cycle_check (pos, sym, !tyref)

                  | cycle_check _ = false


                fun iterate_decs (venv, tenv) =
                    let
                        fun iterate_dec {name, ty, pos} =
                            let
                                fun look_type (tenv, name, pos) =
                                    case Symbol.look(tenv, name) of
                                        SOME ty => ty
                                      | NONE => ((ErrorMsg.error pos ("type variable not found " ^ Symbol.name name)); Types.NIL)

                                val Types.NAME(nameRef, typRef) = look_type (tenv, name, pos)
                                val replace_ty = case ty
                                                  of A.NameTy (sym, pos) =>
                                                               if not (cycle_check (pos,name, SOME(look_type(tenv,sym,pos)))) then
                                                               Types.NAME (sym, ref (SOME(look_type(tenv, sym, pos))))
                                                               else Types.NIL
                                                   | A.ArrayTy (sym, pos) =>
                                                               Types.ARRAY (look_type(tenv, sym, pos), ref ())
                                                   | A.RecordTy fields =>
                                                               Types.RECORD (map (fn ({name, escape, typ, pos}) =>
                                                                                               (name, look_type (tenv, typ, pos))) fields, ref())
                            in
                                typRef := SOME(replace_ty)
                            end
                    in
                        app iterate_dec declars
                    end
                fun initialize ({name, ty, pos}, tenv) = Symbol.enter (tenv, name, Types.NAME(name, ref NONE))
                val tenv' = foldr initialize tenv declars
            in
                iterate_decs (venv, tenv');
                {tenv=tenv', venv=venv}
            end

          | transDec (venv, tenv, A.FunctionDec fundecs) =
            let
                fun look_result_type (tenv, result) =
                    case result of
                        SOME (rt, pos) => (case Symbol.look(tenv, rt) of
                                               SOME ty => actual_ty ty
                                             | NONE => (ErrorMsg.error pos (Symbol.name rt ^ "Result type not found");
                                                        Types.UNIT)
                                          )
                      | NONE => Types.UNIT

                fun transparam tenv' {name, typ, pos, escape} =
                    case Symbol.look(tenv', typ) of
                        SOME t => {name=name, ty=t, escape=escape}
                      | NONE => ((ErrorMsg.error pos (Symbol.name typ ^ " type not found"));
                                 {name=name, ty=Types.NIL, escape=escape})

                fun updateBodys(venv, tenv, fun_levels) =
                    let
                        fun enter_local_vars (({name, ty, escape=_}, access'), venv') =
                                Symbol.enter (venv', name,
                                              Env.VarEntry {ty=ty, access=access'})

                        fun updateBody({name, params, body, pos, result}, fun_level) =
                            let 
                                val result_ty = look_result_type (tenv, result)
                                val params' = map (transparam tenv) params
                                val param_access = T.formals fun_level
                                val venv'' = foldl enter_local_vars venv (ListPair.zip (params', param_access))
                                val {exp=f_body_exp, ty=bodyty} = transExp (fun_level, venv'', tenv, body, bp)
                            in
                                Translate.procEntryExit {level=fun_level, body=f_body_exp};
                                (check_type_equality (result_ty, bodyty, pos, 
                                    (Symbol.name name ^ " function result type does not match return of expression")))
                            end
                    in
                        (app updateBody o ListPair.zip) (fundecs, fun_levels)
                    end
                (* initial function headers insertion -> {venv', tenv'}*)
                fun enterFunctionHeaders({name, params, body, pos, result}, {venv, tenv, levels}) =
                    let
                        val result_ty = look_result_type (tenv, result)
                        val params' = map (transparam tenv) params
                        val fun_label = Temp.newlabel()
                        val new_level = T.newLevel {parent=level, name=fun_label, formals= map (! o #escape) params'}
                        val venv' = Symbol.enter (venv, name, E.FunEntry {formals = map #ty params',
                                                                          result=result_ty, level=level, label=fun_label})
                        val levels' = new_level :: levels
                    in
                        {venv=venv', tenv=tenv, levels=levels'}
                    end
                val {venv=venv', tenv=tenv',levels=levels'} = foldl enterFunctionHeaders {venv=venv,tenv=tenv, levels=[]} fundecs
            in
                updateBodys(venv', tenv', (List.rev levels'));
                {venv=venv', tenv=tenv'}
            end

        val {venv=venv', tenv=tenv'} = transDec (venv, tenv, dec)
    in
        transDecs (level, venv', tenv', decs, exps, bp)
    end

  | transDecs  (_, venv, tenv, [], exps, _: Temp.label option) = {venv=venv, tenv=tenv}

(* Absyn.ty *)
and transTy (tenv, ty) =
    let
        fun trTy (A.NameTy (sym, pos)) = find_type (tenv, sym, pos)

          | trTy (A.RecordTy fields)  =
            let
                fun loop ({name, typ, pos, escape}::rest) =
                    (name, find_type (tenv, typ, pos)) :: loop rest
                  | loop [] = []
                val fields' = loop fields
            in
                Types.RECORD (fields', ref ())
            end

          | trTy  (A.ArrayTy (sym, pos)) = Types.ARRAY (find_type(tenv, sym, pos), ref ())
    in
        trTy ty
    end

and transProg exp =
    let
        (* first layer after outer *)
        val main_level = T.newLevel {parent=T.outermost, name=Symbol.symbol "main_level", formals=[]}
        val {exp=final_exp, ty=_} = transExp (main_level, Env.base_venv, Env.base_tenv, exp, NONE)
    in
        Translate.procEntryExit {level = main_level, body=final_exp};
        Translate.getResult()
    end

end
