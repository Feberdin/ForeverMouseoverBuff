# Forever Mouseover Buff

![Forever Mouseover Buff mit goldenem Mauszeiger und originalem Feberdin-Ritterlogo](release/assets/brand-banner.png)

**[English](README.md)** · [Änderungen](CHANGELOG.md) · [Mitmachen](CONTRIBUTING.md) · [Feberdin-Design](BRANDING.md)

**Ein passender Segen. Ein persönlicher Gruß. Ein ruhigerer Chat.**

Wähle einen gelernten Paladinsegen für den befreundeten Spieler unter deiner
Maus. Andere Klassen können Forever Mouseover Buff einfach installieren,
um seine automatischen Grüße abzulehnen.

**0.7.4 Beta · WoW Forever 1.60.1 · Interface 16001**

Oberfläche und Grüße sind überwiegend deutsch. Das native Sanctum-Menü ist
automatisiert und im nachgebildeten Layout geprüft; der Ingame-Test steht noch aus. Gespeicherte 0.7.2-Diagnosen
zeigen zwei zusätzlich bestätigte Zaubervorgänge, keinen Anstieg der Fehlerzähler
und kein ERROR unter den letzten 64 Ereignissen. Das ist ein begrenzter
Praxisnachweis; die umfassendere Ingame-Abnahme läuft weiter.

## 🛡️ Was das Addon kann

- **Segen per Mouseover:** Außerhalb deines eigenen Kampfes wählt es anhand der
  unterstützten Klassenvorgaben einen passenden gelernten Segen der Macht,
  Weisheit oder Könige.
- **Vorhandene Buffs berücksichtigen:** Die Auswahl verwendet lesbare
  Zielinformationen und erhält bestehende Segen. Sind wichtige Angaben unklar
  oder geschützt, hält sie mit einer verständlichen Begründung an.
- **Taste im Kampf:** Sobald gelernt, liegt Segen der Könige im eigenen Kampf
  fest auf derselben Mouseover-Taste. Dabei findet keine dynamische Auswahl statt.
- **Rückmeldung erhalten:** Ein gesperrter Versuch wird kurz erklärt und auf
  Wunsch mit einem Ton gemeldet. Ein eigener Hinweiston erinnert an einen
  beobachteten natürlichen Siegelablauf.
- **Persönliche Grüße senden:** Nach einem bestätigten FMB-Buff kann ein
  wechselnder Gruß mit passender Klassen-/Volkssprache und, soweit verfügbar,
  dem Link zum tatsächlich gewirkten Zauber verschickt werden.

**Jeder Zauber benötigt einen echten Tastendruck.** Bloßes Drüberfahren mit der
Maus zaubert nichts. Buffauswahl und Statistik unterstützen derzeit
**ausschließlich Paladine**. Der reine Empfangsmodus funktioniert mit **jeder
Klasse**; die vorbereiteten Grußstile anderer Klassen ergänzen keine Zauber.

## 🚀 Schnell eingerichtet

1. Installiere das Addon im aktiven Forever-Ordner `Interface/AddOns`. Bei einer
   manuellen ZIP-Installation muss dort
   `ForeverMouseoverBuff/ForeverMouseoverBuff.toc` liegen.
2. Starte WoW nach der ersten Installation neu. Bei einem Update reicht
   normalerweise `/reload`.
3. Öffne mit `/fmb` die Einstellungen.
4. Als Paladin vergibst du unter **Tastaturbelegung → Forever Mouseover Buff**
   eine freie Taste. Fahre über einen freundlichen Spieler, drücke die Taste und
   lasse sie wieder los.
5. Du möchtest nur die Grüße abschalten? Gib `/fmb receive off` ein. Dafür
   brauchst du weder einen Paladin noch eine Buff-Taste.

`/fmb auto` aktiviert die automatische Auswahl außerhalb des Kampfes. Mit
`/fmb might`, `/fmb wisdom` oder `/fmb kings` wählst du einen festen Modus.
`/fmb on` und `/fmb off` schalten die Bufffunktion ein oder aus.

## 💬 Drei unabhängige Nachrichtenschalter

| Dein Wunsch | Befehl | Das wird geändert |
| --- | --- | --- |
| Keine eigenen Grüße versenden | `/fmb whisper off` | Deine ausgehenden automatischen Grüße |
| Keine FMB-Grüße empfangen | `/fmb receive off` | Automatische Grüße an dich |
| Eigene Grüße im normalen Chat verbergen | `/fmb outgoing off` | Nur deine lokale Chatanzeige |

Mit `on` statt `off` schaltest du die jeweilige Funktion wieder ein. Alle drei
Einstellungen sind unabhängig. Die eigene Chatkopie ist standardmäßig verborgen.

Normale persönliche Whisper bleiben erhalten. WIM ist optional. Seine eigenen
Gesprächseinstellungen bestimmen weiterhin, ob ein ausgehender Gruß ein Fenster
öffnet oder im Verlauf erscheint. Erkannt werden kompatible, markierte FMB-Grüße. Ältere unmarkierte
Nachrichten und andere Addons werden nicht pauschal gefiltert.

## 🔔 Töne nach deinem Geschmack

- `/fmb sound on` beziehungsweise `/fmb sound off`: Ton bei gesperrten Buffversuchen.
- `/fmb soundtest`: den eingeschalteten Hinweiston prüfen.
- `/fmb seal on` beziehungsweise `/fmb seal off`: separate Siegelerinnerung.

Der Siegelton folgt einem beobachteten natürlichen Ablauf. Er ertönt nicht schon
deshalb, weil beim Einloggen kein Siegel aktiv ist.

## 📊 Lokale Statistik und freiwillige Rankingtests

`/fmb stats` zeigt lokale, unbestätigte Zähler erfolgreicher FMB-Buffs. Version
0.7.1 speichert die zwanzig unterstützten Zauberzähler als Binärdaten in Base64
mit einer SHA-256-Prüfsumme. Gültige ältere Zähler werden automatisch übernommen.
Beschädigte oder unlesbare Datensätze bleiben unverändert erhalten; die Statistik
pausiert, während Buffen weiterhin möglich ist.

**Das ist eine Kodierung mit Fehlerprüfung, keine Verschlüsselung oder
Manipulationssicherheit.** Wer die Dateien kontrolliert, kann auch neue Daten
mit passender Prüfsumme erstellen. Die Zähler bleiben selbst gemeldete
Community-Daten und beweisen keine echten Zaubervorgänge.

Der Rankingexport ist **standardmäßig aus**. `/fmb ranking on` sammelt freiwillig
Exportereignisse; `/fmb ranking help` erklärt den separaten Companion und den
lokalen Testablauf. Die Ereignisdatei bleibt lesbar. Empfänger und Chattexte
werden nicht exportiert. Das Addon baut keine Webverbindung auf, und es gibt
**keinen bereitgestellten öffentlichen Rankingdienst**. Companion und lokaler
Dienst sind zum Buffen nicht erforderlich.

## ✨ Sanctum-Menü im Spiel

`/fmb` öffnet das neue dunkle Menü mit deinem Feberdin-Ritter und Addon-Logo.
Links wechselst du zwischen Buffs und Tastenhilfe, Grüßen, Tönen, Statistik,
Diagnose und Hilfe. Türkise Schalter zeigen den aktuellen Zustand; Gold markiert
den gewählten Bereich und Segensmodus. Änderungen werden direkt übernommen.
Das Fenster passt sich kleineren Bildschirmen an und lässt sich mit Escape
schließen. Statistik und Diagnose zeigen echte lokale Werte, keine Beispieldaten.

## 💬 Fehler, Wünsche und Features melden

Öffne **Feedback & Hilfe auf GitHub** im Menü oder gib `/fmb feedback` ein.
Wähle Fehler, Wunsch oder Feature. Technische Angaben sind standardmäßig aus;
bei Aktivierung siehst du Version, öffentliche Schalter und höchstens fünf
bekannte Diagnosecodes in der Vorschau. Namen, Whisper und Zähler bleiben draußen.

Klicke **Link markieren**, kopiere mit Cmd/Strg+C und öffne den Link im Browser.
GitHub erhält die enthaltenen Angaben bereits beim Öffnen; du ergänzt und
veröffentlichst das Issue erst dort. Das Addon überträgt nichts und benötigt
keinen Token. [Schritt-für-Schritt-Hilfe und Vorlagen](docs/feedback.md).

## 🧭 Lokales Diagnoseprotokoll

`/fmb diag` zeigt den Diagnosestatus und die letzten fünf Ereignisse. Das begrenzte
lokale Protokoll enthält feste Codes, Schweregrad, Modul, soweit verfügbar öffentliche
Zeitstempel, Versuchs-/Erfolgs-/Fehlerzähler und einen kleinen Einstellungs- und
Clientstand. Spielernamen, GUIDs, Whispertexte und rohe API-Fehler werden nicht erfasst.
Das Protokoll arbeitet ohne Chatspam; `/fmb debug on` ergänzt nur die lokale Chatausgabe.

WoW schreibt die SavedVariables bei `/reload` oder beim Ausloggen auf die Festplatte.
Ein separater lokaler Leser kann diesen Stand ohne Rankingdienst und ohne Upload
prüfen. Er liest keinen Live-Spielzustand aus. Ein alter Dateistand ist keine aktuelle
Funktionsprüfung.

Details und lokale Abfragebefehle stehen im [Diagnoseprotokoll](DIAGNOSTICS.md).

## ❓ Häufige Fragen

**Kann ich jemanden buffen, der gerade kämpft?**  
Ja, der Kampfstatus des Ziels allein verhindert es nicht. Die Auswahl braucht
weiterhin verwendbare Zielinformationen. Dein eigener Kampf stellt die Taste
auf den gelernten Segen der Könige um.

**Was hilft bei einer Fehlermeldung?**  
Nutze `/fmb status`, `/fmb help` und vorübergehend `/fmb debug on`. Nenne im Fehlerbericht Addonversion, Clientbuild, Schritte zum
Nachstellen und den festen Diagnosecode. Danach schaltest du mit `/fmb debug off` zurück.
Teile keine vollständigen SavedVariables, privaten Whisper, Tokens oder
Zugangssicherungen. Sichere beschädigte Statistikdaten vor einem
Wiederherstellungsversuch; setze sie nicht nur zum Verbergen des Fehlers zurück.

## 🧰 Entwicklung, Support und Lizenz

Die [englische README](README.md#develop-and-test) enthält die lokal ausführbaren
Test- und Buildbefehle. [CONTRIBUTING](CONTRIBUTING.md) erklärt den Ablauf
Rot → Grün → Refactor; [SECURITY](SECURITY.md) beschreibt Daten und Schutzgrenzen.
Für eigene lokale Rankingtests gibt es die [Companion-Anleitung](companion/README.md)
und die [Service-Anleitung](service/README.md). Diese Komponenten sind nicht im
installierbaren Addon-ZIP enthalten.

Originaler Projektcode: [MIT](LICENSE). Das Ritterlogo kennzeichnet Feberdin als
Absender; die [Designvorlage](BRANDING.md) erklärt den Einsatz in weiteren eigenen
Addons. Eigenständiges Projekt ohne offizielle Verbindung zu Blizzard oder
CurseForge; Spielnamen und Marken verbleiben bei ihren jeweiligen Inhabern.

Quellcode: [Feberdin/ForeverMouseoverBuff](https://github.com/Feberdin/ForeverMouseoverBuff).
Fehlerberichte: [GitHub Issues](https://github.com/Feberdin/ForeverMouseoverBuff/issues).
