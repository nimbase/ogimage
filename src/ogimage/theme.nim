## Named presets resolving to fixed-size `OgTheme` values.
##
## All sizes are fixed by design: title and description boxes use
## `toEllipsis` with a line clamp, never `tfShrink`.

import ./types

export types

proc defaultAccent*(preset: OgPreset): Color =
  case preset
  of opDark: rgb(56, 189, 248)
  of opLight: rgb(37, 99, 235)
  of opGradient: rgb(56, 189, 248)
  of opPhoto: rgb(56, 189, 248)
  of opMinimal: rgb(15, 23, 42)
  of opBrand: rgb(56, 189, 248)

proc themeForPreset*(preset: OgPreset, accent: Color,
    hasAccent: bool): OgTheme =
  ## Resolve concrete colors and sizes for `preset`. A custom
  ## `accent` overrides the bar, badge and brand-gradient stops.
  let ac = if hasAccent: accent else: defaultAccent(preset)
  case preset
  of opDark:
    OgTheme(titleSize: 76.0, descSize: 30.0, badgeSize: 20.0,
      siteSize: 24.0, titleColor: rgb(255, 255, 255),
      descColor: rgb(148, 163, 184),
      badgeBg: rgbaf(1, 1, 1, 0.1), badgeColor: rgb(255, 255, 255),
      siteColor: rgb(148, 163, 184), pageBg: rgb(11, 15, 25),
      accent: ac, align: thaLeft, padding: 80.0, radius: 24.0,
      titleMaxLines: 3, descMaxLines: 2, onDark: true,
      centered: false)
  of opLight:
    OgTheme(titleSize: 76.0, descSize: 30.0, badgeSize: 20.0,
      siteSize: 24.0, titleColor: rgb(15, 23, 42),
      descColor: rgb(71, 85, 105),
      badgeBg: rgbaf(0, 0, 0, 0.06), badgeColor: rgb(15, 23, 42),
      siteColor: rgb(100, 116, 139), pageBg: rgb(255, 255, 255),
      accent: ac, align: thaLeft, padding: 80.0, radius: 24.0,
      titleMaxLines: 3, descMaxLines: 2, onDark: false,
      centered: false)
  of opGradient:
    OgTheme(titleSize: 76.0, descSize: 30.0, badgeSize: 20.0,
      siteSize: 24.0, titleColor: rgb(255, 255, 255),
      descColor: rgbaf(1, 1, 1, 0.82),
      badgeBg: rgbaf(1, 1, 1, 0.18), badgeColor: rgb(255, 255, 255),
      siteColor: rgbaf(1, 1, 1, 0.75), pageBg: rgb(30, 27, 75),
      accent: ac, align: thaLeft, padding: 80.0, radius: 24.0,
      titleMaxLines: 3, descMaxLines: 2, onDark: true,
      centered: false)
  of opPhoto:
    OgTheme(titleSize: 76.0, descSize: 30.0, badgeSize: 20.0,
      siteSize: 24.0, titleColor: rgb(255, 255, 255),
      descColor: rgbaf(1, 1, 1, 0.85),
      badgeBg: rgbaf(1, 1, 1, 0.18), badgeColor: rgb(255, 255, 255),
      siteColor: rgbaf(1, 1, 1, 0.8), pageBg: rgb(11, 15, 25),
      accent: ac, align: thaLeft, padding: 80.0, radius: 24.0,
      titleMaxLines: 3, descMaxLines: 2, onDark: true,
      centered: false)
  of opMinimal:
    OgTheme(titleSize: 68.0, descSize: 28.0, badgeSize: 20.0,
      siteSize: 24.0, titleColor: rgb(15, 23, 42),
      descColor: rgb(71, 85, 105),
      badgeBg: rgbaf(0, 0, 0, 0.06), badgeColor: rgb(15, 23, 42),
      siteColor: rgb(100, 116, 139), pageBg: rgb(248, 250, 252),
      accent: ac, align: thaCenter, padding: 90.0, radius: 24.0,
      titleMaxLines: 3, descMaxLines: 2, onDark: false,
      centered: true)
  of opBrand:
    OgTheme(titleSize: 72.0, descSize: 29.0, badgeSize: 20.0,
      siteSize: 24.0, titleColor: rgb(255, 255, 255),
      descColor: rgbaf(1, 1, 1, 0.82),
      badgeBg: rgbaf(1, 1, 1, 0.18), badgeColor: rgb(255, 255, 255),
      siteColor: rgbaf(1, 1, 1, 0.75), pageBg: rgb(17, 24, 39),
      accent: ac, align: thaCenter, padding: 90.0, radius: 24.0,
      titleMaxLines: 3, descMaxLines: 2, onDark: true,
      centered: true)
