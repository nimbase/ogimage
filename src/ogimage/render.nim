## Layout and rasterization of `OgImage` via `nvg`.
##
## Fixed layout grid on 1200x630: badge, title box (ellipsis,
## 3 lines), description box (ellipsis, 2 lines), footer row.
## Text never auto-shrinks; overflow trims with "..." instead.

import std/math
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

proc drawImageCover(c: Canvas, id: int, W, H: float64) =
  ## Stretch `id` over the full canvas. Clamp sampling extends edge
  ## texels outside the tile, which reads as a cover fit.
  let (iw, ih, ok) = c.imageSize(id)
  if not ok or iw <= 0 or ih <= 0:
    return
  let scale = max(W / float64(iw), H / float64(ih))
  let dw = float64(iw) * scale
  let dh = float64(ih) * scale
  let ox = (W - dw) * 0.5
  let oy = (H - dh) * 0.5
  c.beginPath()
  c.rect(0, 0, W, H)
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
          drawImageCover(c, id, W, H)
          c.beginPath()
          c.rect(0, 0, W, H)
          c.setFillColor(og.background.tint.withAlpha(
            og.background.overlayAlpha))
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

proc drawDecor(c: Canvas, og: OgImage, th: OgTheme) =
  ## Two translucent glow discs; deterministic, no randomness.
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
  ## Bottom row: `repo` handle with its GitHub-style mark, or the
  ## plain `site` label when no repo is set. The mark variant
  ## follows the preset brightness; a missing file draws the handle
  ## without an icon.
  let footerY = float64(og.height) - th.padding - 30.0
  c.setFontFaceId(bodyId)
  c.setFontSize(th.siteSize)
  c.setLineHeight(1.2)
  c.setFillColor(th.siteColor)
  if og.content.repo == "":
    if og.content.site == "":
      return
    discard c.fillTextBox(contentX, footerY, og.content.site,
      TextBoxOpts(maxW: contentW, boxH: 36.0, ha: th.align,
        va: tvaTop, wrap: false, overflow: toEllipsis, fit: tfNone,
        maxLines: 1, ellipsis: "..."))
    return
  let iconS = th.siteSize * 1.2
  const iconGap = 10.0
  let iconPath = if th.onDark: og.repoIconDark else: og.repoIconLight
  var iconId = 0
  if iconPath != "":
    iconId = c.createFittedImage(iconPath, iconS, iconS)
  if iconPath == "":
    discard c.fillTextBox(contentX, footerY, og.content.repo,
      TextBoxOpts(maxW: contentW, boxH: 36.0, ha: th.align,
        va: tvaTop, wrap: false, overflow: toEllipsis, fit: tfNone,
        maxLines: 1, ellipsis: "..."))
    return
  let m = c.measureTextBox(0, 0, og.content.repo, TextBoxOpts(
    maxW: contentW, boxH: 36.0, ha: thaLeft, va: tvaTop,
    wrap: false, overflow: toEllipsis, fit: tfNone, maxLines: 1,
    ellipsis: "..."))
  let textW = min(m.advance, contentW - iconS - iconGap)
  let totalW = textW + iconS + iconGap
  var startX = contentX
  case th.align
  of thaCenter:
    startX = contentX + (contentW - totalW) * 0.5
  of thaRight:
    startX = contentX + contentW - totalW
  else:
    discard
  let iy = footerY + (36.0 - iconS) * 0.5
  if iconId != 0:
    c.beginPath()
    c.rect(startX, iy, iconS, iconS)
    c.setFillPaint(c.imagePattern(startX, iy, iconS, iconS, 0.0,
      iconId, 1.0))
    c.fill()
  else:
    c.drawPlaceholder(bodyId, startX, iy, iconS, iconS, 6.0)
  c.setFillColor(th.siteColor)
  discard c.fillTextBox(startX + iconS + iconGap, footerY,
    og.content.repo, TextBoxOpts(maxW: textW, boxH: 36.0,
      ha: thaLeft, va: tvaTop, wrap: false, overflow: toEllipsis,
      fit: tfNone, maxLines: 1, ellipsis: "..."))

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
  drawDecor(c, og, th)

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

  if og.content.title != "":
    c.setFontFaceId(titleId)
    c.setFontSize(th.titleSize)
    c.setLineHeight(1.12)
    c.setTextAlign(th.align, tvaTop)
    c.setFillColor(th.titleColor)
    let title = c.ellipsizeToLines(og.content.title,
      titleOpts(th, titleW))
    discard c.fillTextBox(titleX, titleY, title,
      titleOpts(th, titleW))

  if og.content.description != "":
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
