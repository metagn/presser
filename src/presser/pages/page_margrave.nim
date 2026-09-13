import std/[strutils, uri, os], ./[info, templates], ../common, margrave, margrave/[common, element], margrave/parser/[defs, utils], rot

type MargravePage* = object
  info*: Info
  body*: seq[MargraveElement]

proc processSingleElement(page: MargravePage, element: MargraveElement) =
  if page.info.lazy:
    if not element.isText:
      case element.tag
      of tagImage: element.attr("loading", "lazy")
      of tagAudio, tagVideo: element.attr("preload", "none")
      else: discard

proc processNested(page: MargravePage, element: MargraveElement) =
  processSingleElement(page, element)
  if not element.isText:
    for c in element.content:
      processNested(page, c)

proc setYoutube(element: MargraveElement, id: NativeString) =
  element.tag = tagOther
  element.attr("tag", "iframe")
  element.attr("width", "953")
  element.attr("height", "536")
  element.attr("src", NativeString"https://www.youtube.com/embed/" & id)
  element.attr("title", "(youtube embed)")
  element.attr("frameborder", "0")
  element.attr("allow", "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture")
  element.attr("allowfullscreen", "")

proc setLink(element: MargraveElement, link: Link) =
  if not element.isText and element.tag == tagImage:
    let uri = parseUri($link)
    var h = uri.hostname
    h.removePrefix("www.")
    case h
    of "youtu.be":
      let id = toNativeString(uri.path)
      if id.len != 0:
        setYoutube(element, id)
        return
    of "youtube.com":
      var id: NativeString
      for k, v in decodeQuery(uri.query):
        if k == "v":
          id = toNativeString(v)
          break
      if id.len != 0:
        setYoutube(element, id)
        return
    else: discard
  setLinkDefault(element, link)

proc parseBody(page: var MargravePage, body: string) =
  let options = MargraveOptions(setLinkHandler: setLink, insertLineBreaks: true, disableTextAlignExtension: false)
  for b in parseMargrave(body, options):
    processNested(page, b)
    page.body.add(b)

proc loadFrom*(page: var MargravePage, file: File) =
  var 
    line = ""
    recordMeta = false
    body = ""

  while file.readLine(line):
    if line.isEmptyOrWhitespace:
      continue
    elif line == "---":
      recordMeta = true
    else:
      body.add(line)
      body.add("\n")
    break
  if recordMeta:
    var meta: string
    while file.readLine(line) and line != "---":
      meta.add(line)
      meta.add("\n")
    page.info = parseInfo(meta)
  while file.readLine(line):
    body.add(line)
    body.add("\n")
  parseBody(page, body)

proc loadFrom*(page: var MargravePage, text: string) =
  let lines = text.splitLines
  var
    i = 0
    recordMeta = false
    body = ""

  while i < lines.len:
    let line = lines[i]
    inc i
    if line.isEmptyOrWhitespace:
      continue
    elif line == "---":
      recordMeta = true
    else:
      body.add(line)
      body.add("\n")
    break
  if recordMeta:
    var meta: string
    while i < lines.len:
      let line = lines[i]
      inc i
      if line == "---":
        break
      else:
        meta.add(line)
        meta.add("\n")
    page.info = parseInfo(meta)
  while i < lines.len:
    let line = lines[i]
    inc i
    body.add(line)
    body.add("\n")
  parseBody(page, body)

proc genBody(page: MargravePage): string =
  result = ""
  for b in page.body:
    result.add($b)

proc addHead(result: var string, a: RotPhrase)

proc defaultAddHtml(result: var string, name: string, body: RotTerm, a: RotPhrase) =
  result.add('<')
  result.add(name)
  proc addArgument(res: var string, arg: tuple[name, value: string]) =
    if arg.name.len == 0:
      echo "got argument without name"
    else:
      res.add(' ')
      res.add(arg.name)
    if arg.value.len != 0:
      res.add("=\"")
      res.add(arg.value)
      res.add('"')
  for ar in a.arguments:
    if ar.associated.len == 0:
      if ar.term.kind == Symbol:
        addArgument(result, (ar.term.symbol, ""))
    elif ar.associated.len == 1:
      let left = ar.term
      let right = ar.associated[0]
      var arg: tuple[name, value: string]
      if left.kind == Symbol:
        arg.name = left.symbol
      elif left.kind == Text:
        arg.name = left.text
      if right.kind == Symbol:
        arg.value = right.symbol
      elif right.kind == Text:
        arg.value = right.text
      if arg.name.len != 0:
        addArgument(result, arg)
  let needsBody = name in ["script"]
  case body.kind
  of Symbol, Text, Block:
    result.add('>')
    if body.kind == Symbol:
      result.add(body.symbol)
    elif body.kind == Text:
      result.add(body.text)
    elif body.kind == Block:
      for p in body.block.phrases:
        result.addHead(p)
    result.add("</")
    result.add(name)
    result.add('>')
  else:
    if needsBody:
      result.add("></")
      result.add(name)
      result.add('>')
    else:
      result.add("/>")

proc addHead(result: var string, a: RotPhrase) =
  if not (a.items.len != 0 and a.head.kind == Symbol):
    for b in a.items:
      if b.term.kind == Text:
        result.add b.term.text
    return
  let name = a.head.symbol
  let body = if a.items.len == 1: rotUnit() else: a.items[^1].term
  case name
  of "template", "lazy": discard
  of "background":
    if body.kind == Text:
      let val = body.text
      result.add("<style>body{background-")
      if '/' in val:
        result.add("image:url(\"")
        result.add(val)
        result.add("\")")
      else:
        result.add("color:")
        result.add(val)
      result.add("}</style>")
  of "icon":
    if body.kind == Text:
      let link = body.text
      result.add("<link rel=\"icon\" ")
      if link.endsWith(".ico"):
        result.add("type=\"image/x-icon\" ")
      elif link.endsWith(".png"):
        result.add("type=\"image/png\" ")
      elif link.endsWith(".jpg") or link.endsWith(".jpeg"):
        result.add("type=\"image/jpeg\" ")
      result.add("href=\"")
      result.add(link)
      result.add("\"/>")
  of "stylesheet":
    if body.kind == Text:
      let val = body.text
      result.add("<link rel=\"stylesheet\" href=\"")
      result.add(val)
      result.add("\"/>")
  of "article", "description", "url", "sitename", "type", "image", "author", "time", "tag", "tags", "published_time":
    # article
    discard
  else:
    result.defaultAddHtml(name, body, a)

proc toHead*(meta: Info): string =
  result = ""
  if meta.isArticle:
    if meta.article.title != "":
      result.add("<meta name=\"og:title\" content=\"")
      result.add meta.article.title
      result.add("\"/>")
    if meta.article.description != "":
      result.add("<meta name=\"og:description\" content=\"")
      result.add meta.article.description
      result.add("\"/>")
    if meta.article.sitename != "":
      result.add("<meta name=\"og:site_name\" content=\"")
      result.add meta.article.sitename
      result.add("\"/>")
    if meta.article.url != "":
      result.add("<meta name=\"og:url\" content=\"")
      result.add meta.article.url
      result.add("\"/>")
    if meta.article.type != "":
      result.add("<meta name=\"og:type\" content=\"")
      result.add meta.article.type
      result.add("\"/>")
    if meta.article.author != "":
      result.add("<meta name=\"og:article:author\" content=\"")
      result.add meta.article.author
      result.add("\"/>")
    if meta.article.time != "":
      result.add("<meta name=\"og:article:published_time\" content=\"")
      result.add meta.article.time
      result.add("\"/>")
    if meta.article.tags.len != 0:
      for tag in meta.article.tags:
        if tag != "":
          result.add("<meta name=\"og:article:tag\" content=\"")
          result.add tag
          result.add("\"/>")
    if meta.article.twitterCard != "":
      result.add("<meta name=\"twitter:card\" content=\"")
      result.add meta.article.twitterCard
      result.add("\"/>")
  for a in meta.elements.phrases:
    addHead(result, a)

proc toHtml*(page: MargravePage, tmpl: string): string =
  {.cast(gcsafe).}:
    result = tmpl.multiReplace({
      "$head": toHead(page.info),
      "$body": genBody(page)
    })

proc processMargravePage*(path: string, templates: var Templates, config: Config) =
  var page = MargravePage()
  let file = open(path, fmRead)
  try: page.loadFrom(file)
  finally: file.close()
  var templ: string
  if page.info.`template`.len != 0:
    templ = templates.getTemplate(page.info.`template`)
  if templ.len == 0:
    templ = templates.defaultTemplate.content
  var newPath = path
  let extPos = path.rfind('.')
  if extPos >= 0:
    let dirPos = path.rfind({DirSep, AltSep})
    if dirPos < 0 or extPos > dirPos:
      newPath.setLen(extPos)
  newPath.add(".html")
  output(config, newPath, page.toHtml(templ))
