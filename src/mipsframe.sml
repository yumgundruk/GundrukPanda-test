structure MipsFrame : FRAME = struct

structure T = Tree

val wordSize = 8
val FP = Temp.newtemp()
val RV = Temp.newtemp() (* return register *)
val SP = Temp.newtemp()
val RA = Temp.newtemp()

(* determines where the value will be stored -> register (temp) or memory (int) *)
datatype access = InFrame of int | InReg of Temp.temp
type register = string

(* label here is memory label which starts the location *)
type frame = { name: Temp.label,
               formals: (access * bool) list,
               locals: (access * bool) list ref,
               totalFormals : int ref,
               totalLocals : int ref
             }

datatype frag = PROC of {body : Tree.stm, frame: frame}
                    | STRING of Temp.label * string

val special_regs = [
  (FP, "$fp"),
  (RV, "$v0"),
  (SP, "$sp"),
  (RA, "$ra")
]                

fun entryenv ((id, data), env) =
    Temp.Table.enter (env, id , data)

fun make_many_temps times = 
  if times = 0 then []
  else Temp.newtemp() :: (make_many_temps (times - 1))    

val args_reg_list = make_many_temps 4

val final_regs = special_regs @ (ListPair.zip (args_reg_list, ["$a0", "$a1", "$a2", "$a3"]))

val calldefs = args_reg_list @ [RV, RA]


fun assignMem index = InFrame  (index * wordSize)(* TODO: Change later *)

fun assignReg() = InReg (Temp.newtemp())

fun assignMemOrReg index true = (assignMem index, true)
  | assignMemOrReg _ false = (assignReg(), false)

(* first four gets assigned register *)
val limit = 4

fun assignParam [] _ _= []

  | assignParam (true::formals) index count = 
  let
    val mem = assignMem (!index)
  in
    index := 1 + (!index);
    (mem, true)::(assignParam formals index count)
  end
  
  | assignParam (false::formals) index count =
      if count <= limit then
        (InReg (List.nth (args_reg_list, !index)), false)::(assignParam formals index (count+1))
      else
        let
          val newformals = map (fn _ => true) formals
        in
          assignParam newformals index count
        end


fun newFrame {name, formals}: frame = 
                      let
                        val formalNum = ref 0
                        val formals = (assignParam formals formalNum 0)
                      in
                                {name = name,
                                formals = formals,
                                locals = ref [],
                                totalFormals = formalNum,
                                totalLocals = ref 0
                                }
                      end


fun name {name=name, formals=_, locals=_ , totalFormals=_, totalLocals=_} = name

fun formals {name=_, formals=formals, locals=_,totalFormals=_, totalLocals=_} =
    (map (fn (access, _) => access) formals)

fun allocLocal {name = _, formals=_, locals, totalFormals=_, totalLocals=localnum} isescape =
    let
        val new_access = assignMemOrReg (~(!localnum)) isescape
        val (access, _) = new_access
    in
        locals := new_access :: !locals;
        localnum := 1 + (!localnum);
        access
    end

fun exp (InFrame c) (fp: T.exp) =
    T.MEM(T.BINOP (T.PLUS, fp, T.CONST c))

  |  exp (InReg reg) (_: T.exp) = T.TEMP reg


fun externalCall (name: string) (args : Tree.exp list) = 
  T.CALL (T.NAME (Temp.namedlabel name), args)

fun procEntryExit1 (c_frame, t_stm) = t_stm (* implement view shift later *)

end
