# Am lokalen Ranking mitarbeiten

1. `README.md` und `../CONTRIBUTING.md` lesen; keine Produktivdaten/Spielernachrichten in Tests verwenden.
2. Vor jeder fachlichen Änderung einen gezielten HTTP-/SQLite-Test schreiben, die tatsächliche fachliche Rot-Phase festhalten und erst danach implementieren.
3. Bestehende API-Felder nicht still ändern. Der Companion verwendet strikte Schemata; `openapi.json` und Integrationsprüfungen gemeinsam anpassen.
4. Geheimnisse und Identitäten niemals loggen. Nur feste Codes und anonyme Summen; SQL-Werte immer binden. Im Browser ausschließlich `textContent`, keine HTML-Interpolation aus API-Daten.
5. Alle Daten bleiben `self_reported`. Weder Code, Texte noch Tests dürfen aus einem lokalen Erfolgssignal einen serverbestätigten Zauber machen.
6. Nach grünem Teststand mit Ruff formatieren und die README-Prüfbefehle ausführen. Ein zusätzlicher Test soll echte fachliche Fehler erkennen, nicht nur Implementierungsdetails spiegeln.
7. Öffentliche Bereitstellung ist eine separate Aufgabe mit Datenschutz-/Freigabeprüfung. Dieser Ordner autorisiert weder Cloud-Upload noch Deployment.

Die API ist absichtlich auf die in FMB vorhandenen Paladinsegen begrenzt. Weitere Klassen benötigen zuerst einen belegten Zauberkatalog, addonseitige Erfolgskorrelation, Tests und eine Versionierung des API-Vertrags.
