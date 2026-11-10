# 0.10.2 – Reparatur und Prüfnachweis

## Umfang und Ursache

Eine gemischte lokale Installation enthielt einen Aufruf von `AutoThanks.OnCombatLog`, obwohl das installierte Modul diese optionale Funktion nicht bereitstellte. Der Ereignispfad warf dadurch einen Lua-Fehler. Version 0.10.2 prüft die optionale Funktion und liefert ein zusammenpassendes Paket. Eigene Frame-Fehler werden zusätzlich als feste Fehlerkennung mit eigener Datei und Zeile aufgezeichnet und weiterhin an Blizzards Fehleranzeige weitergereicht.

Die bereits lokal vorhandenen Änderungen an Heilungs-Dank, PvP-Schutz und verständlichen Versandzählern sind enthalten und durch die portable Suite abgesichert. Kampfsperren für geschützte Aktionen werden nicht umgangen.

## Dateien

```text
src/ForeverMouseoverBuff/{App,AutoThanks,FeberdinDiagnostics}.lua
companion/fmb_companion/{diagnostics,cli}.py
tests/{test_app,test_auto_thanks,test_feberdin_diagnostics}.lua
companion/tests/test_diagnostics.py
docs/PVP-SAFETY.md
```

## Rot → Grün

Mit `LUA_BIN` auf eine lokale Lua-5.1-Datei setzen:

```sh
"$LUA_BIN" tests/test_app.lua auto_thanks_combat_log_missing_optional_handler_is_ignored
"$LUA_BIN" tests/test_app.lua lifecycle_
"$LUA_BIN" tests/test_feberdin_diagnostics.lua
python3 -m unittest discover -s companion/tests -p test_diagnostics.py -v
```

Der Zwei-Dateien-Test `test_separate_account_snapshot_adds_sanitized_lua_errors_without_network` wurde mit `python3 -m unittest discover -s companion/tests -p test_diagnostics.py -k separate_account -v` zuerst rot ausgeführt (nicht unterstütztes CLI-Argument), danach grün.

Rot: fehlender optionaler Callback führte zum Aufruf eines nil-Werts; die eigene Fehlergrenze erfasste/übergab Fehler noch nicht; der Diagnosebeobachter und die bereinigte Companion-Ausgabe fehlten. Grün: optionale Ereignisse bleiben ohne Modulunterstützung fehlerfrei; eigene Fehler erreichen Diagnose und native Fehleranzeige; nur erlaubte Fehlerorte werden ausgegeben. Die dauerhaften Regressionstests bleiben im Projekt.

## Lokal prüfen und paketieren

```sh
LUA_BIN=lua5.1 sh scripts/check-portable.sh
python3 -m unittest discover -s companion/tests -v
python3 -m unittest discover -s tests -p test_release_package.py -v
python3 -m unittest discover -s tests -p test_issue_templates.py -v
PYTHONPATH=service python3 -m unittest discover -s service/tests -v
python3 -m unittest discover -s tests -p test_ranking_end_to_end.py -v
python3 -m unittest discover -s tests -p test_diagnostics_end_to_end.py -v
node --test service/tests/test_upload_core.cjs service/tests/test_upload_ui.cjs
ruff check service companion scripts/prepare-release.py
ruff format --check service companion scripts/prepare-release.py
shellcheck scripts/check-portable.sh
python3 scripts/prepare-release.py --version 0.10.2 --output dist/0.10.2
```

Die CI enthält außerdem JavaScript-Syntax-, JSON-, XML- und Paketprüfungen. Ein eigener Typecheck ist für dieses Lua-/Python-Projekt nicht konfiguriert. Der Paketgenerator ist der Build-Schritt.

## Installation und Diagnose

Das vollständige Paket lokal installieren, dann außerhalb des Kampfes `/reload` ausführen. Ein zweiter Reload nach der Reproduktion speichert die neuen Diagnosen. SavedVariables niemals als Lua ausführen oder während des Spiels bearbeiten. Companion-Anleitung: `companion/README.md`.

Die lokale Installation wurde vor dem Überschreiben gesichert und alle 29 Addon-Paketdateien anschließend byteweise geprüft. Die nachfolgend gespeicherte Diagnose meldet Version 0.10.2 ohne aufgezeichnete Lua-Fehler. Ein erfolgreicher Ingame-Buff-Test der neuen Version ist noch nicht bestätigt; automatisierte Tests ersetzen die geschützte WoW-Laufzeit nicht.

## Datenschutz und Veröffentlichung

Technische Wartung eines bestehenden Addons; keine neue Website, kein Hosting-Deployment und keine Änderung der Betreiber-/Rechtstexte. Diagnose bleibt lokal und begrenzt; eigene Fehler werden ohne Rohmeldung, Stack, Chat, Spielernamen oder GUID gespeichert. Der Companion führt kein Lua aus und überträgt bei Diagnosebefehlen keine Daten. Private lokale Sicherungen und Rohlogs sind nicht Teil des Commits oder der Paket-Allowlist. Die vorhandenen freiwilligen Online-Funktionen werden nicht neu aktiviert.

GitHub-Veröffentlichung erst nach grüner CI des exakten Commits. CurseForge-Veröffentlichung benötigt eine bestehende Autorenanmeldung oder `CURSEFORGE_API_KEY`; Moderationsfreigabe erst nach überprüfbarem Plattformstatus behaupten.
