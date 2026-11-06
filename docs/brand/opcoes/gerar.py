"""Gera as opções de marca: SVGs, PNGs de teste, .ico e camadas adaptativas.

Só produz arquivos em docs/brand/opcoes/. Não toca em nada do app.
    python docs/brand/opcoes/gerar.py     (precisa de fonttools, pymupdf, pillow)
"""
import io
import math
import os
import sys

import pymupdf
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))


def line(d, color, w):
    return f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>'


def shape(d, color):
    return f'<path d="{d}" fill="{color}"/>'


def dot(x, y, r, color):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{color}"/>'


def square(x, y, s, r, color):
    return f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="{r}" fill="{color}"/>'


# Cada desenho ocupa o quadrado 100x100, com margem própria.
def engate(c):
    a = 'M25 81V38C25 21 39 16 50 27L60 37'
    b = 'M75 19V62C75 79 61 84 50 73L40 63'
    return line(a, c[0], 15) + line(b, c[1], 15)


def intersecao(c):
    return (f'<rect x="14" y="14" width="50" height="50" rx="14" fill="{c[0]}"/>'
            f'<rect x="36" y="36" width="50" height="50" rx="14" fill="{c[1]}"/>'
            f'<rect x="36" y="36" width="28" height="28" rx="6" fill="{c[2]}"/>')


def constelacao(c):
    return (line('M26 78V22L74 78V22', c[0], 8)
            + dot(26, 78, 10.5, c[1]) + dot(26, 22, 10.5, c[1])
            + dot(74, 78, 10.5, c[1]) + dot(74, 22, 10.5, c[1]))


def fluxo(c):
    return line('M21 80C21 44 27 20 39 20C53 20 47 80 61 80C73 80 79 56 79 20', c[0], 16)


def encontro(c):
    return shape('M12 40V88H60A48 48 0 0 0 12 40Z', c[0]) + shape('M88 60V12H40A48 48 0 0 0 88 60Z', c[1])


def ponte(c):
    return line('M26 80V50A24 24 0 0 1 74 50V80', c[0], 20)


def blocos(c):
    size, gap, start = 17, 5, 13.5
    out = ''
    for col, row in [(0, 0), (0, 1), (0, 2), (0, 3), (3, 0), (3, 1), (3, 2), (3, 3)]:
        out += square(start + col * (size + gap), start + row * (size + gap), size, 4.5, c[0])
    for col, row in [(1, 1), (2, 2)]:
        out += square(start + col * (size + gap), start + row * (size + gap), size, 4.5, c[1])
    return out


def nucleo(c):
    points = [(50, 17), (21, 67), (79, 67)]
    out = ''.join(line(f'M50 50L{x} {y}', c[0], 7) for x, y in points)
    out += ''.join(dot(x, y, 12.5, c[0]) for x, y in points)
    return out + dot(50, 50, 15, c[1])


OPTIONS = [
    dict(id='engate', name='Engate', direction='Monograma', fn=engate, tile='#0E1420',
         dark=['#5EEAD4', '#F8FAFC'], light=['#0F766E', '#0F172A'], word='SemiBold',
         concept='Dois ganchos que se prendem formam o N: duas contas que passam a andar juntas.'),
    dict(id='intersecao', name='Interseção', direction='Abstrato', fn=intersecao, tile='#101826',
         dark=['#38BDF8', '#818CF8', '#F8FAFC'], light=['#0284C7', '#4F46E5', '#0F172A'], word='SemiBold',
         concept='Duas áreas que se sobrepõem: o nexo é o ponto em comum entre elas.'),
    dict(id='constelacao', name='Constelação', direction='Monograma sóbrio', fn=constelacao, tile='#0B1F1A',
         dark=['#6EE7B7', '#ECFDF5'], light=['#047857', '#064E3B'], word='Medium',
         concept='Quatro pontos e as ligações entre eles: suas contas formam uma única figura.'),
    dict(id='fluxo', name='Fluxo', direction='Vivo', fn=fluxo, tile='#E11D48',
         dark=['#FB7185'], light=['#E11D48'], tile_mark=['#FFF1F2'], word='Bold',
         concept='Uma linha só, sem cantos: o dinheiro correndo de uma ponta à outra.'),
    dict(id='encontro', name='Encontro', direction='Geométrico', fn=encontro, tile='#0F172A',
         dark=['#E2E8F0', '#F59E0B'], light=['#0F172A', '#D97706'], word='SemiBold',
         concept='Duas formas que se encaram e deixam entre elas a diagonal do N.'),
    dict(id='ponte', name='Ponte', direction='Vivo', fn=ponte, tile='#BEF264',
         dark=['#BEF264'], light=['#3F6212'], tile_mark=['#14532D'], word='Bold',
         concept='O n minúsculo é uma ponte: dois pilares e o arco que os liga.'),
    dict(id='blocos', name='Blocos', direction='Monograma geométrico', fn=blocos, tile='#111827',
         dark=['#E5E7EB', '#22D3EE'], light=['#111827', '#0891B2'], word='SemiBold',
         concept='Dez peças iguais formam o N, e duas delas fazem a ligação entre os lados.'),
    dict(id='nucleo', name='Núcleo', direction='Abstrato', fn=nucleo, tile='#1E1B4B',
         dark=['#C7D2FE', '#FDE047'], light=['#3730A3', '#A16207'], word='SemiBold',
         concept='Um centro e três pontas: tudo o que é seu ligado a um só lugar.'),
]


def svg(body, size=100, box='0 0 100 100'):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="{box}">{body}</svg>'


def nested(body, x, y, s):
    return f'<g transform="translate({x} {y}) scale({s / 100})">{body}</g>'


def mark_on_tile(o):
    return o.get('tile_mark') or o['dark']


def tile_svg(o):
    """Ícone cheio: fundo e marca, com os cantos do Windows e do README."""
    return svg(f'<rect width="100" height="100" rx="22" fill="{o["tile"]}"/>'
               + nested(o['fn'](mark_on_tile(o)), 12, 12, 76))


def wordmark(weight, color):
    font = TTFont(os.path.join(ROOT, 'assets/fonts/Inter', f'Inter-{weight}.ttf'))
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    x = 0
    out = ''
    for ch in 'Nexo':
        name = cmap[ord(ch)]
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(TransformPen(pen, (1, 0, 0, -1, x, 0)))
        out += f'<path d="{pen.getCommands()}" fill="{color}"/>'
        x += glyphs[name].width
    return out, x, font['OS/2'].sCapHeight


def lockup_svg(o, colors, ink):
    letters, width, cap = wordmark(o['word'], ink)
    scale = 60 / cap
    text_w = width * scale
    w = 100 + 18 + text_w
    body = nested(o['fn'](colors), 0, 0, 100)
    body += f'<g transform="translate(118 80) scale({scale})">{letters}</g>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{round(w)}" height="100" '
            f'viewBox="0 0 {w:.1f} 100">{body}</svg>')


def adaptive_svg(body):
    """Camada de 108x108: a marca cabe no círculo seguro de 66 de diâmetro."""
    return svg(nested(body, 54 - 25.5, 54 - 25.5, 51), 108, '0 0 108 108')


def png(svg_text, size):
    """Desenha 8x maior e reduz: a mesma suavização em todos os tamanhos."""
    doc = pymupdf.open(stream=svg_text.encode(), filetype='svg')
    page = doc[0]
    zoom = size * 8 / page.rect.width
    pix = page.get_pixmap(matrix=pymupdf.Matrix(zoom, zoom), alpha=True)
    image = Image.open(io.BytesIO(pix.tobytes('png'))).convert('RGBA')
    doc.close()
    return image.resize((size, round(size * image.height / image.width)), Image.LANCZOS)


def luminance(color):
    channels = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    r, g, b = [c / 12.92 if c <= .03928 else ((c + .055) / 1.055) ** 2.4 for c in channels]
    return .2126 * r + .7152 * g + .0722 * b


def contrast(a, b):
    high, low = sorted([luminance(a), luminance(b)], reverse=True)
    return (high + .05) / (low + .05)


def safe_radius(o):
    """Maior distância do centro com tinta, na camada de 108 (limite: 33)."""
    size = 432
    image = png(adaptive_svg(o['fn'](['#FFFFFF'] * 3)), size)
    alpha = image.getchannel('A').load()
    far = 0
    for y in range(0, size, 2):
        for x in range(0, size, 2):
            if alpha[x, y] > 96:
                far = max(far, math.hypot(x - size / 2, y - size / 2))
    return far * 108 / size


def report():
    rows = []
    for o in OPTIONS:
        marks = mark_on_tile(o)
        rows.append(dict(id=o['id'], tile=min(contrast(c, o['tile']) for c in marks),
                         black=min(contrast(c, '#000000') for c in o['dark']),
                         white=min(contrast(c, '#FFFFFF') for c in o['light']),
                         radius=safe_radius(o)))
    return rows


def write(path, text):
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)


def build(o):
    out = os.path.join(HERE, o['id'])
    os.makedirs(out, exist_ok=True)
    mono = ['#FFFFFF'] * 3
    files = {
        'simbolo-escuro.svg': svg(o['fn'](o['dark'])),
        'simbolo-claro.svg': svg(o['fn'](o['light'])),
        'icone.svg': tile_svg(o),
        'nome-escuro.svg': lockup_svg(o, o['dark'], '#F8FAFC'),
        'nome-claro.svg': lockup_svg(o, o['light'], '#0F172A'),
        'android-frente.svg': adaptive_svg(o['fn'](mark_on_tile(o))),
        'android-mono.svg': adaptive_svg(o['fn'](mono)),
    }
    for name, text in files.items():
        write(os.path.join(out, name), text)
    tile = files['icone.svg']
    for size in (16, 32, 48, 192, 512):
        png(tile, size).save(os.path.join(out, f'icone-{size}.png'))
    sizes = [16, 24, 32, 48, 64, 128, 256]
    frames = [png(tile, s) for s in sizes]
    frames[-1].save(os.path.join(out, 'app_icon.ico'), format='ICO',
                    sizes=[(s, s) for s in sizes], append_images=frames[:-1])


def sheet(path):
    """Prancha para revisão: cada opção em 512, 48, 32 e 16 px, e no claro."""
    cell_w, cell_h = 300, 330
    canvas = Image.new('RGB', (cell_w * 4, cell_h * 2), (24, 24, 28))
    for i, o in enumerate(OPTIONS):
        x, y = (i % 4) * cell_w, (i // 4) * cell_h
        tile = tile_svg(o)
        big = png(tile, 190)
        canvas.paste(big, (x + 10, y + 10), big)
        off = x + 210
        for s in (64, 48, 32, 16):
            p = png(tile, s)
            canvas.paste(p, (off, y + 10), p)
            y2 = s + 8
            y += y2
        y = (i // 4) * cell_h
        white = Image.new('RGB', (280, 96), (250, 250, 250))
        lock = png(lockup_svg(o, o['light'], '#0F172A'), 230)
        white.paste(lock, (8, 8), lock)
        canvas.paste(white, (x + 10, y + 214))
    canvas.save(path)


if __name__ == '__main__':
    for option in OPTIONS:
        build(option)
    if len(sys.argv) > 1:
        sheet(sys.argv[1])
    for row in report():
        print('{id:12} tile {tile:5.1f}  preto {black:5.1f}  branco {white:5.1f}  raio {radius:4.1f}/33'.format(**row))
