# Release-Polish 0.9.0 – Prüfung vom 31.10.2026

## Ergebnis und Umfang

Für die Veröffentlichung ausdrücklich freigegebene Version **0.9.0 Beta** für
WoW Forever 1.60.1 / Interface 16001. Der Auftrag umfasst die Fertigstellung und
die Veröffentlichung auf CurseForge mit neuen Produktbildern. Dieser Bericht
belegt lokale Prüfung und Installation; ein erfolgter Upload oder eine
Plattformfreigabe wird daraus nicht abgeleitet.
Der sichere CLICK-Router und die eigentliche Segenauswahl bleiben unverändert.

- Eine kurze Einführung erscheint einmal pro Charakter, auch nach dem Update.
  Schließen ist ein gültiges Überspringen; `/fmb intro` zeigt sie erneut.
- Bei Login im Kampf wartet die automatische Einführung auf Kampfende.
  Eine währenddessen bewusst gelesene Einführung wird nicht erneut geöffnet.
- `/fmb bind` oder **Buffs & Taste → Taste wählen** öffnet die direkte Tastenwahl.
- Tastatur, Modifier (Umschalt/Strg/Alt/Cmd), mittlere/zusätzliche Maustasten und
  Mausrad werden unterstützt. Linke/rechte Maustaste und Escape sind reserviert.
- Neue freie Tasten ersetzen bisherige FMB-Tasten. Andere Aktionen und aktive
  Overrides werden nicht überschrieben. Eine bereits eigene Taste bleibt bestehen.
- Drücken allein speichert nicht: Tastatur-/Maustasten werden nach Loslassen
  übernommen. Escape, Abbrechen, Seitenwechsel, Schließen und Kampf brechen ab.
- Speichern nutzt den aktiven Account-/Charaktersatz. Fehler versuchen die zuvor
  vorhandenen Belegungen wiederherzustellen; ein fehlgeschlagener Rückweg wird
  ausdrücklich gemeldet. Es gibt keine zusätzliche Tasten-Kopie in SavedVariables.

## Dateibaum und zentrale Zuständigkeiten

```text
src/ForeverMouseoverBuff/
  App.lua                       Login, /fmb intro, /fmb bind, Version
  Menu.lua                      Einführung, Eingabe und sichtbare Rückmeldung
  Keybinding.lua                Validierung, Konfliktschutz, Speichern/Rollback
  ForeverMouseoverBuff.toc       Version und Ladereihenfolge
  ForeverMouseoverBuff_Camelot.toc
scripts/
  check-portable.sh              18 Lua-Suiten
  prepare-release.py             explizite Paket-Allowlist
tests/
  test_app.lua                   Einführung und Kampf-Lebenszyklus
  test_menu.lua                  tatsächliche UI-Handler und Abbruchwege
  test_keybinding.lua            19 native API-Verträge
  test_release_package.py        neues Modul im ZIP
  menu_frames.lua                synthetische Frame-Grenze
README.md / README.de.md / CHANGELOG.md
curseforge/                      Kandidatentexte und Metadaten
release/                         geprüfte Spiegel für den Source-Export
docs/release-polish-validation.md
```

Zentrale Aufrufe: `Menu.ShowIntroduction()`, `Menu.BeginBinding()`,
`Keybinding.Assign(key)`, `Keybinding.Clear()`, `Keybinding.FromInput(input)`.
Die Eingabe erreicht ausschließlich die vorhandene native CLICK-Bindung.
Das reine Anzeigen einer Seite wirkt keinen Zauber und weist keine Taste zu.

## Rot → Grün

Lua-Laufzeit: Lua 5.1.5, lokal vorhandene Laufzeit des benachbarten
Feberdin-HealBot-Forever-Projekts. `LUA_BIN` bezeichnet diese ausführbare Datei.
Die folgenden Befehle laufen aus dem Repository-Hauptordner.

| Test / Befehl | Fachlicher Rot-Nachweis | Grün |
| --- | --- | --- |
| `"$LUA_BIN" tests/test_menu.lua 'binding setup'` | `Buffs & Taste must offer a visible Taste wählen control` | 6 Tastenwahl-UI-Tests erfolgreich |
| `"$LUA_BIN" tests/test_app.lua introduction` | `first login must explain the addon before settings: expected intro, got buffs` | 3 Einführungstests erfolgreich |
| `"$LUA_BIN" tests/test_app.lua 'introduction manually'` | `explicitly dismissed introduction must stay closed: expected false, got true` | Regression erfolgreich |
| `"$LUA_BIN" tests/test_keybinding.lua 'localized keyboard'` | `expected CTRL-Ö, got nil` | UTF-8-Einzeltaste mit Modifier erfolgreich |
| `python3 -m unittest discover -s tests -p test_release_package.py -k sanctum -v` | `ForeverMouseoverBuff/Keybinding.lua` fehlte im ZIP | Paketvertrag erfolgreich |

Die anfänglichen Fehler waren fachliche Assertions, keine kaputten Imports oder
fehlenden Laufzeiten. Bestehende Assertions bleiben erhalten; ein Rückkehrer-Test
öffnet sein nun absichtlich geschlossenes Menü vor dem Anklicken ausdrücklich.

## Ausgeführte Gesamtprüfungen

Alle nachstehenden Prüfungen erfolgreich. Die Befehle entsprechen dem CI-Workflow;
PyYAML 6.0.3 und Ruff 0.16.1 standen lokal bereits zur Verfügung.

```sh
LUA_BIN="$LUA_BIN" sh scripts/check-portable.sh
python3 -m unittest discover -s tests -p test_release_package.py -v
python3 -m unittest discover -s tests -p test_issue_templates.py -v
python3 -m unittest discover -s companion/tests -v
PYTHONPATH=service python3 -m unittest discover -s service/tests -v
LUA_BIN="$LUA_BIN" python3 -m unittest discover -s tests -p test_ranking_end_to_end.py -v
LUA_BIN="$LUA_BIN" python3 -m unittest discover -s tests -p test_diagnostics_end_to_end.py -v
node --test service/tests/test_upload_core.cjs service/tests/test_upload_ui.cjs
node --check service/static/app.js
node --check service/static/upload-core.js
node --check service/static/upload.js
ruff check scripts/prepare-release.py release/assets/render-launch-0.9.0.py tests/test_release_package.py tests/test_diagnostics_end_to_end.py tests/test_issue_templates.py service companion
ruff format --check scripts/prepare-release.py release/assets/render-launch-0.9.0.py tests/test_release_package.py tests/test_diagnostics_end_to_end.py tests/test_issue_templates.py service companion
shellcheck scripts/check-portable.sh
sh -n scripts/check-portable.sh
python3 -m json.tool service/openapi.json
python3 -m json.tool curseforge/metadata.json
git diff --check
python3 scripts/prepare-release.py --version 0.9.0 --output dist/review-0.9.0
```

Zusätzlich wurden die vorhandenen privaten nativen Fixtures in einem temporären
Verzeichnis mit dem aktuellen `src/` verknüpft und folgende Tests ausgeführt:

```sh
"$LUA_BIN" tests/test_native_action.lua
"$LUA_BIN" tests/test_wim_contract.lua
"$LUA_BIN" tests/test_chat.lua
```

Ergebnis: 22 native Action-, 17 WIM- und 17 Chat-Verträge erfolgreich.
Diese Fixtures werden nicht in das veröffentlichbare Paket aufgenommen.

Weitere Ergebnisse: 18 portable Lua-Suiten, 90 Python-Tests, 14 Node-Tests.
Kein eigener Lua-Formatter oder Lua-Typecheck konfiguriert; Syntax aller
Runtime-Dateien wird mit Lua 5.1 geprüft. Kein separater Addon-Build erforderlich;
der überprüfte ZIP-Export ist das Installationsartefakt.
Für die Veröffentlichung muss zusätzlich die GitHub-CI des finalen Liefercommits
erfolgreich abgeschlossen sein. Maßgeblich ist der tatsächlich zu diesem Commit
gehörende Run; die lokalen Ergebnisse ersetzen diesen Nachweis nicht.

## Lokale Forever-Installation

Die Version wurde im aktiven `_forever_/Interface/AddOns/ForeverMouseoverBuff`
installiert. Der Installationsabgleich bestätigt **26 Dateien**, Version **0.9.0**,
Interface **16001** und bytegleichen Runtime-Inhalt zum geprüften Quellstand.
Der vorhandene Forever-Client ist **1.60.1.70685**. SavedVariables wurden dabei
nicht verändert.

Installiertes ZIP, SHA-256:
`81c6397f9f39d2e3ba309a7e1c0b81d83e2864f6c8a8c857d7c0206a4a5e0004`

Dies ist ein Datei-/Installationsnachweis. Das Laden im Spiel, die tatsächliche
Tasteneingabe und die umfassende Ingame-Abnahme sind noch offen; deshalb bleibt
die ausdrücklich beauftragte Veröffentlichung als **Beta** gekennzeichnet.

## Starten und debuggen

1. ZIP in den aktiven Forever-Ordner `Interface/AddOns` entpacken. Der resultierende
   Ordner muss `ForeverMouseoverBuff/ForeverMouseoverBuff.toc` enthalten.
2. Bei erstmaliger Installation WoW neu starten; für ein bestehendes Addon `/reload`.
3. Einführung lesen, **Taste einrichten** wählen, freie Taste drücken und loslassen.
4. Für einen Segen mit dem Paladin über einen freundlichen Spieler fahren und
   die Taste erneut bewusst drücken und loslassen.

Bei belegter Taste eine andere Taste wählen oder die alte Aktion bewusst in WoWs
Tastaturbelegung ändern. Bei Kampf warten und `/fmb bind` erneut aufrufen.
Bei Speicher-/Rollbackfehler die native WoW-Tastaturbelegung prüfen; sie ist die
maßgebliche Quelle. `/fmb status`, `/fmb diag` und zeitweise `/fmb debug on` helfen
bei Buff-Problemen; danach `/fmb debug off`. Keine Spielernamen, Whisper oder
rohen API-Fehler werden durch das neue Tastenmodul protokolliert. API-Fehler werden
als feste, verständliche UI-Meldung angezeigt, nicht still verschluckt.

## Noch im Spiel abzunehmen

Die Offline-Tests emulieren keine WoW-Eingabeauslieferung und keine echten Zauber.
Die folgenden Punkte bleiben für die Beta offen und sind vor einer Einstufung
als stabile Version im Forever-Client zu prüfen:

- Einführung bei neuem Charakter/Update, Escape, Wiederaufruf und Login im Kampf.
- Freie Tastaturtaste, Modifier, Zusatztaste und Mausrad zuweisen; beim Einrichten
  darf kein alter oder neuer Zauber ausgelöst werden.
- Konflikte/Abbrechen/Kampfbeginn; andere Belegungen müssen erhalten bleiben.
- Account- und Charakterbelegung nach `/reload` und nach vollständigem Neustart.
- Auto außerhalb des Kampfes, festes gelerntes Könige im Kampf, keine Hover-Casts.
- Schrift, Umbrüche und Trefferflächen bei kleiner Auflösung und eigener UI-Skalierung.

## Review-Checkliste

- [x] README und Quickstart verständlich aktualisiert.
- [x] Kommentare erklären Grenzen, Absicht und komplexe Eingabefolgen.
- [x] Eingaben validiert, keine Default-Taste oder fremde Überschreibung.
- [x] Verständliche Konflikt-, Kampf- und Fehlermeldungen mit nächsten Schritten.
- [x] Bestehende Diagnosebefehle dokumentiert; keine Rohfehler oder privaten Logs.
- [x] Neue Anforderungen vor Implementierung fachlich rot.
- [x] Fokussierte Tests nach Implementierung grün.
- [x] Gesamttests lokal erfolgreich.
- [x] Vorhandene Syntax-, Lint-, Format- und Paketprüfungen erfolgreich.
- [x] Lokale Forever-Installation mit Quellstand abgeglichen; SavedVariables erhalten.
- [ ] Tatsächliche Eingabe, Persistenz und Layout im laufenden WoW abgenommen.
- [ ] Finalen Liefercommit, exakte Remote-CI und veröffentlichte Downloads verifiziert.

## Marketing-Paket: Rot → Grün

Test: `tests/test_release_package.py::ReleaseTests.test_launch_artwork_ships_in_source_without_inflating_game_addon`.

Rot-Befehl: `python3 -m unittest discover -s tests -p test_release_package.py -k launch_artwork -v`.
Fachlicher Fehler: `release/assets/hero-art-0.9.0.jpg` fehlte im Source-Export;
die neuen versionierten Marketing-Dateien waren noch nicht freigegeben.
Nach gezielter Ergänzung der Asset-Allowlist bestand derselbe Befehl (1 Test).
Der Vertrag prüft zugleich, dass Marketing-Dateien nicht ins installierbare Addon-ZIP gelangen.

Die Bildserie umfasst ein KI-unterstütztes Titelmotiv und zwei ausdrücklich als
Code-Vorschau gekennzeichnete UI-Ansichten. Herkunft und Reproduktion stehen in
`release/assets/launch-0.9.0.md`. Originale Feberdin-Marken bleiben unverändert.
