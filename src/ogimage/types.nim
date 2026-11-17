## Shared value types for the ogimage library.
##
## `OgImage` is the single input object: content plus presentation.
## Rendering lives in `ogimage/render`; presets in `ogimage/theme`.

import nvg

export nvg

type
  OgPreset* = enum
    opDark
      ## Dark card, light text, accent bar.
    opLight
      ## White card, dark ink.
    opGradient
      ## Full-bleed brand gradient, white ink.
    opPhoto
      ## Background photo with a dark overlay, white ink.
    opMinimal
      ## Centered, quiet, thin divider instead of an accent bar.
    opBrand
      ## Accent-driven gradient, white ink, centered.

  OgBackgroundKind* = enum
    bgSolid
    bgGradient
    bgImage

  OgBackground* = object
    ## Explicit background override. When `kind` is `bgImage` but
    ## `path` is empty or undecodable, render falls back to the
    ## preset solid.
    case kind*: OgBackgroundKind
    of bgSolid:
      color*: Color
    of bgGradient:
      fromColor*: Color
      toColor*: Color
      angleDeg*: float64
    of bgImage:
      path*: string
      tint*: Color
      overlayAlpha*: float64

  OgContent* = object
    title*: string
    description*: string
    badge*: string
      ## Small pill above the title. Empty hides it.
    site*: string
      ## Plain footer label, e.g. "nimbase.dev". Empty hides it.
      ## Ignored when `repo` is set.
    repo*: string
      ## Repo handle footer, e.g. "@nimbase/ogimage", drawn with the
      ## `repoIconDark`/`repoIconLight` mark. Empty hides it.
    logoPath*: string
      ## Optional square-ish logo drawn in the top-right corner.
      ## Empty skips it, as does a set `photoPath` (the photo owns
      ## the right side).
    photoPath*: string
      ## Optional photo drawn as a `photoRadius` rounded square avatar
      ## sharing the headline row (like a profile pic). The
      ## description below keeps the full width. Empty or
      ## undecodable paths fall back to the full-width layout.

  OgTheme* = object
    ## Resolved drawing parameters for one render. Build with
    ## `themeForPreset`; fields are fixed sizes because body text
    ## uses ellipsis, never auto-shrink.
    titleSize*: float64
    descSize*: float64
    badgeSize*: float64
    siteSize*: float64
    onDark*: bool
      ## True when the preset background is dark (picks the light
      ## repo icon variant).
    titleColor*: Color
    descColor*: Color
    badgeBg*: Color
    badgeColor*: Color
    siteColor*: Color
    pageBg*: Color
      ## Fallback page color under photos/gradients.
    accent*: Color
    align*: TextHAlign
    padding*: float64
    radius*: float64
    titleMaxLines*: int
    descMaxLines*: int
    centered*: bool

  OgImage* = object
    width*: int
    height*: int
    content*: OgContent
    background*: OgBackground
    hasBackground*: bool
      ## When false the preset default background is used.
    preset*: OgPreset
    accent*: Color
    hasAccent*: bool
      ## When false the preset default accent is used.
    align*: TextHAlign
    hasAlign*: bool
      ## When true, overrides the preset alignment (e.g. `thaRight`
      ## for RTL text). Otherwise the preset alignment is used.
    scale*: float64
      ## Output scale factor (1.0 = 1200x630 px, 2.0 = retina
      ## 2400x1260 px). Layout stays in `width`x`height` user units.
      ## Values <= 0 fall back to 1.0.
    fontTitlePath*: string
      ## Empty resolves via `resolveTitleFont`.
    fontBodyPath*: string
      ## Empty falls back to the title font.
    fallbackFontPaths*: seq[string]
      ## Optional fallback faces for glyphs missing from the title
      ## or body font. Tried in order; unknown files are skipped.
      ## Same-direction scripts only: mixed-direction text (e.g.
      ## Hebrew + Latin) needs a single covering font instead, since
      ## fallback runs shape in logical order.
    repoIconDark*: string
      ## GitHub-style mark drawn on dark presets with `repo`.
      ## Empty draws the handle without an icon.
    repoIconLight*: string
      ## GitHub-style mark drawn on light presets with `repo`.
      ## Empty draws the handle without an icon.
    titleFaceIndex*: int
    bodyFaceIndex*: int

  OgError* = object of CatchableError

proc solidBackground*(c: Color): OgBackground =
  OgBackground(kind: bgSolid, color: c)

proc gradientBackground*(fromColor, toColor: Color,
    angleDeg = 135.0): OgBackground =
  OgBackground(kind: bgGradient, fromColor: fromColor, toColor: toColor,
    angleDeg: angleDeg)

proc imageBackground*(path: string, overlayAlpha = 0.55,
    tint = rgbf(0, 0, 0)): OgBackground =
  OgBackground(kind: bgImage, path: path, tint: tint,
    overlayAlpha: overlayAlpha)

proc newOgImage*(title, description: string,
    preset = opDark): OgImage =
  ## Minimal constructor with standard 1200x630 dimensions.
  OgImage(width: 1200, height: 630,
    content: OgContent(title: title, description: description),
    preset: preset, accent: rgbf(0, 0, 0), hasAccent: false,
    hasBackground: false, titleFaceIndex: 0, bodyFaceIndex: 0)
