#:______________________________________________________
#  ᛟ minc  |  Copyright (C) Ivan Mar (sOkam!)  |  MIT  :
#:______________________________________________________
## @fileoverview
## Defines the minc compiler preprocessor functionality
#_______________________________________________________|
# @deps std
import std/strutils
import std/paths
import std/sets
# @deps minc
import ./logger


func isInclude (line :string) :bool=  line.startsWith("include") and '\"' notin line and '<' notin line and '>' notin line
  ## @descr Checks if the line contains a file include that should be processed
  ## @note Lines that match start with `include` and contain a path without any " < > characters

var includedFiles :HashSet[string]
  ## @descr Processed include files state
proc getInclude (line :string; root :Path) :tuple[code:string, root:Path]=
  ## @descr Gets the contents of the file referenced by the include line
  ## @req The compiler logger object must be initialized before running this function.
  let path     :Path= line[8..^1].strip().strip( leading=false, chars={'\n'} ).Path
  let file     :Path= root/path.addFileExt("cm")
  let included :bool= includedFiles.containsOrIncl(file.string)
  if included: dbg "Skipped recursive include for file: ", file.string; return
  result.root = file.splitFile.dir
  try    : result.code = readFile(file.string)
  except : fail "Tried to include a file, but failed reading it.\n  ", file.string

proc processIncludes *(code :string; root :Path) :string=
  ## @descr Recursively add all of the includes that should be preprocessed
  for line in code.splitLines:
    if line.isInclude:
      var tmp = line.getInclude(root)
      result.add processIncludes(tmp.code, tmp.root)
    else: result.add line & "\n"
