## Layout and rasterization of `OgImage` via `nvg`.
##
## Fixed layout grid on 1200x630: badge, title box (ellipsis,
## 3 lines), description box (ellipsis, 2 lines), footer row.
## Text never auto-shrinks; overflow trims with "..." instead.

import std/math
import std/strutils
import std/unicode
import nvg
import ./types
import ./theme
import ./fonts

export types
export theme

proc bgEndpoints(w, h: int,
    angleDeg: float64): tuple[sx, sy, ex, ey: float64] =
  let a = degToRad(angleDeg)
  let dx = cos(a)
  let dy = sin(a)
  let half = sqrt(float64(w * w + h * h)) * 0.5
  let cx = float64(w) * 0.5
  let cy = float64(h) * 0.5
  (cx - dx * half, cy - dy * half, cx + dx * half, cy + dy * half)

proc drawImageFit(c: Canvas, id: int, W, H: float64, fit: OgBgFit,
    pos: OgBgPos) =
  ## Draw `id` per `fit`: cover scales to fill and crops, contain
  ## scales to fit inside (letterboxing on the cleared page color),
  ## fill stretches to the exact canvas size. `pos` is either
  ## centered or an explicit px top-left origin. Only the image
  ## rect itself is filled, so letterbox/off-canvas gaps keep the
  ## page color instead of smeared edge texels.
  let (iw, ih, ok) = c.imageSize(id)
  if not ok or iw <= 0 or ih <= 0:
    return
  var dw, dh, ox, oy: float64
  case fit
  of bgFill:
    dw = W
    dh = H
    ox = 0.0
    oy = 0.0
  of bgCover:
    let s = max(W / float64(iw), H / float64(ih))
    dw = float64(iw) * s
    dh = float64(ih) * s
    if pos.centered:
      ox = (W - dw) * 0.5
      oy = (H - dh) * 0.5
    else:
      ox = pos.x
      oy = pos.y
  of bgContain:
    let s = min(W / float64(iw), H / float64(ih))
    dw = float64(iw) * s
    dh = float64(ih) * s
    if pos.centered:
      ox = (W - dw) * 0.5
      oy = (H - dh) * 0.5
    else:
      ox = pos.x
      oy = pos.y
  c.beginPath()
  c.rect(ox, oy, dw, dh)
  c.setFillPaint(c.imagePattern(ox, oy, dw, dh, 0.0, id, 1.0))
  c.fill()

proc fittedImageTarget(dispW, dispH, factor: float64): tuple[w, h: int] =
  ## Upload size for a `dispW` x `dispH` draw at `factor` oversample.
  (max(1, int(dispW * factor + 0.5)), max(1, int(dispH * factor + 0.5)))

proc areaAverage(src: openArray[uint8], sw, sh, dw, dh: int): seq[uint8] =
  ## Area-weighted box resample to `dw` x `dh` in premultiplied space,
  ## so thin strokes survive heavy minification as even coverage
  ## instead of dropout. Upsampling (or equal sizes) copies nearest.
  result = newSeq[uint8](dw * dh * 4)
  if sw <= 0 or sh <= 0 or dw <= 0 or dh <= 0:
    return
  if dw >= sw and dh >= sh:
    for y in 0 ..< dh:
      for x in 0 ..< dw:
        let sx = min(sw - 1, int(float64(x) * float64(sw) / float64(dw)))
        let sy = min(sh - 1, int(float64(y) * float64(sh) / float64(dh)))
        let s = (sy * sw + sx) * 4
        let d = (y * dw + x) * 4
        result[d] = src[s]
        result[d + 1] = src[s + 1]
        result[d + 2] = src[s + 2]
        result[d + 3] = src[s + 3]
    return
  let sx = float64(sw) / float64(dw)
  let sy = float64(sh) / float64(dh)
  for y in 0 ..< dh:
    let y0 = float64(y) * sy
    let y1 = y0 + sy
    for x in 0 ..< dw:
      let x0 = float64(x) * sx
      let x1 = x0 + sx
      var acc = [0.0, 0.0, 0.0, 0.0]
      var area = 0.0
      let ix0 = max(0, int(y0))
      let ix1 = min(sh - 1, int(y1 - 1e-9))
      let iy0 = max(0, int(x0))
      let iy1 = min(sw - 1, int(x1 - 1e-9))
      for j in ix0 .. ix1:
        let wy = min(float64(j + 1), y1) - max(float64(j), y0)
        for i in iy0 .. iy1:
          let wx = min(float64(i + 1), x1) - max(float64(i), x0)
          let w = wx * wy
          let s = (j * sw + i) * 4
          let a = float64(src[s + 3]) / 255.0
          acc[0] += float64(src[s]) / 255.0 * a * w
          acc[1] += float64(src[s + 1]) / 255.0 * a * w
          acc[2] += float64(src[s + 2]) / 255.0 * a * w
          acc[3] += a * w
          area += w
      let d = (y * dw + x) * 4
      if area > 1e-9 and acc[3] > 1e-9 * area:
        let a = acc[3] / area
        result[d] = uint8(min(255.0, acc[0] / area / a * 255.0 + 0.5))
        result[d + 1] = uint8(min(255.0, acc[1] / area / a * 255.0 + 0.5))
        result[d + 2] = uint8(min(255.0, acc[2] / area / a * 255.0 + 0.5))
        result[d + 3] = uint8(min(255.0, a * 255.0 + 0.5))
      else:
        result[d] = 0
        result[d + 1] = 0
        result[d + 2] = 0
        result[d + 3] = 0

proc createFittedImage*(c: Canvas, path: string, dispW, dispH: float64,
    factor = 2.0, flags: set[ImageFlag] = {}): int =
  ## Load `path` and upload it at `factor`x the drawn size. nvg image
  ## patterns sample one bilinear tap with no mipmaps, so drawing a
  ## large source at a small size aliases (thin icon strokes break
  ## up); area-averaging down to a modest oversample here keeps
  ## coverage even. Sources at or below the target upload as-is.
  ## Returns 0 for missing/undecodable files, like `createImageFile`.
  ## SVG has no decoder in nvg: vector paths always fail here.
  if dispW <= 0.0 or dispH <= 0.0:
    return 0
  var bytes: seq[uint8]
  try:
    bytes = cast[seq[uint8]](readFile(path))
  except CatchableError:
    return 0
  let d = decodeRgba8(bytes)
  if not d.ok or d.w <= 0 or d.h <= 0:
    return 0
  let (tw, th) = fittedImageTarget(dispW, dispH, factor)
  if tw >= d.w and th >= d.h:
    return c.createImageRGBA(d.w, d.h, flags, d.pixels)
  c.createImageRGBA(tw, th, flags, areaAverage(d.pixels, d.w, d.h, tw, th))

proc drawBackground(c: Canvas, og: OgImage, th: OgTheme) =
  let W = float64(og.width)
  let H = float64(og.height)
  if og.hasBackground:
    case og.background.kind
    of bgSolid:
      c.clear(og.background.color)
      return
    of bgGradient:
      let e = bgEndpoints(og.width, og.height,
        og.background.angleDeg)
      c.clear(th.pageBg)
      c.beginPath()
      c.rect(0, 0, W, H)
      c.setFillPaint(c.linearGradient(e.sx, e.sy, e.ex, e.ey,
        og.background.fromColor, og.background.toColor))
      c.fill()
      return
    of bgImage:
      c.clear(th.pageBg)
      if og.background.path != "":
        let id = c.createImageFile(og.background.path, {})
        if id != 0:
          drawImageFit(c, id, W, H, og.background.fit,
            og.background.pos)
          # Scrim between photo and text: `#000` at overlayAlpha
          # fading to transparent along overlayAngleDeg, so copy
          # stays legible over busy photos.
          let e = bgEndpoints(og.width, og.height,
            og.background.overlayAngleDeg)
          c.beginPath()
          c.rect(0, 0, W, H)
          c.setFillPaint(c.linearGradient(e.sx, e.sy, e.ex, e.ey,
            og.background.tint.withAlpha(
              og.background.overlayAlpha),
            og.background.tint.withAlpha(0.0)))
          c.fill()
          return
      # Undecodable image falls through to the preset default.
      discard
  case og.preset
  of opGradient:
    let e = bgEndpoints(og.width, og.height, 135.0)
    c.clear(th.pageBg)
    c.beginPath()
    c.rect(0, 0, W, H)
    c.setFillPaint(c.linearGradient(e.sx, e.sy, e.ex, e.ey,
      rgb(79, 70, 229), rgb(124, 58, 237)))
    c.fill()
  of opBrand:
    let e = bgEndpoints(og.width, og.height, 135.0)
    c.clear(th.pageBg)
    c.beginPath()
    c.rect(0, 0, W, H)
    c.setFillPaint(c.linearGradient(e.sx, e.sy, e.ex, e.ey,
      th.accent, th.pageBg))
    c.fill()
  else:
    c.clear(th.pageBg)

proc drawDecor*(c: Canvas, og: OgImage, th: OgTheme) =
  ## Opt-in glow discs (no longer drawn implicitly). Call after
  ## `render` content or from custom example code when wanted.
  let W = float64(og.width)
  let H = float64(og.height)
  c.setFillColor(th.accent.withAlpha(0.10))
  c.beginPath()
  c.circle(W - 140.0, 90.0, 210.0)
  c.fill()
  c.setFillColor(rgbaf(1, 1, 1, 0.04))
  c.beginPath()
  c.circle(120.0, H - 60.0, 170.0)
  c.fill()

proc drawPlaceholder(c: Canvas, fontId: int, x, y, w, h,
    radius: float64) =
  ## Gray fallback box used when an image cannot be loaded. Boxes
  ## of 48px or more also get the centered `WxH` dimensions label;
  ## smaller ones stay plain, since the label would be illegible.
  c.beginPath()
  c.roundedRect(x, y, w, h, radius)
  c.setFillColor(rgb(209, 213, 219))
  c.fill()
  if min(w, h) < 48.0:
    return
  c.setFontFaceId(fontId)
  c.setFontSize(max(8.0, min(w, h) * 0.2))
  c.setLineHeight(1.0)
  c.setFillColor(rgb(75, 85, 99))
  let label = $int(w + 0.5) & "x" & $int(h + 0.5)
  discard c.fillTextBox(x, y, label, TextBoxOpts(maxW: w, boxH: h,
    ha: thaCenter, va: tvaMiddle, wrap: false, overflow: toVisible,
    fit: tfNone, maxLines: 1, ellipsis: ""))

proc ellipsizeToLines*(c: Canvas, s: string,
    o: TextBoxOpts): string

proc segBoxOpts(w, boxH: float64, ha: TextHAlign,
    maxLines: int): TextBoxOpts =
  TextBoxOpts(maxW: w, boxH: boxH, ha: ha, va: tvaTop, wrap: true,
    overflow: toEllipsis, fit: tfNone, maxLines: maxLines,
    ellipsis: "...")

proc drawSegBackgrounds(c: Canvas, base: TextFont, sizePx: float64,
    text: string, spans: seq[TextSpan],
    bgs: seq[tuple[first, last: int, color: Color]], lineH: float64,
    o: TextBoxOpts, x, y: float64) =
  ## Tight per-line highlight rects behind `bgs` ink ranges. Layout
  ## glyphs are already alignment-final, so layout space maps to
  ## the box with the same shift `paintBox` uses.
  if bgs.len == 0 or base == nil:
    return
  let bl = layoutBoxSpans(base, sizePx, text, spans, 0.0, lineH, 0.0, o)
  let padX = bl.sizePx * 0.12
  let padY = bl.sizePx * 0.08
  for i in 0 ..< bl.lay.lines.len:
    let line = bl.lay.lines[i]
    for (first, last, color) in bgs:
      var x0 = Inf
      var x1 = NegInf
      var y0 = Inf
      var y1 = NegInf
      for g in line.glyphs:
        if not g.hasInk or g.boxKind != sbkNone:
          continue
        if g.cluster >= uint32(first) and g.cluster < uint32(last):
          x0 = min(x0, g.x0)
          x1 = max(x1, g.x1)
          y0 = min(y0, g.y0)
          y1 = max(y1, g.y1)
      if x1 > x0:
        let oy = y + bl.shift + bl.lay.lineY(i)
        c.beginPath()
        c.rect(x + x0 - padX, oy + y0 - padY,
          (x1 - x0) + padX * 2.0, (y1 - y0) + padY * 2.0)
        c.setFillColor(color)
        c.fill()

proc drawSegText(c: Canvas, og: OgImage, th: OgTheme,
    segs: seq[OgSeg], baseId: int, basePath: string, baseIdx: int,
    ink: Color, sizePx, lineH, x, y, w, boxH: float64,
    maxLines: int): float64 =
  ## Rich-text twin of the plain title/description blocks: per-run
  ## faces, fg colors and link styling via spans, bg highlights
  ## behind, same fixed-size ellipsis clamping. Bold metrics run a
  ## touch wider than the base face, so edge-case line counts may
  ## differ by one from the plain path.
  let strongF = loadFace(og.fontStrongPath, og.strongFaceIndex)
  let emF = loadFace(og.fontEmPath, og.emFaceIndex)
  let o = segBoxOpts(w, boxH, th.align, maxLines)
  c.setFontFaceId(baseId)
  c.setFontSize(sizePx)
  c.setLineHeight(lineH)
  c.setTextAlign(th.align, tvaTop)
  c.setFillColor(ink)
  var cur = segs
  var (text, spans, bgs) = toTextSpans(cur, strongF, emF, th.accent)
  if maxLines > 0 and
      c.measureSpanBox(0, 0, text, spans, o).lineCount > maxLines:
    let trimmed = c.ellipsizeToLines(text, o)
    var cutBytes = trimmed.len
    if trimmed.endsWith(o.ellipsis):
      cutBytes = trimmed.len - o.ellipsis.len
    cur = trimSegs(cur, cutBytes)
    (text, spans, bgs) = toTextSpans(cur, strongF, emF, th.accent)
  c.drawSegBackgrounds(loadFace(basePath, baseIdx), sizePx, text,
    spans, bgs, lineH, o, x, y)
  c.setFillColor(ink) # highlights reuse the state fill; restore ink
  c.fillSpanBox(x, y, text, spans, o)

proc drawLogo(c: Canvas, og: OgImage, th: OgTheme, fontId: int) =
  if og.content.logoPath == "":
    return
  const box = 72.0
  let id = c.createImageFile(og.content.logoPath, {})
  if id != 0:
    let (iw, ih, ok) = c.imageSize(id)
    if ok and iw > 0 and ih > 0:
      let scale = min(box / float64(iw), box / float64(ih))
      let dw = float64(iw) * scale
      let dh = float64(ih) * scale
      var dx, dy: float64
      if th.centered:
        dx = (float64(og.width) - dw) * 0.5
        dy = 52.0 + (box - dh) * 0.5
      else:
        dx = float64(og.width) - th.padding - dw
        dy = 56.0 + (box - dh) * 0.5
      c.beginPath()
      c.roundedRect(dx, dy, dw, dh, 16.0)
      c.setFillPaint(c.imagePattern(dx, dy, dw, dh, 0.0, id, 1.0))
      c.fill()
      return
  var bx, by: float64
  if th.centered:
    bx = (float64(og.width) - box) * 0.5
    by = 52.0
  else:
    bx = float64(og.width) - th.padding - box
    by = 56.0
  c.drawPlaceholder(fontId, bx, by, box, box, 16.0)

const photoSize* = 128.0
  ## Photo avatar edge length in px (maximum 128x128).
const photoRadius* = 20.0
  ## Photo avatar corner radius in px.
const photoGap* = 24.0
  ## Gap between the photo avatar and the headline.

proc drawPhoto(c: Canvas, id: int, x, y: float64): bool =
  ## Cover-fit image `id` into a `photoSize` square masked with a
  ## `photoRadius` rounded rect at `(x, y)`. Returns false when the
  ## image handle is invalid.
  let (iw, ih, ok) = c.imageSize(id)
  if not ok or iw <= 0 or ih <= 0:
    return false
  let scale = max(photoSize / float64(iw), photoSize / float64(ih))
  let dw = float64(iw) * scale
  let dh = float64(ih) * scale
  let ox = x + (photoSize - dw) * 0.5
  let oy = y + (photoSize - dh) * 0.5
  c.beginPath()
  c.roundedRect(x, y, photoSize, photoSize, photoRadius)
  c.setFillPaint(c.imagePattern(ox, oy, dw, dh, 0.0, id, 1.0))
  c.fill()
  true

proc titleOpts(th: OgTheme, contentW: float64): TextBoxOpts =
  TextBoxOpts(maxW: contentW, boxH: 260.0, ha: th.align,
    va: tvaTop, wrap: true, overflow: toEllipsis, fit: tfNone,
    maxLines: th.titleMaxLines, ellipsis: "...")

proc descOpts(th: OgTheme, contentW: float64): TextBoxOpts =
  TextBoxOpts(maxW: contentW, boxH: 100.0, ha: th.align,
    va: tvaTop, wrap: true, overflow: toEllipsis, fit: tfNone,
    maxLines: th.descMaxLines, ellipsis: "...")

proc isSpaceRune(r: Rune): bool =
  let v = uint32(r)
  v == 32u32 or v == 10u32 or v == 9u32

proc ellipsizeToLines*(c: Canvas, s: string,
    o: TextBoxOpts): string =
  ## Trim `s` with the `o.ellipsis` marker so the unclamped layout
  ## fits `o.maxLines` lines. nvg's `toEllipsis` only trims
  ## over-wide lines, not lines dropped by `maxLines` clamping, so
  ## pre-trim here. Call with the canvas font/size/line-height
  ## already set, matching the following `fillTextBox` call.
  ## Returns `s` unchanged when it already fits or no clamp applies.
  if o.maxLines <= 0 or s == "":
    return s
  var probe = o
  probe.maxLines = 0
  if c.measureTextBox(0, 0, s, probe).lineCount <= o.maxLines:
    return s
  let runes = s.toRunes()
  var lo = 0
  var hi = runes.len
  while lo < hi:
    let mid = (lo + hi + 1) div 2
    let trial = $runes[0 ..< mid] & o.ellipsis
    if c.measureTextBox(0, 0, trial, probe).lineCount <= o.maxLines:
      lo = mid
    else:
      hi = mid - 1
  var cut = lo
  if cut < runes.len and cut > 0 and not isSpaceRune(runes[cut]):
    var b = cut - 1
    while b >= 0 and not isSpaceRune(runes[b]):
      dec b
    if b > 0:
      cut = b
  while cut > 0 and isSpaceRune(runes[cut - 1]):
    dec cut
  if cut <= 0:
    return o.ellipsis
  $runes[0 ..< cut] & o.ellipsis

proc drawBadge(c: Canvas, og: OgImage, th: OgTheme, bodyId: int,
    contentX, contentW: float64): float64 =
  ## Returns the y the title should start at.
  if og.content.badge == "":
    return if th.centered: 150.0 else: 110.0
  c.setFontFaceId(bodyId)
  c.setFontSize(th.badgeSize)
  c.setLineHeight(1.2)
  let m = c.measureTextBox(0, 0, og.content.badge, TextBoxOpts(
    maxW: contentW, boxH: 44.0, ha: thaLeft, va: tvaTop,
    wrap: false, overflow: toEllipsis, fit: tfNone, maxLines: 1,
    ellipsis: "..."))
  let pillW = min(contentW, m.advance + 48.0)
  const pillH = 44.0
  const pillY = 64.0
  var pillX = contentX
  if th.centered:
    pillX = contentX + (contentW - pillW) * 0.5
  c.beginPath()
  c.roundedRect(pillX, pillY, pillW, pillH, pillH * 0.5)
  c.setFillColor(th.badgeBg)
  c.fill()
  c.setFillColor(th.badgeColor)
  discard c.fillTextBox(pillX, pillY, og.content.badge, TextBoxOpts(
    maxW: pillW, boxH: pillH, ha: thaCenter, va: tvaMiddle,
    wrap: false, overflow: toEllipsis, fit: tfNone, maxLines: 1,
    ellipsis: "..."))
  pillY + pillH + 22.0

proc drawFooter(c: Canvas, og: OgImage, th: OgTheme, bodyId: int,
    contentX, contentW: float64) =
  ## Bottom row of icon + label items (handles, counters, captions)
  ## composed with NVG flex rows: each item is an optional fitted
  ## icon box plus its label, items separated by a wider gap, the
  ## whole row aligned per `th.align`. The icon variant follows the
  ## preset brightness; a missing file draws a placeholder box, an
  ## empty path draws the label alone. Without items the plain
  ## `site` label renders instead.
  const boxH = 36.0
  const iconGap = 10.0
  const itemGap = 28.0
  let footerY = float64(og.height) - th.padding - 30.0
  c.setFontFaceId(bodyId)
  c.setFontSize(th.siteSize)
  c.setLineHeight(1.2)
  c.setFillColor(th.siteColor)
  # One shared baseline for every item: rows with icon boxes lay
  # out taller ink than text-only rows, so top-anchoring each row
  # seats them on different baselines. Anchoring to the baseline
  # keeps all labels on one line; the probe ("Ag" covers ascender
  # and descender) recovers the baseline that puts ink top at
  # footerY.
  let probe = c.textSpanBounds(0, 0, "Ag", newSeq[TextSpan](0),
    TextBoxOpts(maxW: contentW, boxH: boxH, ha: thaLeft,
      va: tvaBaseline, wrap: false, overflow: toVisible,
      fit: tfNone, maxLines: 1, ellipsis: "..."))
  let baseY = footerY - probe.y
  if og.content.footer.len == 0:
    if og.content.site == "":
      return
    discard c.fillTextBox(contentX, baseY, og.content.site,
      TextBoxOpts(maxW: contentW, boxH: boxH, ha: th.align,
        va: tvaBaseline, wrap: false, overflow: toEllipsis,
        fit: tfNone, maxLines: 1, ellipsis: "..."))
    return
  let iconS = th.siteSize * 1.2
  var iconIds: seq[int] = @[]
  var slots: seq[bool] = @[]
  var labels: seq[string] = @[]
  var labelWs: seq[float64] = @[]
  for it in og.content.footer:
    let p = if th.onDark: it.iconDark
      elif it.iconLight != "": it.iconLight
      else: it.iconDark
    var id = 0
    var slot = false
    if p != "":
      slot = true
      id = c.createFittedImage(p, iconS, iconS)
    let m = c.measureTextBox(0, 0, it.label, TextBoxOpts(
      maxW: contentW, boxH: boxH, ha: thaLeft, va: tvaTop,
      wrap: false, overflow: toEllipsis, fit: tfNone, maxLines: 1,
      ellipsis: "..."))
    iconIds.add(id)
    slots.add(slot)
    labels.add(it.label)
    labelWs.add(m.advance)
  var totalW = itemGap * float64(max(0, labels.len - 1))
  for i in 0 ..< labels.len:
    totalW += labelWs[i]
    if slots[i]:
      totalW += iconS + iconGap
  if totalW > contentW and labelWs.len > 0:
    # Icons and gaps are fixed; the last label absorbs overflow.
    var fixedW = totalW - labelWs[^1]
    labelWs[^1] = max(0.0, contentW - fixedW)
    totalW = fixedW + labelWs[^1]
  var x = contentX
  case th.align
  of thaCenter:
    x = contentX + (contentW - totalW) * 0.5
  of thaRight:
    x = contentX + contentW - totalW
  else:
    discard
  let iy = baseY + (probe.y + probe.h * 0.5) - iconS * 0.5
  for i in 0 ..< labels.len:
    c.setFillColor(th.siteColor)
    if slots[i]:
      if iconIds[i] != 0:
        let (iw, ih, ok) = c.imageSize(iconIds[i])
        if ok and iw > 0 and ih > 0:
          # Inline flex pair: the icon box rides the label's text
          # ink center, so multi-item rows stay glued per item.
          let row = "\uFFFC " & labels[i]
          let spans = [TextSpan(first: 0, last: 3,
            box: SpanBox(kind: sbkImage, imageId: iconIds[i],
              imageW: float64(iw), imageH: float64(ih)),
            alignSelf: faCenter, size: iconS)]
          discard c.fillSpanBox(x, baseY, row, spans,
            TextBoxOpts(maxW: iconS + iconGap + labelWs[i],
              boxH: boxH, ha: thaLeft, va: tvaBaseline, wrap: false,
              overflow: toEllipsis, fit: tfNone, maxLines: 1,
              ellipsis: "...",
              flex: TextRowFlex(gap: iconGap)))
          x += iconS + iconGap + labelWs[i] + itemGap
          continue
      c.drawPlaceholder(bodyId, x, iy, iconS, iconS, 6.0)
      discard c.fillTextBox(x + iconS + iconGap, baseY, labels[i],
        TextBoxOpts(maxW: labelWs[i], boxH: boxH, ha: thaLeft,
          va: tvaBaseline, wrap: false, overflow: toEllipsis,
          fit: tfNone, maxLines: 1, ellipsis: "..."))
      x += iconS + iconGap + labelWs[i] + itemGap
    else:
      discard c.fillTextBox(x, baseY, labels[i],
        TextBoxOpts(maxW: labelWs[i], boxH: boxH, ha: thaLeft,
          va: tvaBaseline, wrap: false, overflow: toEllipsis,
          fit: tfNone, maxLines: 1, ellipsis: "..."))
      x += labelWs[i] + itemGap

proc render*(og: OgImage): Canvas =
  ## Rasterize `og` into a fresh `Canvas`. Raises `OgError` on bad
  ## dimensions or when no font resolves.
  if og.width <= 0 or og.height <= 0:
    raise newException(OgError, "ogimage: width and height must be positive")
  var th = themeForPreset(og.preset, og.accent, og.hasAccent)
  if og.hasAlign:
    th.align = og.align
  let s = if og.scale > 0.0: og.scale else: 1.0
  let c = newCanvas(max(1, int(float64(og.width) * s + 0.5)),
    max(1, int(float64(og.height) * s + 0.5)))
  c.setPixelRatio(s)
  if s != 1.0:
    c.scale(s, s)
  let (titleId, bodyId) = ensureFonts(c, og)
  c.ensureFallbacks(og.fallbackFontPaths)

  drawBackground(c, og, th)

  var contentX = th.padding
  var contentW = float64(og.width) - th.padding * 2.0

  if og.content.photoPath == "":
    drawLogo(c, og, th, bodyId)

  let titleY = drawBadge(c, og, th, bodyId, contentX, contentW)

  var titleX = contentX
  var titleW = contentW
  if og.content.photoPath != "":
    let photoX = contentX + contentW - photoSize
    titleW = contentW - photoSize - photoGap
    let photoId = c.createImageFile(og.content.photoPath, {})
    if photoId == 0 or not c.drawPhoto(photoId, photoX, titleY):
      c.drawPlaceholder(bodyId, photoX, titleY, photoSize,
        photoSize, photoRadius)

  if og.content.titleSegs.len > 0:
    discard c.drawSegText(og, th, og.content.titleSegs, titleId,
      resolveTitlePath(og), og.titleFaceIndex, th.titleColor,
      th.titleSize, 1.12, titleX, titleY, titleW, 260.0,
      th.titleMaxLines)
  elif og.content.title != "":
    c.setFontFaceId(titleId)
    c.setFontSize(th.titleSize)
    c.setLineHeight(1.12)
    c.setTextAlign(th.align, tvaTop)
    c.setFillColor(th.titleColor)
    let title = c.ellipsizeToLines(og.content.title,
      titleOpts(th, titleW))
    discard c.fillTextBox(titleX, titleY, title,
      titleOpts(th, titleW))

  if og.content.descSegs.len > 0:
    let bodyFace = if og.fontBodyPath != "": og.bodyFaceIndex
      else: og.titleFaceIndex
    discard c.drawSegText(og, th, og.content.descSegs, bodyId,
      resolveBodyPath(og), bodyFace, th.descColor, th.descSize, 1.4,
      contentX, titleY + 272.0, contentW, 100.0, th.descMaxLines)
  elif og.content.description != "":
    c.setFontFaceId(bodyId)
    c.setFontSize(th.descSize)
    c.setLineHeight(1.4)
    c.setTextAlign(th.align, tvaTop)
    c.setFillColor(th.descColor)
    let desc = c.ellipsizeToLines(og.content.description,
      descOpts(th, contentW))
    discard c.fillTextBox(contentX, titleY + 272.0, desc,
      descOpts(th, contentW))

  drawFooter(c, og, th, bodyId, contentX, contentW)
  result = c

proc savePng*(og: OgImage, path: string) =
  ## Render and write a PNG file.
  render(og).savePng(path)

proc encodePng*(og: OgImage): seq[uint8] =
  ## Render and return PNG bytes.
  render(og).encodePng()
