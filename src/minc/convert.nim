#:______________________________________________________
#  ᛟ minc  |  Copyright (C) Ivan Mar (sOkam!)  |  MIT  :
#:______________________________________________________
# std dependencies
import std/paths
import std/strformat
import std/strutils
# *Slate dependencies
import slate/format
import slate/element/error
import slate/element/procdef
import slate/element/vars
import slate/element/incldef
import slate/element/calls
import slate/element/loops
# minc dependencies
include ./fwdecl

const Tab = "  "


#______________________________________________________
# Procedure Definition
#_____________________________
const ProcDefArgTmpl = "{typ} {arg.name}{sep}"
proc mincProcDefGetArgs *(code :PNode) :string=
  ## Returns the code for all arguments of the given ProcDef node.
  assert code.kind == nkProcDef
  let params = code[procdef.Elem.Args]
  assert params.kind == nkFormalParams
  let argc = procdef.getArgCount(code)
  if argc == 0: return "void"  # Explicit fill with void for no arguments
  # Find all arguments
  for arg in procdef.args(code): # For every individual argument -> args can be single or grouped arguments. this expands them
    let typ  = if arg.typ.isPtr: &"{arg.typ.name}*" else: arg.typ.name
    let sep  = if arg.last: "" else: ", "
    result.add( fmt ProcDefArgTmpl )

proc mincProcDefGetBody *(code :PNode; indent :int= 1) :string=
  ## Returns the code for the body of the given ProcDef node.
  result.add "\n"
  result.add MinC(code[procdef.Elem.Body], indent)

proc mincFuncDef (code :PNode; indent :int= 0) :string=
  assert false, "proc and func are identical in C"  # TODO : Sideffects checks

const ProcDefTmpl = "{priv}{procdef.getRetT(code)} {procdef.getName(code)} ({mincProcDefGetArgs(code)}) {{{mincProcDefGetBody(code)}}}\n"
proc mincProcDef (code :PNode; indent :int= 0) :string=
  ## Converts a nkProcDef into the Min C Language
  assert code.kind == nkProcDef
  let priv = if procdef.isPrivate(code, indent): "static " else: ""
  result = fmt ProcDefTmpl


#______________________________________________________
# Return Statement
#_____________________________
proc mincReturnStmt (code :PNode; indent :int= 1) :string=
  assert code.kind == nkReturnStmt
  assert indent != 0, "Return statements cannot exist at the top level in C.\n" & code.renderTree
  result.add &"{indent*Tab}return {code[0].strValue};\n"


#______________________________________________________
# Variables
#_____________________________
proc mincVariable (entry :PNode; indent :int; mutable :bool) :string=
  assert entry.kind in [nkConstDef, nkIdentDefs], entry.treeRepr
  let priv = if vars.isPrivate(entry,indent): "static " else: ""
  let mut  = if not mutable: "const " else: ""
  let typ  = vars.getType(entry)
  let T    = if typ.isPtr: &"{typ.name}*" else: typ.name  # T = Type Name
  let name = vars.getName(entry)
  let val  =
    if entry[^1].kind == nkCall : mincCallRaw( entry[^1] )
    else                        : vars.getValue(entry)
  if not vars.isPrivate(entry,indent) and indent == 0:
    result.add &"{indent*Tab}extern {mut}{T} {name};\n"
  result.add &"{indent*Tab}{priv}{mut}{T} {name} = {val};\n"

proc mincConstSection (code :PNode; indent :int= 0) :string=
  assert code.kind == nkConstSection # Let and Const are identical in C
  for entry in code.sons: result.add mincVariable(entry,indent, mutable=false)

proc mincLetSection (code :PNode; indent :int= 0) :string=
  assert code.kind == nkLetSection # Let and Const are identical in C
  for entry in code.sons: result.add mincVariable(entry,indent, mutable=false)

proc mincVarSection (code :PNode; indent :int= 0) :string=
  assert code.kind == nkVarSection
  for entry in code.sons: result.add mincVariable(entry,indent, mutable=true)


#______________________________________________________
# Modules
#_____________________________
proc mincIncludeStmt (code :PNode; indent :int= 0) :string=
  assert code.kind == nkIncludeStmt
  if indent > 0: raise newException(IncludeError, &"Include statements are only allowed at the top level.\nThe incorrect code is:\n{code.renderTree}\n")
  result.add &"#include {incldef.getModule(code)}\n"


#______________________________________________________
# Function Calls
#_____________________________
const CallArgTmpl * = "{calls.getArgs(arg.node)} {calls.getArgName(arg.node)}{sep}"
proc mincCallGetArgs *(code :PNode) :string=
  ## Returns the code for all arguments of the given ProcDef node.
  assert code.kind in [nkCall, nkCommand]
  if calls.getArgCount(code) == 0: return
  for arg in calls.args(code):
    if arg.node.kind in nkStrLit..nkTripleStrLit:
      let str = arg.node.strValue.replace("\n", "\\n")
      result.add &"\"{str}\""
    elif arg.node.kind == nkNilLit: result.add "NULL"
    else: result.add arg.node.strValue
    ##[
    elif arg.len > 1:  # Arguments grouped by type
      for entry in arg.node:
        result.add entry.strValue
        result.add( if entry == arg.node[^1]: "" else: ", " )
    ]##
    result.add( if arg.last: "" else: ", " )

proc mincCallRaw (code :PNode) :string=
  assert code.kind in [nkCall, nkCommand]
  result = &"{calls.getName(code,0)}({mincCallGetArgs(code)})"

proc mincCall (code :PNode; indent :int= 0) :string=
  assert code.kind in [nkCall, nkCommand]
  result.add &"{indent*Tab}{mincCallRaw(code)};\n"

proc mincCommand (code :PNode; indent :int= 0) :string=
  assert false, "Command and Call are identical in C"

#______________________________________________________
# Comments
#_____________________________
proc mincCommentStmt (code :PNode; indent :int= 0) :string=
  assert code.kind == nkCommentStmt
  result.add &"{indent*Tab}/// {code.strValue}\n"

#______________________________________________________
# Discard
#_____________________________
proc mincDiscardStmt (code :PNode; indent :int= 0) :string=
  assert code.kind == nkDiscardStmt
  for arg in code: result.add &"{indent*Tab}(void){arg.strValue}; //discard\n"

#______________________________________________________
# While Loops
#_____________________________
proc mincWhileStmt (code :PNode; indent :int= 0) :string=
  assert code.kind == nkWhileStmt
  # TODO: Unconfuse this total mess. Remove hardcoded numbers. Should be names and a loop.
  var condition :string
  if code[0].kind == nkPrefix:
    condition.add code[0][0].strValue.replace("not","!")
    if code[0][1].kind == nkCall: condition.add mincCallRaw( code[0][1] )
    else:                         condition.add code[0][1].strValue
  # Return the code
  result.add &"{indent*Tab}while ({condition}) {{\n"
  result.add MinC( code[^1], indent+1 )
  result.add &"{indent*Tab}}}\n"

#______________________________________________________
# Source-to-Source Generator
#_____________________________
proc MinC (code :PNode; indent :int= 0) :string=
  ## Node selector function. Sends the node into the relevant codegen function.
  # Base Cases
  if code == nil: return
  case code.kind
  of nkNone             : result = mincNone(code)
  of nkEmpty            : result = mincEmpty(code)

  # Process this node
  of nkProcDef          : result = mincProcDef(code, indent)
  of nkFuncDef          : result = mincProcDef(code, indent)
  of nkReturnStmt       : result = mincReturnStmt(code, indent)
  of nkConstSection     : result = mincConstSection(code, indent)
  of nkLetSection       : result = mincLetSection(code, indent)
  of nkIncludeStmt      : result = mincIncludeStmt(code, indent)
  of nkCommand          : result = mincCommand(code, indent)
  of nkCall             : result = mincCall(code, indent)
  of nkCommentStmt      : result = mincCommentStmt(code, indent)
  of nkDiscardStmt      : result = mincDiscardStmt(code, indent)
  of nkVarSection       : result = mincVarSection(code, indent)
  of nkWhileStmt        : result = mincWhileStmt(code, indent)

  #____________________________________________________
  # TODO cases

  of nkIdent            : result = mincIdent(code)
  of nkSym              : result = mincSym(code)
  of nkType             : result = mincType(code)
  of nkComesFrom        : result = mincComesFrom(code)

  of nkDotCall          : result = mincDotCall(code)
  of nkCallStrLit       : result = mincCallStrLit(code)

  of nkInfix            : result = mincInfix(code)
  of nkPrefix           : result = mincPrefix(code)
  of nkPostfix          : result = mincPostfix(code)
  of nkHiddenCallConv   : result = mincHiddenCallConv(code)
  of nkExprEqExpr       : result = mincExprEqExpr(code)
  of nkExprColonExpr    : result = mincExprColonExpr(code)
  of nkVarTuple         : result = mincVarTuple(code)
  of nkPar              : result = mincPar(code)
  of nkObjConstr        : result = mincObjConstr(code)
  of nkCurly            : result = mincCurly(code)
  of nkCurlyExpr        : result = mincCurlyExpr(code)
  of nkBracket          : result = mincBracket(code)
  of nkBracketExpr      : result = mincBracketExpr(code)
  of nkPragmaExpr       : result = mincPragmaExpr(code)
  of nkRange            : result = mincRange(code)
  of nkDotExpr          : result = mincDotExpr(code)
  of nkCheckedFieldExpr : result = mincCheckedFieldExpr(code)
  of nkDerefExpr        : result = mincDerefExpr(code)
  of nkIfExpr           : result = mincIfExpr(code)
  of nkElifExpr         : result = mincElifExpr(code)
  of nkElseExpr         : result = mincElseExpr(code)
  of nkLambda           : result = mincLambda(code)
  of nkDo               : result = mincDo(code)
  of nkAccQuoted        : result = mincAccQuoted(code)
  of nkTableConstr      : result = mincTableConstr(code)
  of nkBind             : result = mincBind(code)
  of nkClosedSymChoice  : result = mincClosedSymChoice(code)
  of nkOpenSymChoice    : result = mincOpenSymChoice(code)
  of nkHiddenStdConv    : result = mincHiddenStdConv(code)
  of nkHiddenSubConv    : result = mincHiddenSubConv(code)
  of nkConv             : result = mincConv(code)
  of nkCast             : result = mincCast(code)
  of nkStaticExpr       : result = mincStaticExpr(code)
  of nkAddr             : result = mincAddr(code)
  of nkHiddenAddr       : result = mincHiddenAddr(code)
  of nkHiddenDeref      : result = mincHiddenDeref(code)
  of nkObjDownConv      : result = mincObjDownConv(code)
  of nkObjUpConv        : result = mincObjUpConv(code)
  of nkChckRangeF       : result = mincChckRangeF(code)
  of nkChckRange64      : result = mincChckRange64(code)
  of nkChckRange        : result = mincChckRange(code)
  of nkStringToCString  : result = mincStringToCString(code)
  of nkCStringToString  : result = mincCStringToString(code)
  of nkAsgn             : result = mincAsgn(code)
  of nkFastAsgn         : result = mincFastAsgn(code)
  of nkGenericParams    : result = mincGenericParams(code)
  of nkFormalParams     : result = mincFormalParams(code)
  of nkOfInherit        : result = mincOfInherit(code)
  of nkImportAs         : result = mincImportAs(code)
  of nkMethodDef        : result = mincMethodDef(code)
  of nkConverterDef     : result = mincConverterDef(code)
  of nkMacroDef         : result = mincMacroDef(code)
  of nkTemplateDef      : result = mincTemplateDef(code)
  of nkIteratorDef      : result = mincIteratorDef(code)
  of nkExceptBranch     : result = mincExceptBranch(code)
  of nkAsmStmt          : result = mincAsmStmt(code)
  of nkPragma           : result = mincPragma(code)
  of nkPragmaBlock      : result = mincPragmaBlock(code)

  of nkIfStmt           : result = mincIfStmt(code)
  of nkWhenStmt         : result = mincWhenStmt(code)
  of nkCaseStmt         : result = mincCaseStmt(code)
  of nkOfBranch         : result = mincOfBranch(code)
  of nkElifBranch       : result = mincElifBranch(code)
  of nkElse             : result = mincElse(code)

  of nkForStmt          : result = mincForStmt(code)
  of nkParForStmt       : result = mincParForStmt(code)

  of nkTypeSection      : result = mincTypeSection(code)
  of nkTypeDef          : result = mincTypeDef(code)

  of nkYieldStmt        : result = mincYieldStmt(code)
  of nkDefer            : result = mincDefer(code)
  of nkTryStmt          : result = mincTryStmt(code)
  of nkFinally          : result = mincFinally(code)
  of nkRaiseStmt        : result = mincRaiseStmt(code)
  of nkBreakStmt        : result = mincBreakStmt(code)
  of nkContinueStmt     : result = mincContinueStmt(code)
  of nkBlockStmt        : result = mincBlockStmt(code)
  of nkStaticStmt       : result = mincStaticStmt(code)

  of nkImportStmt       : result = mincImportStmt(code)
  of nkImportExceptStmt : result = mincImportExceptStmt(code)
  of nkExportStmt       : result = mincExportStmt(code)
  of nkExportExceptStmt : result = mincExportExceptStmt(code)
  of nkFromStmt         : result = mincFromStmt(code)

  of nkBindStmt         : result = mincBindStmt(code)
  of nkMixinStmt        : result = mincMixinStmt(code)
  of nkUsingStmt        : result = mincUsingStmt(code)
  of nkStmtListExpr     : result = mincStmtListExpr(code)
  of nkBlockExpr        : result = mincBlockExpr(code)
  of nkStmtListType     : result = mincStmtListType(code)
  of nkBlockType        : result = mincBlockType(code)
  of nkWith             : result = mincWith(code)
  of nkWithout          : result = mincWithout(code)
  of nkTypeOfExpr       : result = mincTypeOfExpr(code)
  of nkObjectTy         : result = mincObjectTy(code)
  of nkTupleTy          : result = mincTupleTy(code)
  of nkTupleClassTy     : result = mincTupleClassTy(code)
  of nkTypeClassTy      : result = mincTypeClassTy(code)
  of nkStaticTy         : result = mincStaticTy(code)
  of nkRecList          : result = mincRecList(code)
  of nkRecCase          : result = mincRecCase(code)
  of nkRecWhen          : result = mincRecWhen(code)
  of nkRefTy            : result = mincRefTy(code)
  of nkPtrTy            : result = mincPtrTy(code)
  of nkVarTy            : result = mincVarTy(code)
  of nkConstTy          : result = mincConstTy(code)
  of nkOutTy            : result = mincOutTy(code)
  of nkDistinctTy       : result = mincDistinctTy(code)
  of nkProcTy           : result = mincProcTy(code)
  of nkIteratorTy       : result = mincIteratorTy(code)
  of nkSinkAsgn         : result = mincSinkAsgn(code)
  of nkEnumTy           : result = mincEnumTy(code)
  of nkEnumFieldDef     : result = mincEnumFieldDef(code)
  of nkArgList          : result = mincArgList(code)
  of nkPattern          : result = mincPattern(code)
  of nkHiddenTryStmt    : result = mincHiddenTryStmt(code)
  of nkClosure          : result = mincClosure(code)
  of nkGotoState        : result = mincGotoState(code)
  of nkState            : result = mincState(code)
  of nkBreakState       : result = mincBreakState(code)
  of nkTupleConstr      : result = mincTupleConstr(code)
  of nkError            : result = mincError(code)
  of nkModuleRef        : result = mincModuleRef(code)      # for .rod file support: A (moduleId, itemId) pair
  of nkReplayAction     : result = mincReplayAction(code)   # for .rod file support: A replay action
  of nkNilRodNode       : result = mincNilRodNode(code)     # for .rod file support: a 'nil' PNode

  # Unreachable
  of nkConstDef         : result = mincConstDef(code)   # Accessed by nkConstSection
  of nkIdentDefs        : result = mincIdentDefs(code)  # Accessed by nkLetSection and nkVarSection
  of nkCharLit          : result = mincCharLit(code)
  of nkIntLit           : result = mincIntLit(code)
  of nkInt8Lit          : result = mincInt8Lit(code)
  of nkInt16Lit         : result = mincInt16Lit(code)
  of nkInt32Lit         : result = mincInt32Lit(code)
  of nkInt64Lit         : result = mincInt64Lit(code)
  of nkUIntLit          : result = mincUIntLit(code)
  of nkUInt8Lit         : result = mincUInt8Lit(code)
  of nkUInt16Lit        : result = mincUInt16Lit(code)
  of nkUInt32Lit        : result = mincUInt32Lit(code)
  of nkUInt64Lit        : result = mincUInt64Lit(code)
  of nkFloatLit         : result = mincFloatLit(code)
  of nkFloat32Lit       : result = mincFloat32Lit(code)
  of nkFloat64Lit       : result = mincFloat64Lit(code)
  of nkFloat128Lit      : result = mincFloat128Lit(code)
  of nkStrLit           : result = mincStrLit(code)
  of nkRStrLit          : result = mincRStrLit(code)
  of nkTripleStrLit     : result = mincTripleStrLit(code)
  of nkNilLit           : result = mincNilLit(code)

  # Recursive Cases
  of nkStmtList:
    for child in code: result.add MinC( child, indent )


proc toMinC *(code :string|Path) :string=
  ## Converts a block of Nim code into the Min C Language
  when code is Path: MinC( code.readAST() ) & "\n"
  else:              MinC( code.getAST()  ) & "\n"

