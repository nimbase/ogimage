## Segment-based rich text over nvg spans.
##
## Build styled runs with composable constructors instead of markup:
## `strong`, `em`, `fg`, `bg` and `link` wrap a string or another
## segment, so `@[plain("Ship "), strong(fg("faster", red))]` stays
## typed all the way down to `TextSpan`. No parsing, no escaping.

import std/strutils
import std/unicode
import nvg

type
  OgSeg* = object
    ## One styled run. `link` is empty for non-links; a link renders
    ## accent-colored and underlined (visual only: PNGs are static).
    text*: string
    bold*: bool
    italic*: bool
    hasFg*: bool
    fg*: Color
    hasBg*: bool
    bg*: Color
    link*: string

proc plain*(s: string): OgSeg =
  OgSeg(text: s)

proc strong*(s: string): OgSeg =
  OgSeg(text: s, bold: true)

proc strong*(s: OgSeg): OgSeg =
  result = s
  result.bold = true

proc em*(s: string): OgSeg =
  OgSeg(text: s, italic: true)

proc em*(s: OgSeg): OgSeg =
  result = s
  result.italic = true

proc fg*(s: string, color: Color): OgSeg =
  OgSeg(text: s, hasFg: true, fg: color)

proc fg*(s: OgSeg, color: Color): OgSeg =
  result = s
  result.hasFg = true
  result.fg = color

proc bg*(s: string, color: Color): OgSeg =
  OgSeg(text: s, hasBg: true, bg: color)

proc bg*(s: OgSeg, color: Color): OgSeg =
  result = s
  result.hasBg = true
  result.bg = color

proc link*(s: string, url: string): OgSeg =
  OgSeg(text: s, link: url)

proc link*(s: OgSeg, url: string): OgSeg =
  result = s
  result.link = url

proc segmentsText*(segs: openArray[OgSeg]): string =
  for s in segs:
    result.add(s.text)

proc normalizeSegText(s: string): string =
  ## Match the layout normalization in `layoutBoxSpans`, so byte
  ## offsets computed here index the shaped string.
  s.replace("\r\n", "\n").replace("\r", "\n")

proc toTextSpans*(segs: openArray[OgSeg], strongF, emF: TextFont,
    accent: Color): tuple[text: string, spans: seq[TextSpan],
    bgs: seq[tuple[first, last: int, color: Color]]] =
  ## Concatenate segments and build the nvg spans for them. `nil`
  ## faces fall back to the layout font. Links take `accent` unless
  ## they carry an explicit `fg`.
  var text = ""
  var spans: seq[TextSpan] = @[]
  var bgs: seq[tuple[first, last: int, color: Color]] = @[]
  for s in segs:
    let t = normalizeSegText(s.text)
    if t == "":
      continue
    let first = text.len
    text.add(t)
    let last = text.len
    var span = TextSpan(first: first, last: last)
    if s.bold and s.italic:
      span.font = if emF != nil: emF else: strongF
    elif s.bold:
      span.font = strongF
    elif s.italic:
      span.font = emF
    if s.hasFg:
      span.color = s.fg
      span.hasColor = true
    elif s.link != "":
      span.color = accent
      span.hasColor = true
    if s.link != "":
      span.decor = tdUnderline
    spans.add(span)
    if s.hasBg:
      bgs.add((first, last, s.bg))
  (text, spans, bgs)

proc trimSegs*(segs: openArray[OgSeg],
    maxBytes: int): seq[OgSeg] =
  ## Cut concatenated segments to `maxBytes` (rune-boundary safe),
  ## keeping styles and dropping empties. Non-positive budgets keep
  ## just the ellipsis marker so clipped boxes never go blank.
  if maxBytes <= 0:
    return @[plain("...")]
  var budget = maxBytes
  for s in segs:
    if budget <= 0:
      break
    if s.text.len <= budget:
      result.add(s)
      budget -= s.text.len
    else:
      var cut = s.text
      while cut.len > budget:
        cut.setLen(max(0, cut.len - 1))
        while cut.len > 0 and
            (cut[cut.len - 1].uint8 and 0xC0'u8) == 0x80'u8:
          cut.setLen(cut.len - 1)
      if cut != "":
        var c = s
        c.text = cut
        result.add(c)
      budget = 0
  if result.len == 0:
    result = @[plain("...")]
