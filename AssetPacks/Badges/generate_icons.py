import math, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'icons')
FONT = "Arial Black, Arial, Helvetica, sans-serif"


def T(x, y, size, txt, fill='#fff', font=FONT, weight=900, shadow=None):
    s = ''
    if shadow:
        s += f'<text x="{x+2}" y="{y+3}" font-family="{font}" font-weight="{weight}" font-size="{size}" text-anchor="middle" fill="{shadow}" opacity=".45">{txt}</text>'
    return s + f'<text x="{x}" y="{y}" font-family="{font}" font-weight="{weight}" font-size="{size}" text-anchor="middle" fill="{fill}">{txt}</text>'


BIKE = ('<g fill="none" stroke="{c}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round">'
        '<circle cx="86" cy="158" r="30"/><circle cx="170" cy="158" r="30"/>'
        '<path d="M86 158 L122 158 L110 112 Z M110 112 L158 116 L122 158 M158 116 L170 158 M158 116 L154 102 L168 100 M98 106 L120 106"/></g>')


def bike(x, y, s, c='#fff', w=7):
    return f'<g transform="translate({x} {y}) scale({s}) translate(-128 -144)">' + BIKE.format(c=c, w=w) + '</g>'


SHOE = ('<path d="M64 150 L66 112 C67 104 76 102 82 108 L98 124 C118 132 150 136 178 142 C194 146 196 162 184 166 L72 166 C66 166 64 160 64 150 Z" fill="{c}"/>'
        '<path d="M64 156 L196 156 L194 160 C192 166 186 168 180 168 L72 168 C66 168 64 164 64 156Z" fill="{sole}"/>'
        '<path d="M100 128 l10 -10 M112 132 l10 -10 M124 135 l10 -10" stroke="{sole}" stroke-width="4" stroke-linecap="round"/>')


def shoe(x, y, s, c='#fff', sole='#fab005'):
    return f'<g transform="translate({x} {y}) scale({s}) translate(-130 -135)">' + SHOE.format(c=c, sole=sole) + '</g>'


def laurel(color, r=86, n=9, start=105, step=15):
    out = []
    for side in (1, -1):
        for i in range(n):
            a = math.radians(start + i * step)
            x = 128 + r * math.cos(a)
            y = 128 + r * math.sin(a)
            rot = math.degrees(a) + 90 + (25 if i % 2 else -25)
            off = 7 if i % 2 else -7
            x += off * math.cos(a)
            y += off * math.sin(a)
            if side == -1:
                x = 256 - x
                rot = 180 - rot
            out.append(f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="10" ry="4.5" transform="rotate({rot:.1f} {x:.1f} {y:.1f})" fill="{color}"/>')
    return ''.join(out)


def stars(pts, color='#fff'):
    return ''.join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{color}" opacity=".85"/>' for x, y, r in pts)


def flake(x, y, r, c='#fff'):
    lines = ''
    for a in (0, 60, 120):
        lines += f'<line x1="{x}" y1="{y-r}" x2="{x}" y2="{y+r}" transform="rotate({a} {x} {y})"/>'
    return f'<g stroke="{c}" stroke-width="2.5" stroke-linecap="round">{lines}</g>'


def badge(fname, ring, bg, body):
    def grad(id_, stops, x2='1', y2='1'):
        n = len(stops)
        st = ''.join(f'<stop offset="{i/(n-1):.2f}" stop-color="{c}"/>' for i, c in enumerate(stops))
        return f'<linearGradient id="{id_}" x1="0" y1="0" x2="{x2}" y2="{y2}">{st}</linearGradient>'
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
<defs>{grad('ring', ring)}{grad('bg', bg, '0', '1')}
<clipPath id="clip"><circle cx="128" cy="128" r="108"/></clipPath></defs>
<circle cx="128" cy="128" r="126" fill="url(#ring)"/>
<circle cx="128" cy="128" r="126" fill="none" stroke="#000" stroke-opacity=".18" stroke-width="2"/>
<circle cx="128" cy="128" r="114" fill="#fff"/>
<circle cx="128" cy="128" r="108" fill="url(#bg)"/>
<g clip-path="url(#clip)">{body}</g>
<circle cx="128" cy="128" r="108" fill="none" stroke="#000" stroke-opacity=".15" stroke-width="2"/>
<path d="M30 92 A104 104 0 0 1 92 30" fill="none" stroke="#fff" stroke-opacity=".35" stroke-width="5" stroke-linecap="round"/>
</svg>'''
    with open(os.path.join(OUT, fname), 'w') as f:
        f.write(svg)


GOLD = ['#ffe066', '#f08c00']

# 1. 100!
badge('100.svg', GOLD, ['#ffa94d', '#e8590c'],
      T(128, 120, 62, '100!', shadow='#7a2e00') + T(128, 146, 18, 'KM', fill='#fff3bf') + bike(128, 186, .5))

# 2. Century
badge('century.svg', GOLD, ['#c2255c', '#5c0f2b'],
      laurel('#ffd43b') +
      T(128, 140, 92, 'C', fill='#ffd43b', font='Georgia, Times New Roman, serif', weight=700, shadow='#2b0614') +
      T(128, 168, 16, '100 MILES', fill='#fff') + bike(128, 196, .32, '#ffd43b', 9))

# 3. Hollander
tulips = ''.join(
    f'<line x1="{x}" y1="{y}" x2="{x}" y2="{y+14}" stroke="#2b8a3e" stroke-width="3"/><circle cx="{x}" cy="{y}" r="6" fill="{c}"/>'
    for x, y, c in [(54, 206, '#fa5252'), (74, 210, '#fcc419'), (94, 206, '#f783ac'), (114, 210, '#fa5252'),
                    (134, 206, '#fcc419'), (154, 210, '#f783ac'), (174, 206, '#fa5252'), (194, 210, '#fcc419')])
sails = ''.join(
    f'<g transform="rotate({a} 90 108)"><rect x="85" y="60" width="10" height="44" fill="#fff" stroke="#5c3310" stroke-width="2"/>'
    f'<line x1="90" y1="62" x2="90" y2="104" stroke="#5c3310" stroke-width="1.5"/></g>' for a in (20, 110, 200, 290))
badge('hollander.svg', ['#ffa94d', '#d9480f'], ['#4dabf7', '#d0ebff'],
      '<circle cx="186" cy="74" r="16" fill="#ffd43b"/>'
      '<rect x="0" y="160" width="256" height="100" fill="#8ce99a"/>'
      '<rect x="0" y="176" width="256" height="10" fill="#69db7c"/>'
      '<rect x="0" y="186" width="256" height="8" fill="#4dabf7"/>'
      '<rect x="0" y="194" width="256" height="70" fill="#51cf66"/>'
      '<line x1="20" y1="160" x2="236" y2="160" stroke="#fff" stroke-width="2" stroke-dasharray="6 6" opacity=".8"/>'
      '<polygon points="76,162 104,162 98,112 82,112" fill="#a0522d"/>'
      '<polygon points="78,114 102,114 90,98" fill="#5c3310"/>'
      '<rect x="86" y="146" width="8" height="16" rx="4" fill="#5c3310"/>'
      + sails + '<circle cx="90" cy="108" r="4" fill="#5c3310"/>' + tulips + bike(176, 146, .4, '#212529', 9))

# 4. Everester
badge('everester.svg', ['#b197fc', '#5f3dc4'], ['#1c2f6e', '#74c0fc'],
      stars([(50, 70, 1.5), (70, 50, 1.2), (190, 60, 1.5), (210, 90, 1.2), (170, 40, 1)]) +
      '<polygon points="10,240 128,62 246,240" fill="#adb5bd"/>'
      '<polygon points="128,62 246,240 150,240 140,150" fill="#868e96"/>'
      '<polygon points="128,62 156,104 142,98 132,110 120,96 102,104" fill="#fff"/>'
      '<path d="M128 228 L92 200 L160 176 L108 148 L140 122 L124 108" fill="none" stroke="#ffd43b" stroke-width="4" stroke-dasharray="7 5" stroke-linecap="round"/>'
      '<line x1="128" y1="64" x2="128" y2="34" stroke="#343a40" stroke-width="3"/>'
      '<polygon points="128,34 152,41 128,48" fill="#fa5252"/>'
      '<rect x="80" y="196" width="96" height="32" rx="10" fill="#212529" opacity=".75"/>' +
      T(128, 220, 20, '8848 m', fill='#fff'))

# 5. Pretzel
PRETZEL = 'M100 184 C110 160 140 130 158 104 C176 78 210 90 205 125 C200 165 165 196 128 196 C91 196 56 165 51 125 C46 90 80 78 98 104 C116 130 146 160 156 184'
salt = ''.join(f'<rect x="{x}" y="{y}" width="5" height="4" rx="1" fill="#fff" transform="rotate({r} {x} {y})"/>'
               for x, y, r in [(180, 92, 20), (196, 112, -10), (198, 140, 30), (182, 170, 10), (150, 190, -20), (106, 190, 15),
                               (72, 168, -30), (56, 136, 10), (62, 102, 40), (82, 88, -15), (142, 126, 25), (116, 124, -25), (120, 160, 10)])
badge('pretzel.svg', ['#ffd43b', '#e67700'], ['#fff3bf', '#ffc078'],
      f'<g transform="translate(0 -8)"><path d="{PRETZEL}" fill="none" stroke="#6b3410" stroke-width="32" stroke-linecap="round"/>'
      f'<path d="{PRETZEL}" fill="none" stroke="#c46a2b" stroke-width="24" stroke-linecap="round"/>'
      f'<path d="{PRETZEL}" fill="none" stroke="#e8a15c" stroke-width="6" stroke-linecap="round" transform="translate(-3 -4)" opacity=".7"/>'
      + salt + '</g>')

# 6. Nosleep
ticks = ''.join(f'<line x1="128" y1="94" x2="128" y2="{102 if i % 3 == 0 else 99}" stroke="#364fc7" stroke-width="{4 if i % 3 == 0 else 2}" transform="rotate({i*30} 128 140)"/>' for i in range(12))
badge('nosleep.svg', ['#748ffc', '#364fc7'], ['#141833', '#4c3a8a'],
      stars([(52, 110, 1.5), (60, 160, 1.2), (196, 120, 1.5), (204, 170, 1.2), (150, 50, 1.2), (110, 46, 1), (176, 80, 1.5)]) +
      '<circle cx="80" cy="76" r="20" fill="#ffe066"/><circle cx="90" cy="69" r="18" fill="#171b3a"/>'
      '<circle cx="186" cy="62" r="12" fill="#ffa94d"/>' +
      ''.join(f'<line x1="186" y1="44" x2="186" y2="38" stroke="#ffa94d" stroke-width="3" stroke-linecap="round" transform="rotate({a} 186 62)"/>' for a in range(0, 360, 45)) +
      '<circle cx="128" cy="140" r="52" fill="#fff" stroke="#748ffc" stroke-width="6"/>' + ticks +
      '<line x1="128" y1="140" x2="128" y2="106" stroke="#212529" stroke-width="5" stroke-linecap="round"/>'
      '<line x1="128" y1="140" x2="154" y2="140" stroke="#212529" stroke-width="5" stroke-linecap="round"/>'
      '<circle cx="128" cy="140" r="5" fill="#fa5252"/>' + T(128, 172, 15, '24H', fill='#364fc7'))

# 7. Every day I'm hustling
days = 'MTWTFSS'
cells = ''
for i, d in enumerate(days):
    x = 48 + 160 / 7 * (i + .5)
    cells += T(round(x, 1), 128, 12, d, fill='#868e96', font='Arial, Helvetica, sans-serif', weight=700)
    cells += f'<circle cx="{x:.1f}" cy="{152}" r="9" fill="#12b886"/><path d="M{x-4:.1f} 152 l3 3 l5 -6" fill="none" stroke="#fff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>'
badge('every-day-im-hustling.svg', ['#38d9a9', '#087f5b'], ['#c3fae8', '#38d9a9'],
      '<rect x="48" y="74" width="160" height="104" rx="14" fill="#fff"/>'
      '<rect x="48" y="74" width="160" height="34" rx="14" fill="#fa5252"/><rect x="48" y="94" width="160" height="14" fill="#fa5252"/>'
      '<rect x="78" y="66" width="8" height="18" rx="4" fill="#495057"/><rect x="170" y="66" width="8" height="18" rx="4" fill="#495057"/>'
      + T(128, 100, 20, '7 / 7') + cells +
      '<polygon points="196,40 168,94 188,94 176,134 214,74 192,74 206,40" fill="#ffd43b" stroke="#e67700" stroke-width="3" stroke-linejoin="round"/>'
      + T(128, 210, 15, 'NON-STOP', fill='#087f5b'))

# 8. Working 9 to 5
dots = ''
for i in range(7):
    x = 62 + i * 22
    if i < 5:
        dots += f'<circle cx="{x}" cy="200" r="8" fill="#37b24d"/>'
    else:
        dots += f'<circle cx="{x}" cy="200" r="7" fill="none" stroke="#868e96" stroke-width="3"/>'
badge('working-9-to-5.svg', ['#5c7cfa', '#1c2e7a'], ['#fff3bf', '#ffd43b'],
      '<rect x="104" y="70" width="48" height="26" rx="8" fill="none" stroke="#5c3310" stroke-width="8"/>'
      '<rect x="62" y="88" width="132" height="90" rx="14" fill="#a0522d"/>'
      '<rect x="62" y="88" width="132" height="34" rx="14" fill="#b8693a"/>'
      '<rect x="62" y="116" width="132" height="6" fill="#5c3310"/>'
      '<rect x="118" y="110" width="20" height="18" rx="4" fill="#ffd43b" stroke="#e67700" stroke-width="2"/>'
      + T(128, 166, 28, '9-5', fill='#fff', shadow='#3b1d08') + dots)

# 9. Triple jump
lanes = ''.join(f'<path d="M-20 {y} Q128 {y-30} 276 {y}" fill="none" stroke="#fff" stroke-width="2" opacity=".7"/>' for y in (206, 228, 250))
rest = ''.join(f'<circle cx="{x}" cy="170" r="9" fill="#dee2e6" stroke="#adb5bd" stroke-width="2"/>' + T(x, 174, 11, 'z', fill='#868e96', font='Arial, Helvetica, sans-serif', weight=700) for x in (87, 141, 168))
marks = ''.join(f'<circle cx="{x}" cy="170" r="16" fill="{c}" stroke="#fff" stroke-width="3"/>' + T(x, 177, 18, n, fill='#fff')
                for x, c, n in [(60, '#fab005', '1'), (114, '#fd7e14', '2'), (195, '#e03131', '3')])
badge('triple-jump.svg', ['#ff8787', '#c92a2a'], ['#e7f5ff', '#ffffff'],
      '<path d="M-20 190 Q128 162 276 190 V260 H-20Z" fill="#e8590c"/>' + lanes +
      '<path d="M60 152 Q87 80 114 152" fill="none" stroke="#343a40" stroke-width="4" stroke-dasharray="7 6" stroke-linecap="round"/>'
      '<path d="M114 152 Q154 26 195 152" fill="none" stroke="#343a40" stroke-width="4" stroke-dasharray="7 6" stroke-linecap="round"/>'
      + rest + marks)

# 10. Triathlete
badge('triathlete.svg', ['#339af0', '#40c057', '#fd7e14'], ['#f8f9fa', '#dee2e6'],
      '<defs><marker id="ah" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M0 0 L10 5 L0 10Z" fill="#495057"/></marker></defs>'
      '<path d="M96 100 Q82 112 82 120" fill="none" stroke="#495057" stroke-width="4" marker-end="url(#ah)"/>'
      '<path d="M114 176 Q128 184 140 176" fill="none" stroke="#495057" stroke-width="4" marker-end="url(#ah)"/>'
      '<circle cx="128" cy="76" r="36" fill="#228be6"/>'
      '<circle cx="118" cy="70" r="7" fill="#fff"/>'
      '<path d="M104 80 Q124 56 148 72" fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round"/>'
      '<path d="M100 90 q7 -6 14 0 t14 0 t14 0 t14 0" fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round"/>'
      '<circle cx="78" cy="158" r="36" fill="#40c057"/>' + bike(78, 160, .4, '#fff', 9) +
      '<circle cx="178" cy="158" r="36" fill="#fd7e14"/>' + shoe(178, 160, .42, '#fff', '#c2410c'))

# 11. Eddy the Eagle
badge('eddy-the-eagle.svg', ['#74c0fc', '#1864ab'], ['#74c0fc', '#e7f5ff'],
      '<polygon points="0,150 60,96 120,150" fill="#fff" opacity=".7"/><polygon points="140,140 210,80 280,140" fill="#fff" opacity=".7"/>'
      '<polygon points="-10,118 266,226 266,266 -10,266" fill="#f8f9fa"/>'
      '<polygon points="-10,118 266,226 266,234 -10,128" fill="#d0ebff"/>'
      '<path d="M20 150 L240 236 M30 160 L246 244" stroke="#a5d8ff" stroke-width="2" stroke-dasharray="8 6"/>'
      '<g transform="translate(0 -6)">'
      '<path d="M122 136 L90 176 M134 136 L166 176" stroke="#e03131" stroke-width="6" stroke-linecap="round"/>'
      '<path d="M118 100 L46 74 L58 86 L42 88 L58 98 L46 104 L64 110 L56 118 L118 116 Z" fill="#6b3e1f"/>'
      '<path d="M138 100 L210 74 L198 86 L214 88 L198 98 L210 104 L192 110 L200 118 L138 116 Z" fill="#6b3e1f"/>'
      '<ellipse cx="128" cy="112" rx="16" ry="24" fill="#7f4a24"/>'
      '<polygon points="120,130 136,130 144,148 112,148" fill="#fff"/>'
      '<rect x="118" y="132" width="5" height="8" rx="2" fill="#fab005"/><rect x="133" y="132" width="5" height="8" rx="2" fill="#fab005"/>'
      '<circle cx="128" cy="84" r="14" fill="#fff"/>'
      '<path d="M136 84 L150 89 L137 94 Z" fill="#fab005"/>'
      '<path d="M114 80 L142 80" stroke="#343a40" stroke-width="2"/>'
      '<rect x="120" y="76" width="22" height="9" rx="4" fill="#ff922b" stroke="#343a40" stroke-width="2"/></g>'
      + '<path d="M84 206 v14 h-7 l11 12 l11 -12 h-7 v-14z" fill="#1864ab"/>' + T(138, 228, 20, '1000 m', fill='#1864ab'))

# 12. Marathon
badge('marathon.svg', GOLD, ['#f03e3e', '#a61e1e'],
      laurel('#ffd43b') + T(128, 128, 50, '42.2', shadow='#4a0b0b') + T(128, 152, 16, 'KM', fill='#ffe3e3') + shoe(128, 186, .42, '#fff', '#fab005'))

# 13. Half Marathon
badge('half-marathon.svg', ['#f1f3f5', '#868e96'], ['#4dabf7', '#1864ab'],
      '<rect x="0" y="0" width="128" height="256" fill="#fff" opacity=".12"/>'
      '<line x1="128" y1="0" x2="128" y2="256" stroke="#fff" stroke-width="2" stroke-dasharray="6 6" opacity=".5"/>'
      + laurel('#e9ecef') + T(128, 128, 50, '21.1', shadow='#0b2e57') + T(128, 152, 16, 'KM', fill='#d0ebff') + shoe(128, 186, .42, '#fff', '#adb5bd'))


# 14. Silent night
def tree(x, y, s):
    return (f'<g transform="translate({x} {y}) scale({s})">'
            '<rect x="-5" y="-6" width="10" height="14" fill="#5c3310"/>'
            '<polygon points="-30,-4 30,-4 0,-40" fill="#2b8a3e"/>'
            '<polygon points="-24,-28 24,-28 0,-60" fill="#2f9e44"/>'
            '<polygon points="-17,-50 17,-50 0,-78" fill="#37b24d"/>'
            '<path d="M-17 -50 L0 -78 L17 -50 L8 -56 L0 -50 L-8 -56Z" fill="#fff"/>'
            '<path d="M-30 -4 L-22 -10 L-10 -4 L0 -10 L10 -4 L22 -10 L30 -4Z" fill="#fff"/></g>')


badge('silent-night.svg', GOLD, ['#0b1a47', '#2b4c9c'],
      stars([(54, 120, 1.5), (100, 60, 1.2), (130, 96, 1.5), (210, 120, 1.2), (150, 130, 1), (196, 46, 1.2), (70, 150, 1)]) +
      '<circle cx="80" cy="80" r="20" fill="#ffe066"/><circle cx="90" cy="73" r="18" fill="#0f2156"/>'
      '<path d="M172 52 L177 69 L194 74 L177 79 L172 96 L167 79 L150 74 L167 69Z" fill="#ffe066"/>'
      '<circle cx="172" cy="74" r="22" fill="#ffe066" opacity=".15"/>'
      '<path d="M-10 182 Q60 160 140 186 T266 176 V266 H-10Z" fill="#dee2e6"/>'
      + tree(96, 196, .95) + tree(158, 200, 1.15) +
      '<path d="M-10 204 Q80 180 170 206 T266 200 V266 H-10Z" fill="#f8f9fa"/>' +
      ''.join(f'<circle cx="{x}" cy="{y}" r="2" fill="#fff"/>' for x, y in [(40, 100), (120, 140), (214, 150), (200, 100), (60, 190), (124, 60)]))

# 15. Giant leap
badge('giant-leap.svg', ['#da77f2', '#862e9c'], ['#0b0c2a', '#2c2e6e'],
      stars([(40, 120, 1.2), (110, 50, 1.5), (140, 90, 1), (220, 120, 1.2), (150, 40, 1), (196, 136, 1.5), (124, 130, 1.2)]) +
      '<circle cx="184" cy="74" r="24" fill="#339af0"/>'
      '<path d="M170 60 C178 54 188 58 186 66 C184 74 172 72 170 80 C166 76 164 64 170 60Z M190 82 C198 78 206 84 202 92 C196 96 188 92 190 82Z" fill="#51cf66"/>'
      '<path d="M-10 166 Q128 138 266 166 V266 H-10Z" fill="#ced4da"/>'
      '<ellipse cx="60" cy="196" rx="16" ry="6" fill="#adb5bd"/><ellipse cx="196" cy="186" rx="20" ry="7" fill="#adb5bd"/><ellipse cx="176" cy="226" rx="12" ry="4" fill="#adb5bd"/>'
      '<g transform="rotate(-18 124 200)">'
      '<rect x="106" y="160" width="36" height="72" rx="18" fill="#868e96"/>'
      + ''.join(f'<rect x="110" y="{y}" width="28" height="4" rx="2" fill="#495057"/>' for y in range(168, 228, 9)) +
      '</g>'
      '<rect x="44" y="58" width="60" height="60" rx="8" fill="#fff"/>'
      '<path d="M44 66 a8 8 0 0 1 8 -8 h44 a8 8 0 0 1 8 8 v12 h-60z" fill="#e03131"/>'
      + T(74, 75, 12, 'FEB') + T(74, 110, 28, '29', fill='#212529'))

# 16. Festive 500
flakes = ''.join(flake(x, y, r) for x, y, r in [(56, 90, 7), (204, 96, 8), (66, 170, 6), (196, 176, 7), (100, 214, 5), (160, 50, 5), (94, 52, 5)])
badge('festive-500.svg', ['#ff6b6b', '#a61e1e'], ['#2f9e44', '#0b4d1c'],
      flakes +
      '<ellipse cx="110" cy="76" rx="22" ry="9" transform="rotate(-25 110 76)" fill="#51cf66" stroke="#1b5e20" stroke-width="2"/>'
      '<ellipse cx="146" cy="76" rx="22" ry="9" transform="rotate(25 146 76)" fill="#51cf66" stroke="#1b5e20" stroke-width="2"/>'
      '<circle cx="128" cy="84" r="7" fill="#e03131"/><circle cx="120" cy="91" r="6" fill="#c92a2a"/><circle cx="136" cy="91" r="6" fill="#c92a2a"/>'
      + T(128, 150, 60, '500', shadow='#e03131') + T(128, 174, 18, 'KM', fill='#ffe3e3') + bike(128, 202, .3, '#fff', 10))

# 17. Globetrotter
pins = ''.join(f'<path d="M{x} {y} c-6 -8 -8 -11 -8 -15 a8 8 0 0 1 16 0 c0 4 -2 7 -8 15z" fill="#f03e3e" stroke="#fff" stroke-width="1.5"/><circle cx="{x}" cy="{y-15}" r="3" fill="#fff"/>'
               for x, y in [(98, 110), (156, 100), (178, 168), (96, 160)])
badge('globetrotter.svg', ['#63e6be', '#0c8599'], ['#e3fafc', '#99e9f2'],
      '<defs><clipPath id="globe"><circle cx="128" cy="124" r="72"/></clipPath></defs>'
      '<circle cx="128" cy="124" r="72" fill="#339af0"/>'
      '<g clip-path="url(#globe)" transform="translate(0 -4)">'
      '<path d="M88 82 C100 72 118 76 116 90 C114 102 100 104 102 118 C104 132 112 140 106 160 C100 176 90 170 88 156 C86 140 78 130 80 112 C82 98 78 90 88 82Z" fill="#51cf66"/>'
      '<path d="M140 80 C156 72 176 80 172 94 C168 104 158 100 156 110 C168 112 178 124 176 142 C174 162 160 178 150 176 C144 160 150 148 140 138 C132 128 140 118 138 108 C136 98 128 88 140 80Z" fill="#51cf66"/>'
      '<path d="M168 158 C176 152 190 156 188 166 C186 174 172 174 168 168Z" fill="#51cf66"/>'
      '<g fill="none" stroke="#fff" stroke-opacity=".35" stroke-width="2"><ellipse cx="128" cy="128" rx="36" ry="72"/><line x1="128" y1="40" x2="128" y2="210"/>'
      '<line x1="40" y1="128" x2="216" y2="128"/><path d="M50 96 Q128 106 206 96 M50 160 Q128 150 206 160"/></g></g>'
      '<circle cx="128" cy="124" r="72" fill="none" stroke="#1c7ed6" stroke-width="3"/>'
      + pins +
      '<ellipse cx="128" cy="124" rx="98" ry="32" transform="rotate(-20 128 124)" fill="none" stroke="#fff" stroke-width="3" stroke-dasharray="7 6"/>'
      '<g transform="translate(220 92) rotate(-20) scale(1.4)"><path d="M0 -14 C2 -14 3 -12 3 -9 L3 -3 L14 4 L14 7 L3 3 L3 10 L7 13 L7 15 L0 13 L-7 15 L-7 13 L-3 10 L-3 3 L-14 7 L-14 4 L-3 -3 L-3 -9 C-3 -12 -2 -14 0 -14Z" fill="#fff" stroke="#495057" stroke-width="1"/></g>'
      '<rect x="88" y="190" width="80" height="30" rx="15" fill="#f03e3e" stroke="#fff" stroke-width="3"/>'
      + T(128, 213, 20, '50'))

# 18. Taylor
def sparkle(x, y, r, c='#fff'):
    return f'<path d="M{x} {y-r} Q{x} {y} {x+r} {y} Q{x} {y} {x} {y+r} Q{x} {y} {x-r} {y} Q{x} {y} {x} {y-r}Z" fill="{c}"/>'


note = '<path d="M0 0 v-22 l14 -4 v20" fill="none" stroke="#fff" stroke-width="3"/><ellipse cx="-4" cy="0" rx="5" ry="4" fill="#fff"/><ellipse cx="10" cy="-6" rx="5" ry="4" fill="#fff"/>'
badge('taylor.svg', GOLD, ['#f783ac', '#9c36b5'],
      sparkle(64, 70, 10) + sparkle(194, 60, 8, '#ffe066') + sparkle(206, 140, 6) + sparkle(50, 136, 6, '#ffe066') +
      f'<g transform="translate(62 186) rotate(-10)">{note}</g><g transform="translate(184 186) rotate(10)">{note}</g>' +
      '<g transform="translate(0 6)" fill="#1b1f3b">'
      '<path d="M128 102 Q92 66 40 70 Q84 88 118 120Z"/><path d="M128 102 Q164 66 216 70 Q172 88 138 120Z"/>'
      '<ellipse cx="128" cy="112" rx="11" ry="22"/><circle cx="128" cy="90" r="10"/>'
      '<polygon points="120,126 136,126 146,152 128,138 110,152"/>'
      '<circle cx="124" cy="87" r="2.2" fill="#fff"/><circle cx="132" cy="87" r="2.2" fill="#fff"/></g>'
      + T(128, 196, 34, '100', shadow='#4a1060'))

print(sorted(os.listdir(OUT)))
