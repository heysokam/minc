#:______________________________________________________
#  ᛟ minc  |  Copyright (C) Ivan Mar (sOkam!)  |  MIT  :
#:______________________________________________________
# @deps ndk
import nstd/strings
import nstd/paths
from nstd/sets import hasAll, hasAny
# @deps *Slate
import slate/nimc as nim
import slate/format
import slate/elements
import slate/element/extras
import slate/errors as slateErr
import slate/types as slate
# @deps minc
import ../cfg
import ../errors
import ../types as minc
import ../tools


#_______________________________________
# @section MinC+Slate Node Access
#_____________________________
const Renames_Calls :RenameList= @[
  ("addr", "&")
  ] # << Renames_Calls [ ... ]
#___________________
const Renames_ConditionPrefix :RenameList= @[
  ("not", "!"),
  ] # << Renames_ConditionPrefix [ ... ]
#___________________
const Renames_ConditionAffix :RenameList= @[
  ("shl", "<<"),  ("shr", ">>"),
  ("and", "&&"),  ("or" , "||"),  ("xor", "^"),
  ("mod", "%" ),  ("div", "/" ),
  ] # << Renames_ConditionAffix [ ... ]
const Renames_AssignmentAffix :RenameList= @[
  ("shl", "<<"),  ("shr", ">>"),
  ("and", "&" ),  ("or" , "|" ),  ("xor", "^" ),
  ("mod", "%" ),  ("div", "/" ),
  ] # << Renames_AssignmentAffix [ ... ]
#___________________
func renamed (
    name    : string;
    kind    : TNodeKind;
    special : SpecialContext = Context.None;
  ) :string=
  let list =
    case kind
    of nkCommand, nkCall             : Renames_Calls
    of nkPrefix                      : Renames_ConditionPrefix
    of nkInfix                       :
      if   Condition in special      : Renames_ConditionAffix
      elif Context.Return in special : Renames_ConditionAffix
      elif Variable in special       : Renames_AssignmentAffix
      elif Assign in special         : Renames_AssignmentAffix
      else                           : @[]
    else                             : @[]
  for rename in list:
    if name == rename.og: return rename.to
  result = name
#___________________
template `.:`*(code :PNode; prop :untyped) :string=
  let field = astToStr(prop)
  case code.kind
  of nkStmtList:
    var id = int.high
    try : id = field.parseInt
    except NodeAccessError: code.err "MinC: Tried to access a Statement List, but the keyword passed was not a number:  "&field
    strValue( statement.get(code, id) )
  of nkProcDef:
    var id       = int.high
    var property = field
    if "arg_" in field:
      property = field.split("_")[0]
      try : id = field.split("_")[1].parseInt
      except NodeAccessError: code.err "MinC: Tried to access an Argument ID for a nkProcDef, but the keyword passed has an incorrect format:  "&field
    let prop = procs.get(code, property, id)
    case prop.kind
    of nkPtrTy : strValue( prop[0] ) & "*"
    else       : strValue( prop )
  of nkConstDef, nkIdentDefs:
    let typ = vars.get(code, field)
    case typ.kind
    of nkCommand,nkPtrTy:
      var tmp :string
      for field in typ: tmp.add strValue( field ) & " "
      if typ.isPtr: tmp = tmp.strip & "*"
      tmp
    else: strValue( typ )
  of nkPragma:
    strValue( pragmas.get(code, field) )
  of nkCommand, nkCall:
    var id       = int.high
    var property = field
    if "arg_" in field:
      property = field.split("_")[0]
      try : id = field.split("_")[1].parseInt
      except NodeAccessError: code.err "MinC: Tried to access an Argument ID for a Call, but the keyword passed has an incorrect format:  "&field
    strValue( calls.get(code, property, id) ).renamed(code.kind)
  of nkTypeDef:
    strValue( types.get(code, field) )
  of nkPrefix:
    strValue( affixes.getPrefix(code, field) )
  of nkInfix:
    strValue( affixes.getInfix(code, field) )
  else: code.err "MinC: Tried to access a field for an unmapped Node kind: " & $code.kind & "." & field; ""


#_______________________________________
# @section Forward Declares
#_____________________________
const RawSpecials = {Variable, Argument, Assign, Condition, Return}
proc MinC *(code :PNode; indent :int= 0; special :SpecialContext= Context.None) :CFilePair
proc mincLiteral   (code :PNode; indent :int= 0; special :SpecialContext= Context.None) :CFilePair
proc mincObjConstr (code :PNode; indent :int= 0; special :SpecialContext= Context.None) :CFilePair

#_______________________________________
# @section Array tools
#_____________________________
proc mincArrSize (
    code      : PNode;
    indent    : int            = 0;
    special   : SpecialContext = Context.None;
  ) :string=
  ## @descr Returns the array size defined by {@arg code}
  const (Type,ArraySize) = (1,1)
  let typ =
    if   code.kind == nkIdent       : code
    elif code.kind == nkBracketExpr : code
    elif code.kind == nkIdentDefs   : code[Type]
    else                            : code.getType()
  if   typ.kind in {nkIdent}+nim.Literals : result = typ.strValue
  elif typ.kind == nkBracketExpr          : result = typ[ArraySize].strValue
  elif typ.kind == nkInfix                : result = MinC(typ, indent, special).c
  else: code.err &"Tried to access the array size of an unmapped kind:  {typ.kind}" # TODO: Better infix resolution
  # Correct the `_` empty array size case
  if result == "_": result = ""
#_____________________________
const ArrSuffixTempl = "[{size}]"
proc mincArraySuffix (
    code      : PNode;
    indent    : int            = 0;
    special   : SpecialContext = Context.None;
  ) :string=
  let isArr = code.isArr
  if not isArr: return
  let size = mincArrSize(code, indent, special)
  result = fmt ArrSuffixTempl
#_____________________________
proc mincArrayType (
    code      : PNode;
    indent    : int            = 0;
    special   : SpecialContext = Context.None;
  ) :string=
  let isArr = code.isArr
  if not isArr: return
  const Type = ^1
  result = MinC(code[Type], indent, special).c


#_______________________________________
# @section Control Flow: Keywords
#_____________________________
const ReturnTempl = "{indent*Tab}return{body};"
proc mincReturnStmt (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Kind.Return
  if indent < 1: code.trigger FlowCtrlError, "Return statements cannot exist at the top level in C."
  # Generate the Body
  var body :string
  if code.sons.len > 0: body.add " "  # Separate `return` and `body` with a space when there is a value
  for entry in code: body.add MinC(entry, indent+1, special.with Context.Return).c # TODO: Could Header stuff happen inside a body ??
  # Generate the result
  result.c = fmt ReturnTempl
#___________________
proc mincContinueStmt (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Continue
  if indent < 1: code.trigger FlowCtrlError, "Continue statements cannot exist at the top level in C."
  result.c = &"{indent*Tab}continue;\n"
#___________________
proc mincBreakStmt (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Break
  if indent < 1: code.trigger FlowCtrlError, "Break statements cannot exist at the top level in C."
  result.c = &"{indent*Tab}break;\n"


#_______________________________________
# @section Control Flow: Loops
#_____________________________
const WhileTempl = "{indent*Tab}while ({cond}) {{\n{body}{indent*Tab}}}\n"
proc mincWhile (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, nkWhileStmt
  const (Condition,Body) = (0,1)
  let cond = MinC(code[Condition], indent, Context.Condition).c
  let body = MinC(code[Body], indent+1, special).c
  result.c = fmt WhileTempl
#___________________
func isIncr *(value,infix,final :string) :bool= true  # TODO : Remove hardcoded ++. How to know if we increment or decrement?
#___________________
const ForSentryTempl = "size_t {sentry} = {value}"  # TODO: Remove hardcoded size_t. Should be coming from code[Exprs][Value].T
const ForCondTempl   = " {sentry} {infix} {final}"
const ForIterTempl   = " {prefix}{sentry}"
const ForTempl       = "{indent*Tab}for ({init};{cond};{iter}) {{\n{body}{indent*Tab}}}\n"
proc mincFor (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, nkForStmt
  const (Sentry,Exprs,Body) = (0,1,2)  # Root for loop items
  const (Infix,Value,Final) = (0,1,2)  # Expression items at code[Exprs]
  # Get the sentry initializer
  let sentry = MinC(code[Sentry], indent, special.with Variable).c
  let value  = MinC(code[Exprs][Value], indent, special.with Variable).c
  # Get the incrementer/finalizer
  let infix  = MinC(code[Exprs][Infix], indent, special.with ForLoop).c.otherwise("<=")
  let final  = MinC(code[Exprs][Final], indent, special.with Variable).c
  let prefix = if value.isIncr(infix,final): "++" else: "--"
  # Error check
  if value  == "": code.trigger FlowCtrlError, "The starting value of a for loop was empty."
  if sentry == "": code.trigger FlowCtrlError, "The sentry variable of a for loop was empty."
  if infix  == "": code.trigger FlowCtrlError, "The infix of a for loop was empty."
  if final  == "": code.trigger FlowCtrlError, "The final value of a for loop was empty."
  if prefix == "": code.trigger FlowCtrlError, "The prefix of a for loop was empty."
  # Generate the code
  let init = fmt ForSentryTempl
  let cond = fmt ForCondTempl
  let iter = fmt ForIterTempl
  let body = MinC(code[Body], indent+1, special).c
  result.c = fmt ForTempl


#_______________________________________
# @section Control Flow: Conditionals
#_____________________________
const IfTempl = "{elseStr}{ifStr}{cond} {{\n{body}\n{indent*Tab}}}"
const TernaryRawTempl = "({cond}) ? {case1} : {case2}"
proc mincIf (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, nkIfStmt, nkIfExpr, "Tried to generate the code for an `if/elif/else` block with an incorrect node."
  if code.kind == nkIfExpr:  # if Expressions always become ternary expressions
    if code.len != 2: code.trigger ConditionError, "Support for elif branches in if `expr` is not implemented yet"
    const (Condition,IfCase,ElseCase,Body) = (0,0,^1,^1)
    let cond  = MinC(code[IfCase][Condition], indent, Context.Condition).c.wrappedIn("(",")")
    let case1 = MinC(code[IfCase][Body], indent, Context.Condition).c
    let case2 = MinC(code[ElseCase][Body], indent, Context.Condition).c
    result.c = fmt TernaryRawTempl
    return
  elif Variable in special:  # nkIfStmt for variables become ternary expressions
    const (Condition,Case1,Case2) = (0,1,^1)
    let cond  = MinC(code[Condition], indent, Context.Condition).c.wrappedIn("(",")")
    let case1 = MinC(code[Case1], indent, Context.Condition).c
    let case2 = MinC(code[Case2], indent, Context.Condition).c
    result.c = fmt TernaryRawTempl
    return
  for id,branch in code.pairs:
    const (Condition,Body,ElseBody) = (0,1,0)
    let first   = id == 0
    let isElse  = branch.kind == nkElse
    let last    = id == code.sons.high
    let cond    = if isElse: "" else: MinC(branch[Condition], indent, Context.Condition).c.wrappedIn("(",")")
    let body    =
      if isElse : MinC(branch[ElseBody], indent+1, special).c
      else      : MinC(branch[Body], indent+1, special).c
    let elseStr = if first: indent*Tab else: " else "  # elif or else
    let ifStr   = if not isElse: "if "  else: ""       # if or elif
    result.c.add fmt IfTempl
    if last: result.c.add "\n"
#___________________
const WhenTempl    = "{tab}{pfx}{cond}\n{tab}{body}"
const WhenEndTempl = "{tab}#endif\n"
proc mincWhen (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  # TODO: Support for when cases in .h files
  ensure code, nkWhenStmt
  let extra   = {Context.Condition, Context.When}
  let special = (special.without Context.None) + extra
  let tab = indent*Tab
  for id,branch in code.pairs:
    const (Condition,Body) = (0,^1)
    # Get the macro prefix
    var pfx  :string
    var cond :string
    case branch.kind
    of nkElifBranch:
      if id == 0 : pfx = "#if "
      else       : pfx = "#elif "
      cond = MinC(branch[Condition], indent, special).c
    of nkElse    :
      pfx = "#else"
      # Don't get the condition. Else statements don't have any
    else: code.trigger ConditionError, "Unknown branch kind in mincWhen"
    let body = MinC(branch[Body], indent+1, special.without Context.Condition).c
    result.c.add fmt WhenTempl
  result.c.add fmt WhenEndTempl


#_______________________________________
# @section Modules
#_____________________________
proc getModule *(code :PNode) :Module=
  ensure code, Kind.Module # TODO: Support for Import
  const Module = 0
  let module = code[Module]
  ensure module, nkStrLit, nkInfix, nkDotExpr, nkIdent, &"Tried to get the module of a {code.kind} from an unsupported field kind:  {module.kind}"
  var line :string
  if   code.kind == nkIncludeStmt : line = "include "
  elif code.kind == nkImportStmt  : line = "import "
  else: code.err "Only include/import statements are supported for getModule."
  line.add module.renderTree.splitLines.join(" ").replace(" / ", "/")
  result = tools.getModule( line )
#___________________
const IncludeTempl = "#include {module}\n"
proc mincInclude (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Kind.Module, Kind.Ident, &"Tried to get the include of an unsupported kind:  {code.kind}"
  if indent > 0: code.err "include statements are only allowed at the top level."
  let M = code.getModule()
  let module =
    if M.local : M.path.string.wrapped
    else       : "<" & M.path.string & ">"
  if M.path.endsWith(".c") : result.c = fmt IncludeTempl  # Include .c files into other .c files, and not into the header
  else                     : result.h = fmt IncludeTempl


#_______________________________________
# @section Procedures
#_____________________________
const KnownMainNames = ["main", "WinMain"]
proc mincProcPragmas (code :PNode; indent :int= 0) :string=
  let pragmas = procs.get(code, "pragmas")
  for prag in pragmas:
    let name = MinC(prag, 0).c
    if   name == "noreturn"     : result.add "[[noreturn]] "
    elif name == "noreturn_C11" : result.add "_Noreturn "
    elif name == "noreturn_GNU" : result.add "__attribute__((noreturn)) "
    elif name == "inline"       : result.add "extern " & name & " "
    else: code.trigger PragmaError, "proc pragmas error: Only {.noreturn.}, {.noreturn_C11.}, {.noreturn_GNU.}, {.inline.} are currently supported."
#___________________
proc mincProcQualifiers (code :PNode; indent :int= 0) :string=
  let name = code.:name
  result = mincProcPragmas(code, indent)
  if not code.isPublic and name notin KnownMainNames: result.add "static "
#___________________
const ArgTempl = "{typ} {name}"
proc mincProcArgs (code :PNode; indent :int= 0) :string=
  # TODO: {.readonly.} pragma
  # ref :  fmt "{ronly}{typ}{mut} {arg.name}{arr}{sep}"
  ensure code, nkFormalParams
  if code.sons.len == 0: return "void"  # Explicit fill with void for no arguments
  # Add all arguments to the result
  var args :seq[tuple[name:string, typ:string, val:string, special:SpecialContext]]
  for group in code:
    const (Type,Value,LastArg) = (^2,^1,^3)
    var special = {Argument, Immutable}                     # const by default
    if group[Type].kind == nkVarTy: special.excl Immutable  # Remove Immutable for `var T`
    let typ     = MinC(group[Type], indent+1, special).c
    let val     = MinC(group[Value], indent+1, special).c
    for id,arg in group.sons[0..LastArg].pairs:
      args.add (
        name    : MinC(arg, indent+1, special).c,
        typ     : typ,
        val     : val,  # TODO: Default values
        special : special,
        ) # << args.add ( ... )
      args[id].name.add mincArraySuffix(group[Type], indent, special)
  for id,arg in args.pairs:
    let typ  = if Immutable in arg.special: arg.typ & " const" else: arg.typ
    let name = arg.name
    result.add fmt ArgTempl
    if id != args.high: result.add SeparatorArgs
#___________________
const ProcProtoTempl = "{qual}{T} {name} ({args});\n"
const ProcDefTempl   = "{qual}{T} {name} ({args}) {{\n{body}\n}}\n"
proc mincProcDef (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Proc
  let name = code.:name
  let qual = mincProcQualifiers(code, indent)
  let T    = code.:returnT
  let args = mincProcArgs(procs.get(code, "args"), indent)
  let body = MinC(procs.get(code,"body"), indent+1).c # TODO: Could Header stuff happen inside a body ??
  # Generate the result
  result.h =
    if code.isPublic and name notin KnownMainNames : fmt ProcProtoTempl
    else: ""
  result.c = fmt ProcDefTempl
#_____________________________
proc mincFuncDef (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  # __attribute__ ((pure))
  # write-only memory idea from herose (like GPU write-only mem)
  ensure code, Func
  mincProcDef(code, indent, special)
  # code.trigger ProcError, "proc and func are identical in C"  # TODO : Sideffects checks


#_______________________________________
# @section Calls & Commands
#_____________________________
const CallAddrTempl = "{name}{args}"
const CallRawTempl  = "{name}({args})"
const CallTempl     = "{indent*Tab}{call};\n"
proc mincCall (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  # TODO: Union special case
  # TODO: &(StructType){...} special case
  # TODO: StructType(_) special case
  ensure code, Call
  if code.kind == nkCallStrLit: return mincLiteral(code, indent, special)
  # Get the name
  let name = code.:name
  # Get the args code
  var args :string
  let code_args = calls.get(code, "args")
  for id,arg in code_args.pairs:
    args.add MinC(arg, indent+1, special.with Argument).c
    if id != code_args.sons.high: args.add SeparatorArgs
  # Apply to the result
  let call =
    case name
    of "&": fmt CallAddrTempl
    else:   fmt CallRawTempl
  result.c =
    if special == {Context.None} : fmt CallTempl  # Format it by default
    else                         : call           # Leave it unchanged for special cases
#_____________________________
proc mincCommand (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Call
  mincCall(code, indent, special)  # Command and Call are identical in C


#_______________________________________
# @section Variables
#_____________________________
const VarDeclTempl = "{indent*Tab}extern {qual}{T} {name};\n"
const VarDefTempl  = "{indent*Tab}{qual}{T} {name}{eq}{value};\n"
#___________________
proc mincVariable (
    code    : PNode;
    indent  : int;
    kind    : Kind;
    special : SpecialContext= Context.None;
  ) :CFilePair=
  # Error check
  ensure code, Const, Let, Var, msg="Tried to generate code for a variable, but its kind is incorrect"
  let special = special.with Context.Variable
  let typ  = vars.get(code, "type")
  let body = vars.get(code, "body")
  if typ.kind == nkEmpty: code.trigger VariableError,
    &"Declaring a variable without a type is forbidden."
  if kind == Const and body.kind == nkEmpty: code.trigger VariableError,
    &"Declaring a variable without a value is forbidden for `const`."
  # Get the qualifier
  var qual :string
  if code.isPersist(indent) or (indent < 1 and not code.isPublic) : qual.add "static "
  if kind == Const: qual.add "/*constexpr*/ "  # TODO: clang.19
  # Get the type
  var T = code.:type
  if T == "pointer": T = PtrValue # Rename `pointer` to `void*`  ## TODO: configurable based on c23 option
  if not code.isMutable(kind): T.add " const"
  # TODO: {.readonly.} variable without explicit typedef
  # Get the Name
  var name = code.:name
  # Name: Array special case extras
  const Type = 1
  name.add mincArraySuffix(code[Type], indent, special)
  # Get the body (aka variable value)
  let value = MinC(body, indent+1, special).c
  let eq    = if value != "": " = " else: ""
  # Generate the result
  result.h =
    if code.isPublic and indent == 0 : fmt VarDeclTempl
    else:""
  result.c = fmt VarDefTempl
#___________________
proc mincConstSection (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Const
  for entry in code.sons: result.add mincVariable(entry, indent, Kind.Const, special)
#___________________
proc mincLetSection (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Let
  for entry in code.sons: result.add mincVariable(entry, indent, Kind.Let, special)
#___________________
proc mincVarSection (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Var
  for entry in code.sons: result.add mincVariable(entry, indent, Kind.Var, special)
#___________________
const AsgnRawTempl = "{left} = {right}"
const AsgnTempl    = "{indent*Tab}"&AsgnRawTempl&";\n"
proc mincAsgn (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Asgn
  const (Left, Right) = (0,1)
  let specl = special.with Assign
  let left  = MinC(code[Left], indent, specl).c
  let right = MinC(code[Right], indent, specl).c
  result.c  =
    if Context.None in special : fmt AsgnTempl
    else                       : fmt AsgnRawTempl
#___________________
const DerefTempl     = "*{name}"
const ArrAccessTempl = "{name}[{inner}]"
proc mincBracketExpr (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, nkBracketExpr
  if code.isArrAccess:
    const (Type,) = (1,)
    let name  = MinC(code.getName(), indent, special).c
    let inner = MinC(code[Type], indent, special).c
    result.c  = fmt ArrAccessTempl
  elif code.isArr:
    if special.hasAny {Argument}:
      result.c = mincArrayType(code, indent, special)
    else: code.trigger AssignError, &"Found a SpecialContext for arrays that hasn't been mapped yet:  {special}"
  elif special.hasAny {Assign, Variable, Return, Argument}:
    let name = MinC(code.getName(), indent, special).c
    result.c = fmt DerefTempl
  else: code.trigger AssignError, &"Found a SpecialContext that hasn't been mapped yet:  {special}"
#___________________
const ObjConstrTempl       = "({typ}){{{args}}}"
const ObjConstrFieldTempl  = ".{name}= {body}"
const ObjConstrIndentTempl = "\n{(indent+1)*Tab}"
proc mincObjConstr (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ## @descr Designated Initialization for Objects with syntax:  SomeType(field1: val1, field2: val2)
  ensure code, nkObjConstr, nkCall, "Tried to codegen a Designated Initializer for an object from an incorrect node type"
  # Redirection case
  if code.kind == nkCall: code.trigger ObjectError, "Object construction from Call(...) syntax is not implemented yet"
  # Object Construction Case
  const (Type,) = (0,)
  let typ = MinC(code[Type], indent, special).c
  var args :string
  let argCount = code.sons.high - 1
  for field in 1..argCount+1:  # For every field, skipping entry0 (the type)
    if argCount > 1: args.add fmt ObjConstrIndentTempl
    const (Body,) = (1,)
    let name = MinC(code[field].getName(), indent, special).c
    let body = MinC(code[field][Body], indent, special).c
    args.add fmt ObjConstrFieldTempl
    if field != argCount+1 : args.add SeparatorObj              # Skip adding , for the last one
    elif argCount > 1      : args.add fmt ObjConstrIndentTempl  # Add an indent before the final bracket when there is more than 1 field
  result.c = fmt ObjConstrTempl


#_______________________________________
# @section Literals
#_____________________________
proc mincNil (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Nil
  result.c = NilValue
#___________________
proc mincChar (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Char
  result.c = &"'{code.strValue}'"
#___________________
proc mincFloat (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Float
  result.c = $code.floatVal
  case code.kind
  of nkFloat32Lit  : result.c.add "f"
  of nkFloat128Lit : result.c.add "L"
  else: discard
#___________________
proc mincInt (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Int
  result.c = $code.intVal
#___________________
proc mincUInt (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, UInt
  result.c = $code.intVal
#___________________
const StrKinds = nim.Str+{nkCallStrLit}
const ValidRawStrPrefixes = ["raw"]
proc isCustomTripleStrLitRaw (code :PNode) :bool= (code.kind in {nkCallStrLit} and code[0].strValue in ValidRawStrPrefixes and code[1].kind == nkTripleStrLit)
proc isTripleStrLit (code :PNode) :bool=  code.kind == nkTripleStrLit or code.isCustomTripleStrLitRaw
proc getTripleStrLit (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :string=
  ensure code, StrKinds, "Called getTripleStrLit with an incorrect node kind."
  let tab  = indent*Tab
  let val  = if code.kind == nkTripleStrLit: code else: code[1]
  var body = val.strValue
  let multiline = "\n" in body
  if code.isCustomTripleStrLitRaw : body = body.replace( "\n" , &"\"\n{tab}\""  )   # turn every \n character into  \n"\nTAB"  to use C's "" concatenation
  else                            : body = body.replace( "\n" , &"\\n\"\n{tab}\"" ) # turn every \n character into \\n"\nTAB"  to use C's "" concatenation
  if multiline: result.add &"\n{tab}"
  result.add &"\"{body}\""
  result = result.replace( &"\n{tab}\"\"", "" ) # Remove empty lines  (eg: the last empty line)
#___________________
proc mincStr (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, StrKinds, "Called mincStr with an incorrect node kind."
  if Context.When in special : result.c = code.strValue
  elif code.isTripleStrLit   : result.c = code.getTripleStrLit(indent, special)
  else                       : result.c = &"\"{code.strValue}\""
#___________________
proc mincLiteral (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Literal, RawStr, "Called mincLiteral with an incorrect node kind."
  case code.kind
  of nim.Nil   : result = mincNil(code, indent, special)
  of nim.Char  : result = mincChar(code, indent, special)
  of nim.Float : result = mincFloat(code, indent, special)
  of nim.Int   : result = mincInt(code, indent, special)
  of nim.UInt  : result = mincUInt(code, indent, special)
  of StrKinds  : result = mincStr(code, indent, special)
  else: code.trigger LiteralError, &"Found an unmapped Literal kind:  {code.kind}"
#___________________
proc mincIdent (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, nkIdent
  let val =
    if code.strValue == "pointer" : PtrValue # Rename `pointer` to `void*`  ## TODO: configurable based on c23 option
    else                          : code.strValue
  if Variable in special:
    result.c =
      if val == "_" : "{0}"  # TODO: Probably incorrect for the Object SpecialContext
      else          : val
  elif special.hasAll({ Argument, Readonly }) or
       special.hasAll({ Context.Typedef, Readonly }):
    result.c = &"{val} const"
  elif special.hasAny {Context.None, Argument, Condition, Typedef, Assign, Return, ForLoop}:
    result.c = val
    if ForLoop in special and result.c.startsWith(".."):
      result.c = result.c[2..^1] # Remove .. from ForLoop infixes
  else: code.trigger IdentError, &"Found an unmapped SpecialContext kind for interpreting Ident code:  {special}"
#___________________
const ParTempl = "({body})"
proc mincPar (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, nkPar
  const Body = 0
  let body = MinC(code[Body], indent, special).c
  result.c = fmt ParTempl
#___________________
proc mincBracket (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  if Variable in special:
    result.c.add "{ "
    for id,value in code.sons.pairs:
      result.c.add &"\n{indent*Tab}[{id}]= "
      result.c.add MinC(value, indent+1, special).c
      result.c.add if id != code.sons.high: "," else: "\n"
    result.c.add &"{indent*Tab}}}"
  else: code.trigger BracketError, &"Found an unmapped SpecialContext kind for interpreting Bracket code:  {special}"
#___________________
const CastTempl = "({typ})({body})"
proc mincCast (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, nkCast
  const (Type,Body) = (0,1)
  let typ  = MinC(code[Type], indent+1, special).c
  let body = MinC(code[Body], indent+1, special).c
  result.c = fmt CastTempl
#___________________
const DotTempl = "{left}.{right}"
proc mincDot (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, nkDotExpr
  const (Left,Right) = (0,1)
  let left  = MinC(code[Left], indent, special).c
  let right = MinC(code[Right], indent, special).c
  result.c = fmt DotTempl


#_______________________________________
# @section Types
#_____________________________
const ObjBodyTempl  = "struct {name} {{{bfr}{body}{spc}}}" # After-name is added by the typedef already
const ObjFieldTempl = "{typ} {name};"
proc mincType_obj (
    code      : PNode;
    indent    : int            = 0;
    special   : SpecialContext = Context.None;
    extraName : PNode          = nil;
  ) :CFilePair=
  ensure code, nkObjectTy
  const (Fields,Inherit) = (^1,1)
  let fieldCount = code[Fields].sons.len
  discard Inherit # TODO: object of T
  let name = MinC(extraName, indent, special).c
  let spc  = if fieldCount > 1: fmt "\n{indent*Tab}" else: " "
  let bfr  = if fieldCount > 1: "\n" else: " "
  var body :string
  for id,entry in code[Fields].pairs:
    let specl = special.with ObjectField
    let name  = MinC(entry.getName(), indent, specl).c
    let typ   = MinC(entry.getType(), indent, specl).c
    if fieldCount > 1: body.add indent*Tab
    body.add fmt ObjFieldTempl
    if id != code[Fields].sons.high: body.add "\n"  # Skip adding \n for the last field
  result.c = fmt ObjBodyTempl
#___________________
const PointerTempl = "{typ}*"
proc mincType_ptr (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, nkPtrTy
  const Type = 0
  let typ = MinC(code[Type], indent, special).c
  result.c = fmt PointerTempl
#___________________
proc mincType (
    code      : PNode;
    indent    : int            = 0;
    special   : SpecialContext = Context.None;
    extraName : PNode          = nil;
  ) :CFilePair=
  case code.kind
  of nkIdent : return MinC(code, indent, special)
  else       : discard
  ensure code, Type
  let special = if code.kind == nkVarTy: special.without Immutable else: special
  case code.kind
  of nkVarTy    : result = MinC(code[0], indent+1, special)
  of nkPtrTy    : result = mincType_ptr(code, indent+1, special)
  of nkObjectTy : result = mincType_obj(code, indent+1, special, extraName)
  else: code.trigger TypeError, &"Found an unmapped kind for interpreting Type code:  {code.kind}"
#___________________
const TypedefTempl = "typedef {typ} {name};\n"
proc mincTypeDef (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Kind.TypeDef
  var specl = {Context.Typedef}
  let pragm = types.get(code, "pragma").renderTree
  if "readonly" in pragm: specl.incl Readonly
  let name  = code.:name
  let codeT = types.get(code, "type")
  let typ   = mincType(
    code      = codeT,
    indent    = indent,
    special   = specl,
    extraName = if codeT.kind == nkObjectTy: types.get(code, "name") else: nil,
    ).c # << mincType( ... )
  result.h = fmt TypedefTempl


#_______________________________________
# @section Pragmas
#_____________________________
proc mincPragmaWarning (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ## @descr Codegen for {.warning: "msg".} pragmas
  ensure code, Pragma
  let body = pragmas.get(code, "body")
  ensure body, Str, &"Only {{.warning: [[SomeString]].}} warning pragmas are currently supported."
  let msg = mincStr(body, indent, special).c
  result.c = &"{indent*Tab}#warning {msg}\n"
#___________________
proc mincPragmaError (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ## @descr Codegen for {.error: "msg".} pragmas
  ensure code, Pragma
  let body = pragmas.get(code, "body")
  ensure body, Str, &"Only {{.error: [[SomeString]].}} error pragmas are currently supported."
  let msg = mincStr(body, indent, special).c
  result.c = &"{indent*Tab}#error {msg}\n"
#___________________
proc mincPragmaEmit (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ## @descr Codegen for {.emit: "source.code".} pragmas
  ensure code, Pragma
  let body = pragmas.get(code, "body")
  ensure body, Str, &"Only {{.emit: [[SomeString]].}} emit pragmas are currently supported."
  result.c = &"{indent*Tab}{body.strValue}\n"
#___________________
proc mincPragmaNamespace (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ## @descr Codegen for {.namespace: some.sub.name.} pragmas
  # TODO: Symbol namespacing using a `Context` object
  # TODO: Name separation without hard-replacing `.` with `_`
  ensure code, Pragma
  let name = pragmas.get(code, "name")
  let body = pragmas.get(code, "body")
  ensure name, nkIdent, nkDotExpr, &"Only {{.namespace:name.}} and {{.namespace:name.sub.}} namespace pragmas are currently supported."
  let ns_name = body.renderTree.replace(".", "_")
  result.c = &"{indent*Tab}// namespace {ns_name}\n"
  # if "_" in ns_name: result.c.add "\n"
#___________________
const ValidDefineAsignSymbols = ["->"]
const DefineTempl = "{indent*Tab}#define {name}{value}\n"
proc mincPragmaDefine (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ## @descr Codegen for {.define: ... .} pragmas
  const (Value,AssignSymbol,AssignValue, InfixName,InfixSymbol,InfixValue) = (1,0,1, 1,0,2)
  ensure code, Pragma
  let body = pragmas.get(code, "body")
  # Get the name
  var name :string
  case body.kind
  of nkIdent : name = body.strValue
  of nkInfix : name = body[InfixName].strValue
  else:
    code.trigger PragmaError, "Define[name] error: Only {.define:name.} and {.define: name[sym]value.} pragmas are currently supported."
  # Get the value
  var value :string
  # └─ Empty space between the name and the value when there is a value
  if code.len > 1 or body.kind == nkInfix:
    value.add " "
  # └─ Value for the {.define: name[sym]value.} when the value is not part of the body
  if code.len == 2:
    if code[Value].kind == nkPrefix and code[Value][AssignSymbol].strValue in ValidDefineAsignSymbols:
      value.add code[Value][AssignValue].strValue
  # └─ Value for the {.define: name[sym]value.} when the value is part of the body
  elif code.len == 1 and body.kind == nkInfix:
    if body[InfixSymbol].strValue in ValidDefineAsignSymbols:
      value.add body[InfixValue].strValue
    else: code.trigger PragmaError, &"Define[sym] error: Unsupported symbol for {{.define: name[sym]value.}}. Currently suppported list:  {ValidDefineAsignSymbols}"
  # └─ Value is empty when there is only {.define: name.}
  elif code.len == 1: value = ""
  else:
    code.trigger PragmaError, "Define[value] error: Only {.define:name.} and {.define: name[sym]value.} pragmas are currently supported."
  # Assign to the result
  result.c = fmt DefineTempl  # TODO: Should go to the header instead
#___________________
const PragmaOnceTempl = "{indent*Tab}#pragma once"
proc mincPragmaOnce (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Pragma
  result.h = fmt PragmaOnceTempl
#___________________
const KnownCPragmas = ["once"]
proc mincPragmaCPragma (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Pragma
  case code.:body
  of "once": result = mincPragmaOnce(code, indent, special)
  else: code.trigger PragmaError, &"Only {KnownCPragmas} pragmas are currently supported for {{.pragma: [name].}} ."
#___________________
const KnownPragmas = ["define", "error", "warning", "namespace", "emit", "pragma"]
proc mincPragma (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ## @descr
  ##  Codegen for all standalone pragmas
  ##  Context-specific pragmas are handled inside each section
  ensure code, Pragma
  case code.:name
  of "error"     : result = mincPragmaError(code, indent, special)
  of "warning"   : result = mincPragmaWarning(code, indent, special)
  of "emit"      : result = mincPragmaEmit(code, indent, special)
  of "namespace" : result = mincPragmaNamespace(code, indent, special)
  of "define"    : result = mincPragmaDefine(code, indent, special)
  of "pragma"    : result = mincPragmaCPragma(code, indent, special)
  else: code.trigger PragmaError, &"Only {KnownPragmas} pragmas are currently supported."


#_______________________________________
# @section Affixes
#_____________________________
const PrefixRawTempl = "{affix}{body}"
const PrefixTempl    = "{indent*Tab}"&PrefixRawTempl&";"
proc mincPrefix (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, nkPrefix
  let affix = ( code.:name ).renamed(code.kind, special)
  if special.hasAny {Condition, Variable, None}:
    let body = MinC(affixes.getPrefix(code, "body"), indent, special).c
    result.c =
      if Context.None in special : fmt PrefixTempl
      else                       : fmt PrefixRawTempl
  else: code.trigger ConditionError, &"Found an unmapped special case for mincPrefix:  {special}"
#___________________
const ExtraCastOperators = ["as", "@"]
const ExtraCastRawTempl  = "({right})({left})"
const ExtraCastTempl     = "{indent*Tab}"&ExtraCastRawTempl&";\n"
#___________________
const NoSpacingInfixes = ["->"]
const AssignInfixes    = ["=", "+=", "-=", "*=", "/=", "%=", "<<=", ">>=", "&=", "^=", "|="]
const InfixRawTempl    = "{left}{sep}{affix}{sep}{right}"
const InfixTempl       = "{indent*Tab}"&InfixRawTempl&";\n"
proc mincInfix (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, nkInfix
  let affix  = ( code.:name ).renamed(code.kind, special)
  let specl  = if affix in AssignInfixes: special.with Assign else: special
  let left   = MinC(affixes.getInfix(code, "left"),  indent, specl).c
  let right  = MinC(affixes.getInfix(code, "right"), indent, specl).c
  let sep    = if affix in NoSpacingInfixes: "" else: " "
  let isCast = affix in ExtraCastOperators
  let isRaw  = special.hasAny {Variable, Condition, Return, Argument, Assign}
  if isCast:
    if  isRaw : result.c = fmt ExtraCastRawTempl
    else      : result.c = fmt ExtraCastTempl
  else:
    if  isRaw : result.c = fmt InfixRawTempl
    else      : result.c = fmt InfixTempl


#______________________________________________________
# @section Discard
#_____________________________
const DiscardTempl = "{indent*Tab}(void){body};/*discard*/\n"
proc mincDiscard (
    code    : PNode;
    indent  : int            = 0;
    special : SpecialContext = Context.None;
  ) :CFilePair=
  ensure code, Discard
  let D = code[0]
  case D.kind
  of nkTupleConstr,nkPar:
    for arg in D:
      let body = MinC(arg, indent, special).c
      result.c.add fmt DiscardTempl
  else:
    let body = MinC(D, indent, special).c
    result.c = fmt DiscardTempl


#______________________________________________________
# @section Comments
#_____________________________
const NewLineTempl = "\n{indent*Tab}/// "
const CommentTempl = "{indent*Tab}/// {cmt}\n"
proc mincComment (code :PNode; indent :int= 0; special :SpecialContext= Context.None) :CFilePair=
  ensure code, Comment
  let newl = fmt NewLineTempl
  let cmt  = code.strValue.replace("\n", newl)
  result.c = fmt CommentTempl


#______________________________________________________
# @section Source-to-Source Generator
#_____________________________
proc MinC *(code :PNode; indent :int= 0; special :SpecialContext= Context.None) :CFilePair=
  if code == nil: return
  case code.kind
  # Recursive Cases
  of nkStmtList, nkTypeSection:
    for child in code   : result.add MinC( child, indent, special )

  # Intermediate cases
  # └─ Procedures
  of nkProcDef          : result = mincProcDef(code, indent, special)
  of nkFuncDef          : result = mincFuncDef(code, indent, special)
  # └─ Control flow
  of nkReturnStmt       : result = mincReturnStmt(code, indent, special)
  of nkWhileStmt        : result = mincWhile(code, indent, special)
  of nkIfStmt           : result = mincIf(code, indent, special)
  of nkIfExpr           : result = mincIf(code, indent, special)
  of nkWhenStmt         : result = mincWhen(code, indent, special)
  of nkForStmt          : result = mincFor(code, indent, special)
  # └─ Variables
  of nkConstSection     : result = mincConstSection(code, indent, special)
  of nkLetSection       : result = mincLetSection(code, indent, special)
  of nkVarSection       : result = mincVarSection(code, indent, special)
  of nkAsgn             : result = mincAsgn(code, indent, special)
  of nkDiscardStmt      : result = mincDiscard(code, indent, special)
  # └─ Pragmas
  of nkPragma           : result = mincPragma(code, indent, special)
  # └─ Affixes
  of nkPrefix           : result = mincPrefix(code, indent, special)
  of nkInfix            : result = mincInfix(code, indent, special)
  # └─ Identifiers
  of nkBracketExpr      : result = mincBracketExpr(code, indent, special)
  of nkPar              : result = mincPar(code, indent, special)
  of nkObjConstr        : result = mincObjConstr(code, indent, special)
  of nkDotExpr          : result = mincDot(code, indent, special)
  # Terminal cases
  of nkEmpty            : result = CFilePair()
  of nim.SomeLit        : result = mincLiteral(code, indent, special)
  of nkCallStrLit       : result = mincLiteral(code, indent, special)
  of nkCall             : result = mincCall(code, indent, special)
  of nkCommand          : result = mincCommand(code, indent, special)
  of nkBracket          : result = mincBracket(code, indent, special)
  of nkIdent            : result = mincIdent(code, indent, special)
  of nkIncludeStmt      : result = mincInclude(code, indent, special)
  of nkCommentStmt      : result = mincComment(code, indent, special)
  of nim.SomeType       : result = mincType(code, indent, special)
  of nkTypeDef          : result = mincTypeDef(code, indent, special)
  of nkCast             : result = mincCast(code, indent, special)
  # └─ Control flow
  of nkBreakStmt        : result = mincBreakStmt(code, indent, special)
  of nkContinueStmt     : result = mincContinueStmt(code, indent, special)

  else: code.err &"Translating {code.kind} to MinC is not supported yet."

