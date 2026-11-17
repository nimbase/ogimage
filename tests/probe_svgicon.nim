import ogimage

var og = newOgImage("T", "D")
og.fontTitlePath = "tests/data/Roboto-Bold.ttf"
og.fontBodyPath = "tests/data/Roboto-Regular.ttf"
og.content.repo = "@nimbase/ogimage"
og.repoIconDark = "tests/data/brand-github.svg"
og.repoIconLight = "tests/data/brand-github.svg"
og.savePng("/tmp/og_svg.png")
echo "saved svg-icon render"
