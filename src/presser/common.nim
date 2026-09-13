import std/[strutils, os]

type RedirectOutputKind* = enum
  Firebase
  Cloudflare

type Config* = object
  pagesDir*, assetsDir*: string
  templatesDir*: string
  outputDir*: string
  redirectOutputs*: set[RedirectOutputKind]

proc output*(config: Config, filename: string, content: string) =
  var fn = filename
  fn.removePrefix({AltSep, DirSep})
  assert fn.startsWith(config.outputDir) and
    fn.len > config.outputDir.len + 1 and
    fn[config.outputDir.len] in {AltSep, DirSep}, "stick to output folder"
  writeFile(fn, content)

type Step* = concept
  proc process(step: var Self)

proc finish*(step: Step) = discard

import std/macros

macro pipeline*(config: Config, body: untyped) =
  result = newStmtList()
  var variables: seq[NimNode]
  for b in body:
    if b.kind in {nnkVarSection, nnkLetSection, nnkConstSection}:
      for v in b:
        for vn in v[0 .. ^3]:
          variables.add(vn.basename)
    result.add(b)

  for v in variables:
    result.add(newAssignment(newDotExpr(v, ident"config"), config))
  
  for v in variables:
    result.add(newCall(ident"process", v))

  for v in variables:
    result.add(newCall(ident"finish", v))
