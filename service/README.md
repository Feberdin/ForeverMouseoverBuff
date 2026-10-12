# FMB Community-Ranking – lokaler Prototyp

Dieser eigenständig lauffähige Dienst sammelt **einzelne gemeldete Buff-Ereignisse**, zählt sie in SQLite und zeigt deutsche Ranglisten für Charaktere, Klassen und Segensarten. Python 3.10+ genügt; es gibt keine Bibliotheksabhängigkeiten und keine externen Dashboard-Ressourcen. Aktuell sind ausschließlich die 20 normalen Paladinsegen-IDs aus FMB unterstützt: Macht, Weisheit und Könige einschließlich ihrer Ränge. Große Segen, fremde Klassen und außerhalb von FMB gewirkte Zauber gehören noch nicht zum Umfang.

**Alle Daten sind `self_reported`, also nicht durch einen Spielserver bestätigt.** Der Dienst bestätigt weder den Charakterbesitz noch tatsächlich ausgeführte Zauber. Dieses ist ein Community-Zähler, kein manipulationssicherer Wettbewerb.

## Quickstart

Vom Projektordner aus:

```sh
cd service
python3 server.py --host 127.0.0.1 --port 18449 --db ./data/ranking.sqlite3
```

Danach <http://127.0.0.1:18449> öffnen. `Ctrl+C` beendet den Dienst. Standardmäßig ist er nur auf diesem Rechner erreichbar. Das Dashboard lädt bei Aufruf, Filterwechsel oder Klick auf „Aktualisieren“; es gibt kein Hintergrundtracking.

Die Seite bietet einen freiwilligen Upload einer kleinen Ranking-JSON-Datei mit lokaler Vorschau. Die Desktop-Bridge im angrenzenden `companion/`-Ordner kann diese Datei ohne Netzwerk erzeugen oder nach ausdrücklicher Anmeldung selbst übertragen. **Das WoW-Addon selbst kann keine HTTP-Verbindung herstellen.** Der Spielchat wird für dieses Ranking nicht als Transport verwendet.

## Freiwilliger Upload über die Seite

1. Im Spiel `/fmb ranking on` aktivieren. Erst ein selbst ausgeführter Reload/Logout schreibt den neuen Stand in die SavedVariables-Datei.
2. Aus dem Projektordner ausschließlich die Rankingdaten lokal extrahieren:

   ```sh
   python3 companion/companion.py export \
     --saved-variables '/PFAD/ZUM/CHARAKTER/SavedVariables/ForeverMouseoverBuff.lua' \
     --output '/PFAD/ZUR/NEUEN/ranking.json'
   ```

   Das verwendet denselben strikten Lua-Literalparser wie der Companion: keine Ausführung, kein Netzwerk, keine automatische Anmeldung. Die neue Datei enthält nur Schema, Export-Schalter, Klasse und bekannte Einzelereignisse. Vorhandene Ausgabedateien werden nicht überschrieben; eine neue Datei erhält Dateirechte `0600`.
3. Unter „Eigene Buffs freiwillig übertragen“ die erzeugte JSON-Datei auswählen. Die Seite prüft sie **nur lokal im Browser** und zeigt Anzahl, Segensarten und Zeitraum. Ganze `.lua`-Dateien werden hier nicht angenommen und niemals zum Dienst gesendet.
4. Eine bestehende Zugangssicherung/Companion-Konfiguration lokal laden oder bewusst eine neue Teilnahme mit Namen/Realm/Zustimmung anlegen. Beim Laden geht nur der Zugangstoken an genau denselben Dienst, damit das eigene Profil angezeigt werden kann; keine Quelldateipfade oder vollständigen Konfigurationsdateien werden übertragen.
5. Neue Zugänge über den separaten Button „Zugang sichern“ bewusst herunterladen. Der Browser speichert Tokens weder in Local Storage, Session Storage noch IndexedDB. Ohne bewusste Sicherung gehen sie beim Schließen der Seite verloren; ein Namensbesitz-Nachweis oder automatischer Wiederherstellungsweg existiert nicht. Der Download ist eine private JSON-Datei mit Endpunkt und Zugang, keine Verschlüsselung. Der Browser kann ihren tatsächlichen Speicherort, Dateirechte oder erfolgreiche dauerhafte Aufbewahrung nicht prüfen.
6. Vorschau und aktiven Charakter prüfen, die Upload-Zustimmung aktivieren und „Jetzt Ranking-Ereignisse übertragen“ klicken. Erst dann werden Ereignisse in Paketen zu höchstens 100 gesendet. Ergebnis: angenommen, bereits vorhanden oder Quarantäne. Ereignisse älter als sieben Tage werden sichtbar ausgelassen. Der Export bleibt selbst gemeldet.
7. „Zugang aus Sitzung entfernen“ vergisst nur den RAM-Zugang. Unter „Teilnahme und hochgeladene Daten löschen“ erfolgt nach eigener Bestätigung die Löschung im Dienst. Eine verlorene Antwort ist kein Nachweis einer erfolgreichen Löschung; bei Unsicherheit bleibt der Zugang erhalten.

Bei einem Paketfehler zeigt die Seite bereits bestätigte Paketergebnisse und den möglicherweise unklaren Ausgang des letzten Pakets an. Es gibt keine automatischen Wiederholungen. Eine bewusste erneute Übertragung dedupliziert dieselben Ereignisse serverseitig. Während einer Aktion sind Auswahl/Schalter gegen versehentliche parallele Änderungen gesperrt.

Die API und der Browser nehmen keine Summen aus lokalen Dateien als Rankingpunkte an. Ein editierter Client kann dennoch plausible Einzelereignisse erfinden. Weder Token, lokale Verschlüsselung noch Dateiprüfung machen das Ranking manipulationssicher.

## API-Vertrag

Alle Requests/Antworten verwenden JSON. POST benötigt `Content-Type: application/json` und eine eindeutige `Content-Length`. Keine Weiterleitungen, CORS-Freigaben, Cookies oder Chunked-Requests. Maximale Body-Größe: 32.768 Bytes. Doppelte JSON-Schlüssel, zusätzliche Felder, `NaN` und `Infinity` werden abgewiesen. Der vollständige Vertrag steht in `openapi.json`; dort sind ausschließlich synthetische Beispiele enthalten.

| Aktion | Request | Erfolg |
|---|---|---|
| Freiwillig anmelden | `POST /v1/participants` mit `{displayName, realm, casterClass:"PALADIN", consent:true}` | HTTP 201: `{participantId, token, trust:"self_reported"}` |
| Ereignisse senden | `POST /v1/events`, `Authorization: Bearer …`, `{events:[{id,spellId,eventTime}]}` | HTTP 200: `{accepted, duplicates, quarantined, trust:"self_reported"}` |
| Rangliste anzeigen | `GET /v1/leaderboard?group=players&limit=50` | HTTP 200: `{group, rows, total, trust, scope, generatedAt}` |
| Eigenen Zugang zuordnen | `GET /v1/participant`, Bearer wie beim Upload | HTTP 200: `{participantId, displayName, realm, casterClass, trust}` |
| Teilnahme löschen | `DELETE /v1/participant`, Bearer wie beim Upload, **kein Body** | HTTP 200: `{deleted:true, trust:"self_reported"}` |
| Dienststatus | `GET /health` | HTTP 200: `{ok:true, version, trust:"self_reported"}` |

`participantId` ist eine zufällige UUID als 32 Hexzeichen. Der Zugangstoken besteht aus 43 URL-sicheren Zeichen und wird **nur bei Anmeldung einmal zurückgegeben**. Er ist ein Zugang zur gemeldeten Identität, kein Nachweis ihres Besitzes. Der Companion speichert ihn außerhalb des WoW-Ordners mit eingeschränkten Dateirechten; niemals im Chat, Git oder Log veröffentlichen. Geht der Zugang verloren, benötigt die lokale Datenbankverwaltung eine manuelle, sorgfältige Wiederherstellung; diese Version bietet keinen Identitätsbeweis oder automatischen Kontowiederherstellungsweg.

Eine Ereignis-ID enthält 8–96 ASCII-Buchstaben, Ziffern, Bindestriche oder Unterstriche. `eventTime` ist eine ganze Unixzeit in Sekunden. Neue Ereignisse dürfen maximal sieben Tage zurückliegen oder fünf Minuten voraus sein. Ein Batch enthält 1–100 Ereignisse. Ein identischer bereits gespeicherter Datensatz bleibt auch später ein gültiger Replay.

`accepted + duplicates + quarantined` entspricht der Batchlänge; die Kategorien überschneiden sich nicht. Derselbe Ereignisschlüssel zählt einmal. Wird der Inhalt derselben ID verändert, wird der **gesamte Batch** mit HTTP 409 zurückgerollt. Auch ein Validierungsfehler führt zur vollständigen Rücknahme des Batches. Wiederholungen quarantinierter Ereignisse bleiben Duplikate und zählen weiterhin nicht zum Ranking.

Optionale Ranking-Filter:

- `group=players|classes|buffs`, Standard `players`.
- `limit=1..100`, Standard 50.
- `class=PALADIN`, andere Klassen sind noch nicht implementiert.
- `buff=might|wisdom|kings`.

Beispiele: `/v1/leaderboard?group=players&buff=wisdom` zeigt die besten gemeldeten Weisheits-Buffer; `group=buffs` zählt die Segensarten. Verschiedene Ränge desselben Segens werden zusammengefasst. Gleichstände teilen sich den Rang (`1, 1, 3`). Quarantinierte Ereignisse fehlen in allen Ranglisten.

## Plausibilität und verbleibende Manipulationsmöglichkeiten

Der Server akzeptiert **keine Summen, Ränge, frei gewählten Klassen-/Buff-Zuordnungen oder Verifizierungsbehauptungen**. Jeder Punkt entsteht aus einer erlaubten Ereignis-ID mit bekanntem Zauber. Pro Teilnehmer werden höchstens 60 Ereignisse innerhalb einer gemeldeten UTC-Minute und 10.000 pro gemeldetem UTC-Tag angenommen. Weitere Ereignisse bleiben mit `MINUTE_LIMIT` oder `DAY_LIMIT` in Quarantäne. Die Prüfungen beziehen sich auf die gemeldete Zauberzeit, damit ein normaler nachträglicher Datei-Upload nicht pauschal verworfen wird.

Diese Grenzen sind Plausibilitätsfilter, keine Spielregeln und kein Beweis. Ein veränderter Client kann **neue IDs, plausible Zeitabstände und erfundene Zauber** erzeugen. Gefälschte Ereignisse innerhalb der Grenzen können Punkte erhalten; mehrere Konten sind möglich. Namens-/Realm-Besitz ist nicht verifiziert. Wer zuerst einen fremden Namen registriert, kann ihn reservieren. Daher keine Preise, Geld, Wettbewerbsvorteile oder Aussagen über objektive Spielleistung an die Zahlen knüpfen.

Zusätzlich gelten pro Prozess maximal acht Anmeldeversuche pro Stunde/Verbindungspartner und 120 authentifizierte Requests pro Minute/Teilnehmer. Diese temporären Limits gehen bei Neustart verloren. Hinter einem Reverse-Proxy teilen dessen Verbindungen denselben Partner; ungeprüfte `X-Forwarded-For`-Header werden bewusst nicht vertraut. Die Register begrenzen sich auf 4.096 anonyme RAM-Einträge und 32 gleichzeitige HTTP-Worker. Diese einfachen Grenzen ersetzen keinen Schutz durch einen produktiven Reverse-Proxy.

## Daten und freiwillige Teilnahme

Gespeichert werden Teilnehmer-ID, angegebener Charaktername/Realm, Klasse, Hash des Zugangstokens, Einwilligungszeit und pro Ereignis ID, Zauber-ID, Segensart, gemeldete Zeit, tatsächliche Empfangszeit, Annahme-/Quarantänestatus. **Keine Buff-Empfänger, Chattexte, Spielorte, Ausrüstung, Spiel-GUIDs, IP-Adressen oder Klartexttokens** werden in SQLite gespeichert. Bei aktiviertem Dienst sind Name/Realm und aggregierte Zahlen im lokalen Dashboard sichtbar.

Daten bleiben bis zur Löschung der Teilnahme erhalten. `DELETE /v1/participant` entfernt Teilnehmer, Token-Hash und sämtliche dazugehörigen Ereignisse durch die SQLite-Fremdschlüsselbeziehung. Alte Zugangstokens funktionieren danach nicht mehr. Separat erstellte Sicherungen müssen ebenfalls nach einer dokumentierten Aufbewahrungsfrist entfernt werden; die API verändert keine externen Backups. Es gibt kein automatisches erneutes Anmelden.

## Debugging und Fehlermeldungen

```sh
python3 server.py --db ./data/ranking.sqlite3 --debug
```

Logs gehen nach stderr. INFO zeigt Version, Port, Start/Stop, Anmeldung/Löschung und anonyme Batchsummen. DEBUG ergänzt feste Ablehnungscodes. ERROR enthält den Fehlerklassennamen, keine Requestdaten, Namen, Tokens, Header oder SQL-Werte. Es werden keine persistenten Requestlogs angelegt. Meldungen nicht mit fremden Reverse-Proxy-Zugriffslogs vermischen.

| Fehler | Bedeutung und nächster Schritt |
|---|---|
| `CONSENT_REQUIRED` / 400 | Ausdrückliche Teilnahme fehlt; Anmeldung im Companion bewusst bestätigen. |
| `INVALID_FIELDS` / 400 | Unbekannte/fehlende Felder; `openapi.json` und Exportversion prüfen. |
| `EVENT_TIME_WINDOW` / 400 | Neuer Export zu alt oder Uhr falsch; Systemzeit/aktuellen Export prüfen. |
| `AUTH_REQUIRED` / 401 | Zugang fehlt oder wurde gelöscht; lokale Companion-Konfiguration prüfen. |
| `HOST_REJECTED` / 403 | Exakte Dienstadresse einschließlich Port verwenden. |
| `IDENTITY_EXISTS` / 409 | Name/Realm schon angemeldet; bestehenden Zugang verwenden. |
| `ID_CONFLICT` / 409 | Identische Ereignis-ID mit verändertem Inhalt; Export nicht nachträglich editieren. |
| `RATE_LIMIT` / 429 | Warten; keine automatischen endlosen Retries. |
| `SERVICE_UNAVAILABLE` / 503 | stderr sowie Datenbankordner/Dateirechte prüfen. |
| `START_FAILED` | Datenbankordner muss beschreibbar sein, Port muss frei sein; bestehende Datenbankversion prüfen. |

Datenbanksicherungen bei gestopptem Dienst kopieren oder über die SQLite-Backup-API erstellen; laufende WAL-Dateien nicht unkoordiniert kopieren. Tokens sind nicht wiederherstellbar aus ihren SHA-256-Hashes.

## Testen

```sh
cd service
python3 -m unittest tests.test_service.ServiceTests.test_enrollment_requires_explicit_consent_and_stores_only_token_hash -v
python3 -m unittest discover -s tests -v
ruff check server.py tests
ruff format --check server.py tests
python3 -m py_compile server.py tests/test_service.py
python3 -m json.tool openapi.json >/dev/null
node --check static/app.js
node --check static/upload-core.js
node --check static/upload.js
node --test tests/test_upload_core.cjs tests/test_upload_ui.cjs
```

`ruff` und `node` sind ausschließlich optionale Entwickler-Prüfwerkzeuge, keine Laufzeitabhängigkeiten. Die Tests starten echte HTTP-Server nur auf zufälligen Loopback-Ports und verwenden temporäre SQLite-Dateien, synthetische Namen und einen festen Testzeitpunkt. Sie senden keine Nachrichten ins Spiel und kontaktieren keine Produktivkonten. Ein gesonderter Build oder Typechecker ist nicht eingerichtet.

## Spätere gemeinsame Veröffentlichung

**Dieser Stand wird nur lokal getestet. Es ist kein öffentliches Ranking freigeschaltet.** Für ein gemeinsames Angebot müssen Hosting, endgültige Domain, Datenschutztext/Einwilligung/Löschweg, Moderation missbrauchter Namen, Backup-Fristen und ein TLS-Reverse-Proxy geprüft werden. `http.server` ist ein kleiner lokaler Prototyp, kein alleiniger öffentlicher Produktionsserver. Direkte öffentliche Freigabe ohne vorgeschaltete Absicherung ist nicht vorgesehen.

`--public-origin https://ranking.example.invalid` erlaubt später genau diesen Host/Browser-Ursprung; externe Bindung wird ohne diese Angabe abgelehnt. Eine spätere Veröffentlichung auf einem verwalteten Server verwendet ausschließlich dessen freigegebenen Deploymentweg einschließlich Plan und gegebenenfalls Freigabe. Lokaler Teststart erteilt keine Veröffentlichungsfreigabe.

## Lizenz

Es gilt die MIT-Lizenz aus `../LICENSE`. WoW, Zaubernamen und Marken bleiben ihren jeweiligen Rechteinhabern zugeordnet.
