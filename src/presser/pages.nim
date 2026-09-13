import common, pages/[generator, templates], std/[os, strutils, json]

const DefaultThreadCount = 1 shl (when defined(gcDestructors): 3 else: 0)

type
  Redirect = object
    source, destination: string
    `type`: int

  Pages* = object
    config*: Config
    redirects: seq[Redirect]
    templates: Templates
    # same length:
    pageThreads: seq[Thread[(ptr Pages, ptr Channel[string])]]
    pageChannels: seq[Channel[string]]

proc processRedirect(pages: var Pages, path: string): Redirect =
  let s = readFile(path).splitWhitespace()
  if s.len == 0:
    echo "redirect file ", path, " does not have url inside"
    return
  result.destination = s[0]
  result.source = path[pages.config.outputDir.len ..< ^".redirect".len].replace('\\', '/')
  if result.source.len > 1 and result.source[^1] == '/':
    result.source.setLen(result.source.len - 1)
  if s.len > 1 and s[1].len != 0:
    result.type = s[1].parseInt
  else:
    result.type = 301

proc processRedirects(pages: var Pages, path: string): seq[Redirect] =
  let dir = path[pages.config.outputDir.len ..< ^".redirects".len].replace('\\', '/')
  var f: File
  if not open(f, path):
    echo "could not open redirects file ", path
    return
  var line: string
  while readLine(f, line):
    let s = splitWhitespace(line, 2)
    if s.len != 2 or s[0].len == 0 or s[1].len == 0:
      echo "redirects file ", path, " has invalid redirect ", line
      continue
    # xxx make destination path relative opt-in
    var redir = Redirect(type: 301, source: dir, destination: s[1])
    proc join(a: var string, b: string) =
      if b[0] != '/': a.add('/')
      elif a[^1] == '/': a.setLen(a.len - 1)
      a.add(b)
    join(redir.source, s[0])
    result.add(redir)

proc pageProcess(arg: (ptr Pages, ptr Channel[string])) {.thread.} =
  let (pages, chan) = arg
  let config = pages.config
  while true:
    let f = chan[].recv()
    if f == "": break
    processPage(pkMargrave, f, pages.templates, config)
    echo "processed page: ", f

proc finishRedirects(pages: var Pages) =
  if Firebase in pages.config.redirectOutputs:
    let config = json.parseFile(pages.config.templatesDir & "/firebase.json")
    if not config["hosting"].hasKey("redirects"):
      config["hosting"]["redirects"] = %[]
    for r in pages.redirects:
      config["hosting"]["redirects"].add(%r)
    when defined(testrun):
      writeFile(pages.config.outputDir & "/firebase.json", pretty(config))
    else:
      writeFile("firebase.json", $config)
  if Cloudflare in pages.config.redirectOutputs:
    var redirectsFile = ""
    for r in pages.redirects:
      redirectsFile.add(r.source)
      redirectsFile.add(' ')
      redirectsFile.add(r.destination)
      redirectsFile.add(' ')
      redirectsFile.addInt(r.type)
      redirectsFile.add("\n")
    writeFile(pages.config.outputDir & "/_redirects", redirectsFile)
  echo "added redirects to config"
  reset(pages.redirects)

proc finishPages(pages: var Pages) =
  joinThreads(pages.pageThreads)
  echo "all pages processed"

  for i in 0 ..< pages.pageChannels.len:
    pages.pageChannels[i].close()
  clearTemplates(pages.templates)

proc process*(pages: var Pages) =
  let config = pages.config
  let defaultTempl = config.templatesDir & "/default.html"
  pages.templates = initTemplates(defaultTempl)

  let threadCount = DefaultThreadCount # power of 2
  pages.pageThreads.setLen(threadCount)
  pages.pageChannels.setLen(threadCount)
  for i in 0 ..< threadCount:
    pages.pageChannels[i].open()
    createThread(pages.pageThreads[i], pageProcess, (addr pages, addr pages.pageChannels[i]))
  
  var currentThread = 0
  for f in walkDirRec(config.outputDir):
    if f.endsWith(".md") or f.endsWith(".mrg"):
      echo "queueing the processing of file: ", f
      pages.pageChannels[currentThread].send(f)
      currentThread = (currentThread + 1) and (threadCount - 1)
    elif f.endsWith(".redirect"):
      pages.redirects.add processRedirect(pages, f)
    elif f.endsWith(".redirects"):
      pages.redirects.add processRedirects(pages, f)
  for i in 0 ..< threadCount:
    pages.pageChannels[i].send("")

  pages.finishRedirects()
  pages.finishPages()
