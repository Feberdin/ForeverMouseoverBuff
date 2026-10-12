# FMB Community Companion

Lokales, ausdrücklich gestartetes Python-Werkzeug für Diagnose und freiwilliges
Community-Ranking. Der Diagnosebefehl liest ausschließlich erlaubte Diagnosefelder
aus einer ausgewählten SavedVariables-Datei, ohne Netzwerkzugriff. Die getrennten
Rankingbefehle lesen den JSON-Export und können selbst gemeldete Buff-Ereignisse
an den angegebenen Dienst senden. **Keine serververifizierten WoW-Casts, keine
Betrugssicherheit.**

Voraussetzungen: macOS oder Linux mit Python **3.10 oder neuer**. Keine zusätzlichen
Python-Pakete. Kein gestarteter Hintergrunddienst, keine automatische Anmeldung,
keine Installation oder Spielsteuerung durch dieses Verzeichnis.

## Schnellstart

Im Projektordner zunächst die synthetischen Tests ausführen:

```sh
python3 -m unittest discover -s companion/tests -v
python3 companion/companion.py --help
```

## Gespeicherte Diagnose lokal abfragen

Nach einem selbst ausgeführten `/reload` oder Logout in WoW die konkrete
`SavedVariables/ForeverMouseoverBuff.lua` auswählen. Der Befehl steuert WoW nicht
und zeigt den letzten auf Festplatte gespeicherten Stand, keinen Livezustand:

Bei einem frisch installierten Update sind zwei Schritte nötig: Der erste
`/reload` speichert noch den alten Stand und lädt danach die neue Addonversion.
Dann das zu prüfende Verhalten im Spiel auslösen und mit einem zweiten `/reload`
oder Logout die neuen Diagnoseereignisse speichern. Erst anschließend die Datei
erneut abfragen; eine noch alte Versionsnummer nach dem ersten Reload ist möglich.

```sh
python3 companion/companion.py diagnostics \
  --saved-variables '/ABSOLUTER/PFAD/SavedVariables/ForeverMouseoverBuff.lua'
```

Für eine automatische lokale Auswertung denselben Befehl mit `--json` ausführen.
Kein Rankingexport, keine Anmeldung, Token-Datei oder Upload-Zustimmung nötig.
Es entsteht weder eine neue Logdatei noch Netzwerkverkehr. Die Quelldatei wird
nur lesend geöffnet und bleibt unverändert; laufende Schreibvorgänge und Symlinks
werden abgelehnt.

Die Ausgabe enthält nur Addon-/Clientversion, feste Diagnosecodes mit
Schweregrad `INFO`, `WARN` oder `ERROR`, Modul, optionale UTC-Zeit, Diagnosezähler
und öffentliche An-/Aus-Schalter. Niemals Namen, GUIDs, Tastenzuweisungen,
Chattexte, freie Fehlermeldungen, Tokens oder den Quelldateipfad. Schweregrad und
Modul kommen aus demselben festen Codekatalog wie im Addon. Ein unbekannter Code
wird nicht allein wegen eines passenden Präfixes akzeptiert.

Alte Diagnose-Codefolgen bleiben lesbar und werden als Altformat gekennzeichnet.
Fehlende Zähler erscheinen als „nicht gespeichert“. Ungültige einzelne Werte
werden mit einem sichtbaren Hinweis ausgeblendet. Ein unbekanntes Schema,
mehrdeutige ausgewählte Felder, ausführbare Lua-Syntax oder überschrittene Grenzen
brechen mit einem festen Fehlercode ab. Der Reader führt keine Lua-Datei aus und
repariert keine Spieldaten. Grenzen: 8 MiB Datei, 64 Verschachtelungsebenen,
250.000 Parser-Tokens, 64 Ereignisse und 40 ältere Codes; Diagnosezähler höchstens
eine Milliarde. Ereignisse und Zähler sind lokal editierbar und keine unabhängigen
Belege tatsächlicher Spielereignisse.

## Freiwilliges Ranking

Alle folgenden Pfade und Namen sind Platzhalter. Den **konkreten Charakterpfad**
zu dessen `SavedVariables/ForeverMouseoverBuff.lua` wählen. Der Companion prüft
keine Charakteridentität anhand des Exports; richtige Zuordnung von Charakter,
Realm und Datei bleibt eine bewusste Nutzerentscheidung.

Zuerst ohne Netzwerk prüfen:

```sh
python3 companion/companion.py inspect \
  --saved-variables '/ABSOLUTER/PFAD/SavedVariables/ForeverMouseoverBuff.lua'
```

Für den freiwilligen Browser-Upload kann stattdessen eine kleine JSON-Datei lokal erzeugt werden:

```sh
python3 companion/companion.py export \
  --saved-variables '/ABSOLUTER/PFAD/SavedVariables/ForeverMouseoverBuff.lua' \
  --output '/ABSOLUTER/PFAD/ZUR/NEUEN/ranking.json'
```

Dieser Befehl erzeugt **keine Anmeldung und keinen Netzwerkverkehr**. Er verwendet den vorhandenen strikten Parser und schreibt nur die validierten Rankingfelder in eine neue Datei mit `0600`. Die Eingabedatei bleibt unverändert; vorhandene Ausgabedateien oder Symlinks werden nicht überschrieben. Fehlender Zielordner, falsche Endung oder eine bereits vorhandene Datei erzeugen feste `OUTPUT_*`-Fehler. Die neue JSON-Datei ist für die Dateiauswahl der lokalen Rankingseite gedacht. Dort folgen Vorschau, freiwillige Teilnahme und eine getrennte Upload-Zustimmung. Die ganze WoW-Datei wird nicht an die Website übertragen.

Die Ausgabe enthält nur Status, Schalter und Ereignisanzahl, keine Namen oder
einzelnen Ereignisse. Anschließend nur bei gewünschter Teilnahme am gewählten Ranking:

```sh
python3 companion/companion.py enroll \
  --endpoint 'http://127.0.0.1:18449' \
  --name 'Synthetic' --realm 'Testrealm' \
  --saved-variables '/ABSOLUTER/PFAD/SavedVariables/ForeverMouseoverBuff.lua' \
  --config "$HOME/Library/Application Support/Feberdin/ForeverRanking/participant.json" \
  --consent
```

Der lokale Beispiel-Endpunkt setzt einen bereits gestarteten Testdienst voraus.
Er ist keine Zusage einer laufenden Installation. Ein entfernter Dienst benötigt
eine ausdrücklich gewählte **HTTPS-Adresse ohne Unterpfad**. Nur exakte Loopback-
Adressen bzw. `localhost` dürfen HTTP verwenden. Zertifikatsprüfung bleibt aktiv;
Umgebungs-Proxys und Redirects werden nicht übernommen.

Anmeldung übermittelt genau Namen, Realm, Klasse `PALADIN` und Zustimmung an den
Dienst. Namen/Realm können dort öffentlich sichtbar sein. Ohne `--consent`
findet keine Anmeldung statt. Vorhandene Konfiguration wird nicht überschrieben.

Einmal übertragen oder bewusst bis Strg+C beobachten:

```sh
python3 companion/companion.py sync \
  --config "$HOME/Library/Application Support/Feberdin/ForeverRanking/participant.json"
python3 companion/companion.py watch --interval 10 \
  --config "$HOME/Library/Application Support/Feberdin/ForeverRanking/participant.json"
```

`watch` ist nur ein Vordergrundprozess, installiert keinen Autostart und fragt
höchstens einmal je zehn Sekunden ab. Identische Statusmeldungen bleiben still;
`--debug` **vor dem Befehl** zeigt auch unveränderte anonyme Ergebnisse.

## Ausschalten und Teilnahme löschen

**Sofort nichts mehr übertragen:** einen laufenden Companion mit Strg+C stoppen.
Der WoW-Schalter `/fmb ranking off` wird für den Companion erst sichtbar, wenn
WoW die SavedVariables durch einen selbst ausgeführten Reload/Logout schreibt.
Bis dahin kann auf der Festplatte noch der frühere ON-Stand stehen. Der Companion
kann den aktuellen Ingame-Arbeitsspeicher nicht sehen und verändert ihn nicht.

Der gespeicherte OFF-Export enthält keine Ereignisse; `sync` sendet dann nichts.
Das entfernt aber keine früher hochgeladenen Daten. Teilnahme samt zugehöriger
Serverdaten ausdrücklich löschen:

```sh
python3 companion/companion.py leave \
  --config "$HOME/Library/Application Support/Feberdin/ForeverRanking/participant.json"
```

Die lokale Token-Datei wird **erst nach bestätigter Serverlöschung** entfernt.
Bei Netzwerk-/Authentifizierungsfehler bleibt sie zur Wiederholung erhalten.
Wenn eine Serverlöschung erfolgreich war, ihre Antwort aber verloren geht, kann
ein erneuter Aufruf `AUTH_REQUIRED` ergeben. Dann beim Dienst prüfen lassen;
keine erfolgreiche Löschung behaupten und keinen Token in eine Supportnachricht
kopieren. Ein Tokenverlust kann den selbstständigen Löschweg verhindern.

## Daten und Schutzgrenzen

Der Companion liest keine übrigen Charakterdaten fachlich aus. Die Rankingbefehle
prüfen die SavedVariables-Literalstruktur, um die eine globale Zuweisung
`ForeverMouseoverBuffRankingExport = "JSON"` sicher zu finden. Der Diagnosebefehl
wählt ausschließlich erlaubte Felder unter `ForeverMouseoverBuffDB.diagnostics`.
Keine Ausführung
von Lua/Python, kein `eval`, keine dynamischen Imports aus Spieldateien.
Strings, lange Strings, Kommentare und verschachtelte Tabellenschlüssel können
keine falsche globale Zuweisung erzeugen. Doppelte Zuweisungen oder ausführbare
Lua-Ausdrücke werden abgelehnt. Unbekannte JSON-Felder ebenfalls.

```json
{"schema":1,"enabled":true,"casterClass":"PALADIN","events":[{"id":"1791763200-1","spellId":20217,"eventTime":1791763200}]}
```

Es werden ausschließlich diese Ereignisfelder übertragen: ID, bekannte normale
Segens-Spell-ID und Unixzeit. Keine Ziele, Empfängernamen, GUIDs, Chattexte,
Ausrüstung oder Aufenthaltsorte. Der Dienst erhält zusätzlich technisch bedingt
die Netzwerkverbindung; diese Tatsache macht selbst gemeldete Daten nicht anonym.
Das vorhandene Exportformat enthält keine Namensbindung und ist editierbar.

Schranken: Datei 8 MiB, dekodierter Export 1 MiB, 1.000 Ereignisse, 64
Verschachtelungsebenen, 250.000 Parser-Tokens, 100 Ereignisse/HTTP-Paket,
32 KiB HTTP-Anfrage/-Antwort, zehn Sekunden Netzwerk-Timeout. Daten werden aus
einem unveränderten Datei-Snapshot gelesen; Teilstände werden nicht hochgeladen.
Watch wiederholt vorübergehende Dateifehler frühestens nach dem Pollintervall.

Zukünftige Ereignisse über fünf Minuten brechen mit `CLOCK_SKEW` ab. Ereignisse
älter als sieben Tage werden mit `expired`-Anzahl ausgelassen. Sie sind außerhalb
des Serverfensters und dürfen neue Ereignisse nicht blockieren. Durch seltenes
Reload/Logout, den Ringpuffer oder einen längeren Ausfall können Ereignisse fehlen.

Jeder Sync sendet die aktuelle zulässige Ringmenge erneut. Der Server dedupliziert
Event-IDs; lokal entstehen weder Quittungsdatenbank noch zusätzliche Historie.
`accepted`, `duplicates` und `quarantined` sind getrennte Serverergebnisse.
Quarantäne ist keine bestätigte Wertung. Mehrere Batches sind einzeln atomar;
ein späterer Paketfehler rollt schon bestätigte frühere Pakete nicht zurück.
Ein erneuter Sync ist dank Server-Deduplizierung vorgesehen.

## Token-Datei

Konfiguration enthält Endpunkt, Quelldateipfad, Teilnehmer-ID, Token und erfolgte
Zustimmung. **Keinen Token in Addon, Chat, Git, Log oder Kommandozeilenparameter
kopieren.** Der Companion schreibt die Datei atomar mit `0600` in einen eigenen
Ordner mit `0700`; er ändert Rechte vorhandener Verzeichnisse nicht eigenmächtig.
Datei und direkter Elternordner müssen dem ausführenden Benutzer gehören.

Spielverzeichnisse, `WTF`, `Interface`, `AddOns` und der Quellordner sind als
Token-Ziel ausgeschlossen. Symlinks einschließlich Elternpfaden und Hardlinks auf
die Konfigurationsdatei werden abgelehnt. Auf macOS ggf. den tatsächlichen Pfad
statt `/var` verwenden, wenn dieser Systemalias ein Symlink ist. Dateirechte
schützen nicht vor Programmen mit denselben Benutzerrechten, Administratoren oder
bereits kompromittierten Rechnern. Backups können die Token-Datei mit sichern.

Scheitert das Speichern nach erfolgreicher Anmeldung, versucht der Companion
einmal die neu erstellte Teilnahme zu löschen. Der Status unterscheidet bestätigte
Kompensation und fehlgeschlagene Kompensation; Token werden nie als Ausweg gedruckt.
Anmeldeanfragen werden bei unklarem Ausgang nicht automatisch wiederholt.

## Fehler und Debugging

Rankingausgabe besteht aus begrenztem JSON auf stdout. Die Diagnose zeigt
standardmäßig einen lesbaren Bericht, mit `--json` strukturierte Daten. Fehler
bestehen aus festem Code und Handlungshinweis als JSON auf stderr. Keine
Rohantworten, Stacktraces, Namen oder Tokens.
Exitcode 0: abgeschlossen/gestoppt, 2: bekannter Eingabe-/Systemfehler, 1:
unerwarteter interner Fehler. Es gibt keine zusätzliche persistierte Logdatei.

| Code/Status | Nächster Schritt |
| --- | --- |
| `DIAGNOSTICS_OK` | Gespeicherter Diagnosestand gelesen; kein Beleg eines aktuellen Livezustands |
| `DIAGNOSTICS_MISSING` | Addonversion und ausgewählte Datei prüfen; nach eigenem Reload/Logout erneut lesen |
| `DIAGNOSTICS_SCHEMA`, `DIAGNOSTICS_SYNTAX`, `DIAGNOSTICS_LIMIT` | Aktuelles Addon/Companion verwenden; Eingabe nicht ausführen, Grenzen nicht umgehen |
| `DIAGNOSTICS_FIELDS_FILTERED`, `DIAGNOSTICS_LEGACY`, `DIAGNOSTICS_NO_EVENTS` | Bericht mit Einschränkungen gelesen; Hinweis beachten, fehlende Daten nicht als Null interpretieren |
| `EXPORT_VALID`, `SYNCED` | Export geprüft bzw. alle aktuellen Pakete beantwortet; weiterhin nur selbst gemeldet |
| `EXPORT_DISABLED` | Gespeicherter OFF-Stand; kein Upload |
| `EXPORT_MISSING`, `EXPORT_SYNTAX`, `SOURCE_UNSTABLE` | Nach eigenem Reload/Logout erneut lesen; Datei nicht reparieren oder ausführen lassen |
| `EXPORT_SCHEMA`, `SOURCE_TOO_LARGE`, `EXPORT_TOO_LARGE` | Version/Format bzw. Größe prüfen; Grenzen nicht umgehen |
| `CONFIG_LOCATION`, `PATH_SYMLINK` | Echte private Datei außerhalb WoW/Quellordner wählen |
| `CONFIG_PERMISSIONS` | Eigener direkter Elternordner `0700`, Datei `0600`; keinen allgemein genutzten Ordner umstellen |
| `CONFIG_EXISTS` | Bestehende Teilnahme mit sync/leave verwenden; andere eigene Figur benötigt andere Datei |
| `CONSENT_REQUIRED` | Nur nach bewusster Entscheidung `--consent` verwenden |
| `ENDPOINT_INVALID`, `ENDPOINT_REDIRECT` | Direkte HTTPS-/Loopback-Basisadresse ohne Redirect auswählen |
| `AUTH_REQUIRED` | Token/Teilnahmestatus beim Dienst prüfen; nichts heimlich neu anmelden |
| `SERVER_CONFLICT` | Identität oder Event-ID kollidiert; keine künstlichen neuen IDs erzeugen |
| `SERVER_VALIDATION`, `RESPONSE_INVALID` | Vertrag/Version/Uhr prüfen; keine Teilannahme behaupten |
| `RATE_LIMITED`, `NETWORK_UNAVAILABLE` | Verbindung bzw. späteren Versuch abwarten; Watch bleibt mindestens zehn Sekunden begrenzt |
| `CLOCK_SKEW`, `CLOCK_INVALID` | Systemzeit prüfen |
| `ENROLL_SAVE_FAILED_ROLLED_BACK` | Anmeldung wieder gelöscht; lokale Rechte/Speicher zuerst korrigieren |
| `ENROLL_SAVE_AND_CLEANUP_FAILED` | Anmeldung könnte bestehen; Dienstbetreiber kontaktieren, keine erfolgreiche Löschung behaupten |

## Entwicklung und Prüfen

```sh
python3 -m unittest discover -s companion/tests -p test_diagnostics.py -v
python3 -m unittest discover -s companion/tests -v
python3 -m compileall -q companion
ruff check companion
ruff format --check companion
```

Ruff ist nur für Entwicklungschecks nötig; Betrieb und Tests benötigen nur die
Standardbibliothek. Kein separater Typechecker oder Paket-Build ist eingerichtet.
[Lokal ausführbare Prüfungen](#entwicklung-und-prüfen),
[Mitarbeit](CONTRIBUTING.md). Lizenz: bestehende [Projektlizenz](../LICENSE).

Es wurden keine echte Teilnahme, echter Upload, Autostart, öffentlicher Endpunkt
oder laufender Spieler eingerichtet. Veröffentlichung/Deployment bleiben ein
separater Auftrag mit den dafür erforderlichen Prüfungen.
