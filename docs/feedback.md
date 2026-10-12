<!-- Purpose: explain FMB's user-controlled GitHub feedback flow and its data boundary.
Input: a player's issue or idea. Output: an optional, reviewed public GitHub report.
Invariant: no addon HTTP submission, credentials, private messages or complete log export.
Debug: compare the prepared URL's template/field IDs with the issue-form contract tests. -->

# 💬 Feedback & Hilfe

<img src="../release/assets/project-icon.png" width="96" alt="Forever Mouseover Buff mit Feberdin-Ritter" />

Eine gute Rückmeldung beginnt direkt im Spiel. Forever Mouseover Buff bereitet
dafür einen Link zur passenden GitHub-Vorlage vor. Du ergänzt und veröffentlichst
deine Meldung anschließend selbst im Browser.

## So meldest du etwas

1. Öffne **Feedback & Hilfe** im Addon oder gib `/fmb feedback` ein.
2. Wähle **Fehler**, **Wunsch** oder **Neue Funktion**.
3. Entscheide, ob du technische Angaben ergänzen möchtest, und prüfe die Vorschau.
4. Kopiere den vorbereiteten Link mit `Strg+C` beziehungsweise `Cmd+C` und öffne
   ihn im Browser.
5. Melde dich bei GitHub an, ergänze einen aussagekräftigen Titel und die kurzen
   Fragen der Vorlage. Prüfe alles noch einmal, bevor du **Submit new issue**
   anklickst.

Das Addon schickt keinen Bericht ab und benötigt keinen GitHub-Token. WoW-Addons
können diese GitHub-Meldung nicht direkt per HTTP absenden. Ein GitHub-Konto ist
erst für die Veröffentlichung im Browser nötig.

## Welche Vorlage passt?

| Vorlage | Wofür? | Ein gutes Beispiel |
| --- | --- | --- |
| [🐞 Fehlerbericht](https://github.com/Feberdin/ForeverMouseoverBuff/issues/new?template=01-bug.yml) | Eine vorhandene Funktion verhält sich falsch. | „Nach einem Tastendruck fehlt der Hinweis, warum kein Buff möglich ist.“ |
| [✨ Wunsch & Verbesserung](https://github.com/Feberdin/ForeverMouseoverBuff/issues/new?template=02-wish.yml) | Eine vorhandene Funktion soll angenehmer werden. | „Ich wünsche mir eine Tonvorschau neben der Auswahl.“ |
| [🚀 Neue Funktion](https://github.com/Feberdin/ForeverMouseoverBuff/issues/new?template=03-feature.yml) | Eine neue Fähigkeit soll hinzukommen. | „Ich möchte getrennte Einstellungen für Solo-Spiel und Gruppen.“ |

Bitte sieh vorher kurz nach, ob es bereits ein [passendes Issue](https://github.com/Feberdin/ForeverMouseoverBuff/issues)
gibt. Ergänze dort hilfreiche Beobachtungen, wenn derselbe Fall schon beschrieben ist.

## Du entscheidest, was du teilst

Die technischen Angaben sind freiwillig. Die dafür vorgesehenen Felder heißen
`environment` und `diagnostics`: Sie nehmen eine begrenzte Auswahl technischer
Versionsangaben und erlaubter Diagnosecodes auf. Du kannst sie vor dem Absenden
ändern oder vollständig entfernen.

**Beim Öffnen des vorbereiteten Links erhält GitHub bereits die im Link enthaltenen
Angaben.** Sie können außerdem im Verlauf deines Browsers stehen. Ein öffentliches
Issue entsteht erst, wenn du es auf GitHub absendest.

Die Feedback-Funktion übernimmt keine Spielernamen, GUIDs, Whisper, vollständigen
SavedVariables, Zugangsdaten oder ungeprüften Fehlertexte. Auch selbst ergänzte
Texte und Bilder solltest du vor der Veröffentlichung auf private Angaben prüfen.
Für Sicherheitsprobleme gelten die [Sicherheitshinweise](../SECURITY.md).

## Einen Fehler gut beschreiben

Hilfreich sind drei kurze Antworten: **Was passiert? Was erwartest du?
Mit welchen Schritten lässt es sich wiederholen?** Erwähne, ob du selbst im Kampf
warst und welche Funktion du benutzt hast. Du musst das Problem weder technisch
erklären noch selbst beheben können.

Bei Ideen beschreibe zuerst die Spielsituation und den gewünschten Nutzen.
Eine Skizze oder ein Beispiel ist willkommen; ein fertiger Lösungsvorschlag ist
keine Voraussetzung. Die Aufnahme eines Vorschlags ist noch keine Zusage für
einen Veröffentlichungstermin.

## Wenn der Link nicht funktioniert

- **Keine Eingabemaske sichtbar:** Melde dich bei GitHub an und öffne den Link
  anschließend erneut. Alternativ starte über die [Vorlagenauswahl](https://github.com/Feberdin/ForeverMouseoverBuff/issues/new/choose).
- **Ein Feld ist leer:** Technische Angaben sind optional. Du kannst den Bericht
  auch ohne sie absenden oder die Angaben aus der Vorschau manuell übernehmen.
- **Der Browser hat nur einen Teil des Links übernommen:** Kopiere den gesamten
  markierten Link erneut. Verändere keine `%`-Sequenzen im Link; sie kodieren
  Leerzeichen und andere Zeichen.
- **Du möchtest doch nichts senden:** Schließe das Browserformular. Das Addon
  veröffentlicht im Hintergrund nichts.

## Hinweise für Mitwirkende

Die Vorlagen liegen unter `.github/ISSUE_TEMPLATE/`. Die Dateinamen und die beiden
Feld-IDs `environment` / `diagnostics` bilden einen Vertrag mit dem Addon. Ändere
sie nur gemeinsam mit der Link-Erzeugung und den zugehörigen Tests.

Die YAML-Prüfung benötigt ausschließlich für die Entwicklung **PyYAML 6.0.3**:

```sh
python3 -m venv .ci-tools
.ci-tools/bin/python -m pip install PyYAML==6.0.3
.ci-tools/bin/python -m unittest discover -s tests -p test_issue_templates.py -v
```

Der Test prüft YAML-Struktur, eindeutige IDs, erforderliche Fragen, freiwillige
technische Felder und Links zu vorhandenen Projektdateien. Die endgültige
Darstellung wird nach dem Push in GitHubs Vorlagenauswahl geprüft, ohne ein
Test-Issue abzusenden.

GitHub dokumentiert [Issue-Formulare](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms),
[Feld-IDs und Datentypen](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-githubs-form-schema)
sowie das [Vorbelegen per URL](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-an-issue).
