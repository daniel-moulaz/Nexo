"""Monta comparacao.html: uma página só, sem arquivos externos além das fontes.

    python docs/brand/opcoes/pagina.py
"""
import base64
import html
import io
import os

import gerar
from gerar import OPTIONS, HERE, ROOT, contrast, mark_on_tile, png, tile_svg, lockup_svg, adaptive_svg, svg, nested

FAVORITE = 'engate'
CURRENT = open(os.path.join(ROOT, 'docs/brand/nexo-mark.svg'), encoding='utf-8').read()
CURRENT = CURRENT[CURRENT.index('<svg'):]
CURRENT_FRONT = ('<svg xmlns="http://www.w3.org/2000/svg" width="108" height="108" viewBox="0 0 512 512">'
                 '<g transform="translate(138 138) scale(.46)"><path d="M160 352 V168 l192 184 V168" fill="none" '
                 'stroke="#F2C14E" stroke-width="46" stroke-linecap="round" stroke-linejoin="round"/>'
                 '<circle cx="352" cy="168" r="34" fill="#F2C14E"/></g></svg>')


def uri(text):
    return 'data:image/svg+xml;base64,' + base64.b64encode(text.encode()).decode()


def png_uri(text, size):
    buffer = io.BytesIO()
    png(text, size).save(buffer, 'PNG')
    return 'data:image/png;base64,' + base64.b64encode(buffer.getvalue()).decode()


def img(src, size, alt):
    return f'<img src="{src}" width="{size}" height="{size}" alt="{html.escape(alt)}">'


def chips(o):
    colors = [('Fundo do ícone', o['tile'])]
    colors += [('No escuro', c) for c in o['dark']] + [('No claro', c) for c in o['light']]
    seen, out = set(), ''
    for label, c in colors:
        if c in seen:
            continue
        seen.add(c)
        out += f'<li><span class="sw" style="background:{c}"></span><code>{c}</code><small>{label}</small></li>'
    return f'<ul class="chips">{out}</ul>'


def card(o, metric):
    tile = tile_svg(o)
    name = html.escape(o['name'])
    best = o['id'] == FAVORITE
    sizes = ''.join(f'<figure>{img(png_uri(tile, s), s, f"{name} em {s} px")}<figcaption>{s}</figcaption></figure>'
                    for s in (16, 32, 48))
    front = uri(adaptive_svg(o['fn'](mark_on_tile(o))))
    return f'''<article class="card{' best' if best else ''}" id="o-{o['id']}">
  <header><h3>{name}</h3><p class="tag">{html.escape(o['direction'])}{' · minha escolha' if best else ''}</p></header>
  <p class="concept">{html.escape(o['concept'])}</p>
  <div class="pair">
    <div class="on dark"><img class="lock" src="{uri(lockup_svg(o, o['dark'], '#F8FAFC'))}" alt="{name} com o nome, em fundo escuro"></div>
    <div class="on light"><img class="lock" src="{uri(lockup_svg(o, o['light'], '#0F172A'))}" alt="{name} com o nome, em fundo claro"></div>
  </div>
  <div class="sizes">{sizes}</div>
  {chips(o)}
  <p class="numbers">Contraste no ícone {metric['tile']:.1f} · no preto {metric['black']:.1f} · no branco {metric['white']:.1f} · zona segura {metric['radius']:.1f} de 33</p>
  <details><summary>Ver em 192 e 512 px e a versão do Android</summary>
    <div class="big">
      <figure>{img(uri(tile), 192, f"{name} em 192 px")}<figcaption>192</figcaption></figure>
      <figure class="safe"><div class="layer" style="background:{o['tile']}"><img src="{front}" alt="Camada adaptativa de {name}"><i></i></div><figcaption>Android: o círculo é a zona segura</figcaption></figure>
      <figure class="full"><img src="{uri(tile)}" width="512" height="512" alt="{name} em 512 px"><figcaption>512</figcaption></figure>
    </div>
  </details>
</article>'''


def app(o):
    front = uri(adaptive_svg(o['fn'](mark_on_tile(o))))
    mono = uri(adaptive_svg(o['fn'](['#FFFFFF'] * 3)))
    return (f'<li><span class="app" style="--tile:{o["tile"]}"><img class="color" src="{front}" alt="">'
            f'<img class="mono" src="{mono}" alt=""></span><small>{html.escape(o["name"])}</small></li>')


def current_app():
    return (f'<li><span class="app" style="--tile:#0B1118"><img class="color" src="{uri(CURRENT_FRONT)}" alt="">'
            f'<img class="mono" src="{uri(CURRENT_FRONT.replace("#F2C14E", "#FFFFFF"))}" alt=""></span><small>Atual</small></li>')


def bar(kind):
    items = f'<li>{img(uri(CURRENT), 24, "Atual")}<small>Atual</small></li>'
    items += ''.join(f'<li{" class=on" if o["id"] == FAVORITE else ""}>{img(uri(tile_svg(o)), 24, o["name"])}'
                     f'<small>{html.escape(o["name"])}</small></li>' for o in OPTIONS)
    return f'<ul class="bar {kind}">{items}</ul>'


def zoom():
    rows = [('Atual', CURRENT)] + [(o['name'], tile_svg(o)) for o in OPTIONS]
    return ''.join(f'<figure><img class="px" src="{png_uri(t, 16)}" width="64" height="64" alt="{html.escape(n)} em 16 px ampliado">'
                   f'<figcaption>{html.escape(n)}</figcaption></figure>' for n, t in rows)


TEMPLATE = open(os.path.join(HERE, 'pagina.template.html'), encoding='utf-8').read()


def main():
    metrics = {r['id']: r for r in gerar.report()}
    page = (TEMPLATE
            .replace('{{CURRENT}}', img(uri(CURRENT), 120, 'Logo atual: N dourado com um ponto, em fundo quase preto'))
            .replace('{{CURRENT_16}}', img(png_uri(CURRENT, 16), 16, 'Logo atual em 16 px'))
            .replace('{{CURRENT_ZOOM}}', f'<img class="px" src="{png_uri(CURRENT, 16)}" width="64" height="64" alt="Logo atual em 16 px, ampliada">')
            .replace('{{FAVORITE}}', img(uri(tile_svg(next(o for o in OPTIONS if o['id'] == FAVORITE))), 120, 'Engate'))
            .replace('{{CARDS}}', '\n'.join(card(o, metrics[o['id']]) for o in OPTIONS))
            .replace('{{APPS}}', current_app() + ''.join(app(o) for o in OPTIONS))
            .replace('{{BAR_DARK}}', bar('dark'))
            .replace('{{BAR_LIGHT}}', bar('light'))
            .replace('{{ZOOM}}', zoom()))
    with open(os.path.join(HERE, 'comparacao.html'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(page)
    print(len(page) // 1024, 'KB')


if __name__ == '__main__':
    main()
