# Änderungen am Companion

Python 3.10+, ausschließlich Standardbibliothek. Produktionscode liegt in kleinen
Modulen: `export.py` für den nicht ausführenden Parser, `storage.py` für sichere
Dateigrenzen, `client.py` für den API-Vertrag, `diagnostics.py` für die lokale
Diagnoseprojektion und `cli.py` für die begrenzte Ausgabe.
Jede Datei erklärt Zweck, Eingaben, Ausgaben und wichtige Invarianten.

`diagnostic_codes.py` enthält einen ausdrücklich geprüften festen Codekatalog.
Der Vertragstest in `tests/test_diagnostics.py` gleicht ihn vollständig mit der
Lua-Registry in `src/ForeverMouseoverBuff/Diagnostics.lua` ab. Neue Codes erfordern
eine Änderung beider Kataloge. Unbekannte Felder, freie Texte und ein passender
Codepräfix allein dürfen keine Daten in die Diagnoseausgabe einschleusen.
Der Diagnosebefehl erstellt keine `Companion`-Netzinstanz, benötigt keinen Token
und verändert keine SavedVariables. Tests sichern diese Grenze am CLI-Einstieg.

1. Fachliches Verhalten und Datengrenzen festlegen.
2. Kleinsten gezielten unittest schreiben und am vorherigen gültigen Code fachlich
   rot sehen. Fehlende Imports/Fixtures zählen nicht als Rot-Nachweis.
3. Minimal implementieren, fokussiert grün, anschließend gesamte Suite.
4. Erst danach ohne Verhaltensänderung formatieren/refactoren und erneut prüfen.
5. Änderungen an JSON/API zusammen mit Lua-Export und Dienst vertraglich prüfen.

```sh
python3 -m unittest discover -s companion/tests -p test_diagnostics.py -v
python3 -m unittest discover -s companion/tests -v
python3 -m compileall -q companion
ruff check companion
ruff format --check companion
```

Befehle laufen vom übergeordneten Projektordner. Tests benutzen ausschließlich
synthetische Charakterdaten, temporäre Verzeichnisse und eine ersetzte HTTP-Grenze.
Der getrennte Ende-zu-Ende-Test darf einen temporären Loopback-Dienst und eine
temporäre Datenbank verwenden. Nie echte Exportdateien, Tokens oder Konten als
Fixtures einchecken. Niemals Lua ausführen, um eine Spielerdatei einzulesen.

Fehlermeldungen bleiben feste Codes; keine URL-/Pfad-/Response-/Exception-Rohdaten
ausgeben. Die einzige breite Exception-Grenze ist bewusst das CLI-Ende, das einen
sichtbaren `INTERNAL_ERROR` statt eines möglicherweise privaten Tracebacks ausgibt.
Der gezielte Ruff-Kommentar begründet diese Ausnahme; Fachlogik schluckt keine
Fehler still.

Neue Storage-/Netzwerk-/öffentliche Felder benötigen eine erneute datensparsame
Planung. Keine selbst gemeldeten Werte in verifizierte Werte umbenennen. Eine
Server-Signatur über ungeprüfte Clientdaten ist kein Beleg echter WoW-Ereignisse.
