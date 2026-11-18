## Composable rows/columns computing absolute positions.
##
## The preset renderer lays out fixed boxes by hand; this module
## packages that arithmetic so custom cards can do the same: split
## a box into a row or a column, inset padding, then draw each cell
## with direct `nvg` calls. Spans (`ogimage/spans`) are the Layer-0
## text primitive; nothing here runs at draw time, positions are
## plain floats (nvg has layouting but absolute is faster for now).

import nvg

type
  OgBox* = object
    ## An absolute rect in user units: origin plus size.
    x*, y*, w*, h*: float64

proc ogBox*(x, y, w, h: float64): OgBox =
  ## One explicitly placed rect.
  OgBox(x: x, y: y, w: w, h: h)

proc inset*(b: OgBox, pad: float64): OgBox =
  ## Shrink `b` by `pad` on all four sides.
  OgBox(x: b.x + pad, y: b.y + pad,
    w: max(0.0, b.w - pad * 2.0), h: max(0.0, b.h - pad * 2.0))

proc inset*(b: OgBox, dx, dy: float64): OgBox =
  ## Shrink `b` by `dx` horizontally and `dy` vertically.
  OgBox(x: b.x + dx, y: b.y + dy,
    w: max(0.0, b.w - dx * 2.0), h: max(0.0, b.h - dy * 2.0))

proc splitRow*(b: OgBox, widths: openArray[float64],
    gap = 0.0): seq[OgBox] =
  ## Carve `b` into a left-to-right row of absolute `widths`.
  ## Cells keep full height; leftover space stays empty on the
  ## right and overflow is the caller's problem.
  result = @[]
  var x = b.x
  for w in widths:
    result.add(OgBox(x: x, y: b.y, w: w, h: b.h))
    x += w + gap

proc splitRowFlex*(b: OgBox, weights: openArray[float64],
    gap = 0.0): seq[OgBox] =
  ## Like `splitRow` but widths share the available space
  ## proportionally to `weights`. Non-positive totals split evenly.
  var total = 0.0
  for wt in weights:
    total += wt
  let n = weights.len
  var avail = b.w - gap * float64(max(0, n - 1))
  if avail < 0.0:
    avail = 0.0
  result = @[]
  var x = b.x
  for wt in weights:
    let w = if total > 0.0: avail * wt / total
      else: avail / float64(max(1, n))
    result.add(OgBox(x: x, y: b.y, w: w, h: b.h))
    x += w + gap

proc splitColumn*(b: OgBox, heights: openArray[float64],
    gap = 0.0): seq[OgBox] =
  ## Carve `b` into a top-to-bottom column of absolute `heights`.
  ## Cells keep full width; leftover space stays empty at the
  ## bottom.
  result = @[]
  var y = b.y
  for h in heights:
    result.add(OgBox(x: b.x, y: y, w: b.w, h: h))
    y += h + gap

proc splitColumnFlex*(b: OgBox, weights: openArray[float64],
    gap = 0.0): seq[OgBox] =
  ## Like `splitColumn` but heights share the available space
  ## proportionally to `weights`. Non-positive totals split evenly.
  var total = 0.0
  for wt in weights:
    total += wt
  let n = weights.len
  var avail = b.h - gap * float64(max(0, n - 1))
  if avail < 0.0:
    avail = 0.0
  result = @[]
  var y = b.y
  for wt in weights:
    let h = if total > 0.0: avail * wt / total
      else: avail / float64(max(1, n))
    result.add(OgBox(x: b.x, y: y, w: b.w, h: h))
    y += h + gap

proc newCustomCanvas*(w, h: int, scale = 1.0): Canvas =
  ## A blank canvas in `w`x`h` user units at `scale` pixel ratio
  ## (2.0 = retina), mirroring `render` setup without any preset
  ## layout. Draw with direct `nvg` calls, then `savePng`.
  let s = if scale > 0.0: scale else: 1.0
  result = newCanvas(max(1, int(float64(w) * s + 0.5)),
    max(1, int(float64(h) * s + 0.5)))
  result.setPixelRatio(s)
  if s != 1.0:
    result.scale(s, s)
