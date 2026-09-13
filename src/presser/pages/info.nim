import rot

type
  ArticleInfo* = object
    title*, description*, url*, sitename*, `type`*, image*, author*, time*: string
    tags*: seq[string]
    twitterCard*: string

  Info* = object
    elements*: RotBlock
    `template`*: string
    title*: string
    lazy*: bool
    isArticle*: bool
    article*: ArticleInfo

proc defaultArticleInfo*(): ArticleInfo =
  ArticleInfo(sitename: "blog", type: "article", twitterCard: "summary_large_image")

template getText*(a: RotTerm, name: untyped): bool =
  let (`name`, yes) =
    case a.kind
    of Symbol: (a.symbol, true)
    of Text: (a.text, true)
    else: ("", false)
  yes

proc parseInfo*(s: string): Info =
  {.cast(gcsafe).}:
    result = Info(elements: parseRot(s))
  for p in result.elements.phrases:
    if p.head.kind != Symbol:
      continue
    let name = p.head.symbol
    let body = if p.items.len == 1: rotUnit() else: p.items[^1].term
    case name
    of "template":
      if getText(body, text):
        result.`template` = text
    of "title":
      if getText(body, text):
        result.title = text
        if result.isArticle:
          result.article.title = result.title
    of "lazy": result.lazy = true
    of "article":
      if not result.isArticle:
        result.isArticle = true
        result.article = defaultArticleInfo()
        result.article.title = result.title
    of "description":
      if result.isArticle and getText(body, text):
        result.article.description = text
    of "url":
      if result.isArticle and getText(body, text):
        result.article.url = text
    of "sitename":
      if result.isArticle and getText(body, text):
        result.article.sitename = text
    of "type":
      if result.isArticle and getText(body, text):
        result.article.type = text
    of "image":
      if result.isArticle and getText(body, text):
        result.article.image = text
    of "author":
      if result.isArticle and getText(body, text):
        result.article.author = text
    of "time", "published_time":
      if result.isArticle and getText(body, text):
        result.article.time = text
    of "tag", "tags":
      if result.isArticle:
        for i in 1 ..< p.items.len:
          if getText(p.items[i].term, text):
            result.article.tags.add text
    of "twittercard", "twitter_card":
      if result.isArticle and getText(body, text):
        result.article.time = text
    else: discard
