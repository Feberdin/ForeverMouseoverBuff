# Releasegrafiken 0.9.0

Drei statische Artboards mit jeweils **1600 × 900 Pixeln**. Die PNG-Dateien sind
für die Veröffentlichung bestimmt; die gleichnamigen SVG-Dateien enthalten die
vollständigen Vektorkompositionen einschließlich unveränderter Bildquellen.
Alle sechs Dateien liegen einzeln unter 2 MiB.

| Motiv | PNG | SVG | PNG-Größe |
| --- | --- | --- | ---: |
| Titelgrafik | [launch-hero-0.9.0.png](launch-hero-0.9.0.png) | [SVG](launch-hero-0.9.0.svg) | 1.69 MiB |
| Einführung | [launch-intro-0.9.0.png](launch-intro-0.9.0.png) | [SVG](launch-intro-0.9.0.svg) | 260 KiB |
| Tastenwahl | [launch-keybinding-0.9.0.png](launch-keybinding-0.9.0.png) | [SVG](launch-keybinding-0.9.0.svg) | 228 KiB |

## Herkunft und Aussagegrenzen

- **Titelillustration:** [hero-art-0.9.0.jpg](hero-art-0.9.0.jpg), mit dem
  eingebauten `image_gen` erstellt. Die Illustration ist eine eigenständige
  Fantasieszene, kein Spiel-Screenshot. Der verwendete Prompt steht vollständig
  unten. Die Komposition bindet das vorhandene JPEG unverändert ein, skaliert
  proportional und beschneidet nur den Bildausschnitt auf 16:9. Abdunklung,
  Rahmen und Schrift sind separate SVG-Vektorebenen; die Bilddatei wird nicht
  retuschiert. Der sichtbare Fußtext kennzeichnet die KI-gestützte Illustration.
- **Autor- und Addonmarken:** [feberdin-knight.png](feberdin-knight.png) und
  [project-icon.png](project-icon.png) werden als vorhandene Originaldateien
  unverändert eingebettet und proportional skaliert. Keine neu gezeichnete
  Ritter- oder Wortmarke.
- **Oberfläche:** Die `layouts`- und `textures`-Daten in
  [launch-0.9.0.html](launch-0.9.0.html) enthalten exportierte native Frames der
  tatsächlichen [Menu.lua](../../src/ForeverMouseoverBuff/Menu.lua) und
  [Theme.lua](../../src/ForeverMouseoverBuff/Theme.lua). Die SVG-Vorschauen
  übernehmen Reihenfolge, Position, Größe, Farbe, Text und Originaltexturen aus
  diesen Daten: 64 Knoten für die Einführung, 85 für die Tastenaufnahme.
  Die Originaltexturen entsprechen den Dateien unter
  [Media](../../src/ForeverMouseoverBuff/Media).
- **Darstellung:** Es handelt sich um eine aus dem Quellcode erzeugte Vorschau,
  ausdrücklich nicht um einen aufgenommenen WoW-Screenshot. WoWs Schrift- und
  Eingabe-Engine wird nicht simuliert. Die Vorschau verwendet Arial Narrow und
  setzt Text innerhalb der exportierten Flächen um. Keinerlei Spielernamen,
  echten Charakterdaten, erfundenen Zähler, Rankings oder erfolgreichen Zauber
  werden dargestellt. Die Tastenansicht zeigt den tatsächlichen Wartestatus.
- **Redaktionelle Gestaltung:** Englische Begleittexte und Anordnung folgen
  [launch-0.9.0.html](launch-0.9.0.html). Die deutsche Addonoberfläche bleibt
  erhalten. Beta und WoW Forever werden sichtbar benannt.
- **Schriften:** Arial, Arial Narrow und Georgia werden beim Rendern lokal
  eingelesen. Nur die für diese konkreten Texte erforderlichen Glyphenkonturen
  stehen als SVG-Pfade im Ergebnis; es werden keine Fontdateien ausgeliefert.

## Reproduzieren

[render-launch-0.9.0.py](render-launch-0.9.0.py) erstellt eigenständige SVGs und
rendert sie direkt mit CairoSVG, ohne Browser und ohne externe Anfragen. Die
Quellbilder bleiben unverändert. Auf macOS mit Homebrew-Cairo, vom Repo aus:

```sh
python3 -m venv .artwork-tools
.artwork-tools/bin/python -m pip install fonttools==4.68.0 cairosvg==2.9.1
DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib .artwork-tools/bin/python release/assets/render-launch-0.9.0.py
```

Standardmäßig werden die genannten Schriften aus macOS' systemweitem Ordner
`/System/Library/Fonts/Supplemental` verwendet. Für ein anderes System mit
entsprechend bereitgestellten Schriften `--fonts-dir <font-ordner>` angeben.
`--debug` aktiviert ausführlichere lokale Diagnose. Fehlende Dateien oder
Schriften werden vor der jeweiligen Nutzung gemeldet; es gibt keinen Download
während der Generierung. Der Renderer prüft die Größenbegrenzung je Artefakt.

## Prüfung am 31.10.2026

- Alle drei PNGs mit `view_image` visuell geprüft: vollständige Marken,
  lesbare Überschriften, keine abgeschnittenen UI-Texte oder überlappenden
  Bedienelemente.
- PNG-Struktur und 1600 × 900 Pixel geprüft; SVGs als XML geparst.
- Alle SVG-Bildverweise sind eingebettete `data:`-Quellen, alle Glyphenverweise
  dokumentinterne `#`-Referenzen; keine privaten Pfade oder Netzwerkquellen.
- PNG und SVG jeweils unter 2 MiB.
- Generator mit Ruff geprüft und formatiert. Keine künstlichen Unit-Tests für
  diese statischen Grafikartefakte; Render-, Struktur- und Sichtprüfung sind
  die reproduzierbaren Prüfungen.

SHA-256 der Veröffentlichungsdateien:

```text
8e5e3eebcc0a09dfc081d1c68625851ae8f914ab5db76149b127e69ae32d0e8c  launch-hero-0.9.0.png
a992c4bbb36cddf417620b691583eb0d4111dc59582b74bf0fa4e8e6079cdeb2  launch-intro-0.9.0.png
a22d7a92216ab496ffd97885cae6be0c30a56b97425b826b502e6c8569311113  launch-keybinding-0.9.0.png
```

## Verwendeter Illustrationsprompt

```text
Built-in image_gen generation. Original illustrative key art, not a game screenshot.

Use case: ads-marketing.
Asset type: original cinematic background illustration for an independent fantasy game addon release banner.
Primary request: create a beautiful, premium painterly fantasy videogame key-art scene of a noble paladin quietly blessing one fellow traveler on an ancient stone bridge beside a ruined forest sanctuary at dawn.
Scene: misty primeval forest, subtle weathered carved stone, distant sanctuary arches, delicate airborne motes. A benevolent armored paladin extends an open hand toward one cloaked traveler, with a restrained ribbon of warm pale-gold holy light between them. No fighting. Their body language expresses solidarity, kindness, and a brief shared moment on a long journey.
Composition: very wide cinematic landscape, ideally 2.4:1. Both figures and the blessing occupy the right 50 percent; their silhouettes read clearly at small banner size. Left 45 percent is quiet dark atmospheric negative space, deep petrol forest haze with minimal detail, deliberately usable for a later headline overlay. Keep the subjects entirely visible and leave generous crop-safe margins.
Style: sophisticated painterly high-fantasy illustration, refined edge control, rich material details, cinematic depth, luminous gilded armor accents, beautiful natural textures. An original fictional scene, not an imitation of a game screenshot.
Lighting and palette: dark petrol and blue-green teal shadows, warm pale-gold dawn and blessing light, soft mint mist, elegant restrained saturation and strong focal contrast on the right. Dreamlike but grounded, inviting, hopeful.
Text: none.
Constraints: no text, letters, logos, brand marks, insignia, UI, numbers, badges, watermarks or frame. No additional characters. No giant weapon in foreground. No gruesome elements. No actual game interface. Opaque background.
```
