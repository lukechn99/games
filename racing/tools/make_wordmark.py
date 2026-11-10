"""Build approved lettering B as SVG outlines from the game's OFL fonts.
Run from the repository root: python3 racing/tools/make_wordmark.py
Requires fontTools with WOFF2 support. No runtime font download is needed.
"""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen

ROOT = Path(__file__).resolve().parents[2]

def word(text, font_name, size, x, baseline, fill, stroke='none'):
    font = TTFont(ROOT / 'racing/assets/fonts' / (font_name + '.woff2'))
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font['head'].unitsPerEm
    parts = []
    for char in text:
        name = cmap[ord(char)]
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(pen)
        parts.append(f'<path transform="translate({x:.3f} {baseline}) scale({scale:.6f} {-scale:.6f})" d="{pen.getCommands()}"/>')
        x += glyphs[name].width * scale
    return f'<g fill="{fill}" stroke="{stroke}" stroke-width="2" paint-order="stroke" stroke-linejoin="round">' + ''.join(parts) + '</g>', x

animal, end = word('Animal', 'lilita_one', 86, 16, 108, '#246bdb')
karts, end = word('KARTS', 'black_ops_one', 76, end + 14, 108, '#ffc928', '#162842')
# Scale the outline stroke in screen space, independently of glyph units.
karts = karts.replace('<path ', '<path vector-effect="non-scaling-stroke" ')
svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {end+22:.1f} 150" role="img" aria-label="Animal Karts"><title>Animal Karts</title><g transform="rotate(-3 {end/2:.1f} 75)">{animal}{karts}</g></svg>\n'
output = ROOT / 'public/branding/animal-karts.svg'
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(svg)
print(output.relative_to(ROOT))
