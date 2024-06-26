const Title = "Variables"
#_______________________________________
# @deps tests
include ../base
const thisDir = currentSourcePath.Path.parentDir()
template tName:Path= thisDir.lastPathPart()
#_______________________________________


#_______________________________________
# @section Test
#_____________________________
test name "01 | Const: Normal definition"     : check "01"
test name "02 | Const: Private definition"    : check "02"
test name "03 | Let: Private definition"      : check "03"
test name "04 | Var: Private definition"      : check "04"
test name "05 | Return: Identifier"           : check "05"
test name "06 | Visiblity"                    : check "06"
# Assignment
test name "07 | Assignment: Arrays"           : check "07"
test name "08 | Assignment: Identifiers"      : check "08"
test name "09 | Assignment: Literals"         : check "09"
test name "10 | Assignment: Multi-word Types" : check "10"
test name "11 | Assignment: Object Constr"    : check "11"
test name "12 | Assignment: Union Initialize" : check "12"
test name "13 | Assignment: DotExpr values"   : check "13"
test name "14 | Assignment: Parenthesis"      : check "14"
test name "15 | Assignment: Dereference"      : check "15"
# Pragmas
test name "20 | Pragma: Persist"              : check "20"
test name "21 | Pragma: Readonly"             : check "21"

