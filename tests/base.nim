# @warning MUST be `include`d, not `import`ed
#_______________________________________
# @section Dependencies used by all tests
# @deps std
import std/unittest
# @deps ndk
import nstd/paths
import nstd/shell
import nstd/strings
import nstd/logger except err
from ../src/minc/cfg import Prefix


#_______________________________________
# @section General Tools
#_____________________________
logger.init(name=cfg.Prefix, threshold=Log.Err)
#___________________
type UnitTestError = object of CatchableError
template err *(msg :varargs[string, `$`]) :void= raise newException(UnitTestError, msg.join(""))


#_______________________________________
# @section Tests Tools
#_____________________________
template name *(
    descr : string;
    testN : string = "test";
    title : string = "";
  ) :string=
  ## @descr Confusing syntax. Returns the correct prefix for the given test information
  let t = when declared(Title): Title else: title
  let n = when declared(tName): tName else: testN
  n.string&": " & (
    if t != "" : t&" | " else: ""
    ) & descr
#_____________________________
proc minc *(args :varargs[string, `$`]) :void=  sh "minc " & args.join(" ")
proc compile *(file,outDir :Path) :string=
  let tmp = outDir/"tmp.c"
  if fileExists(tmp): tmp.removeFile
  try    : minc "cc", file.string, "tmp.c", "--codeDir:"&outDir.string
  except : err "Something went wrong when compiling a tmp file:  ", tmp.string
  try    : result = readFile(tmp)
  except : err "Something went wrong when reading the resulting tmp file:  ", tmp.string
#_____________________________
template compile *(file :Path) :string=  compile file, thisDir
#_____________________________
template check *(cm,C :Path) :void=
  const fileA = "A.c".Path
  const fileB = "B.c".Path
  let A = cm.compile
  let B = C.readFile
  if A != B:
    fileA.writeFile(A)
    fileB.writeFile(B)
    try : sh "diff", fileA, fileB
    except CatchableError: discard
    rm fileA
    rm fileB
    check false
  else:
    check A == B
template check *(file :string) :void=  check thisDir/file.Path.changeFileExt(".cm"), thisDir/file.Path.changeFileExt(".c")

