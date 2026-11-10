# PvP-Schutz und Zähler

Diese Notiz beschreibt das Verhalten der Version 0.10.2. Sie gilt für die
Forever-MouseoverBuff-Addons in `src/ForeverMouseoverBuff/` und kann lokal mit
Lua 5.1 geprüft werden.

## PvP-geflaggte Ziele

`API.ReadContext` liest für das aktuelle Mouseover-Ziel sowohl `UnitIsPVP` als
auch `UnitIsPVPFreeForAll`. Core sperrt die Auswahl, sobald eine der beiden
Markierungen aktiv ist. Fehlende, geheime oder fehlerhafte Werte werden als
unbekannt behandelt und ebenfalls gesperrt.

Vor dem Vorbereiten der geschützten Zauberaktion liest die Klickroutine den
aktuellen Zustand erneut. So wird eine Flag-Änderung während der längeren
Zauberbuch- und Aura-Abfrage abgefangen. Im eigenen Kampf gibt es keinen
Zauberzweig: WoWs geschützte Makrobedingungen können die PvP-Markierung des
Mouseover-Ziels nicht prüfen. Die Taste meldet die Sperre; nach Kampfende kann
sie wieder außerhalb des Kampfes verwendet werden.

Die finale Lua-Abfrage und WoWs tatsächliche Zauberausführung sind keine
atomare Operation. Ändert sich der Mouseover-Zustand genau nach der letzten
Abfrage, kann Lua diese Änderung nicht synchron mit dem geschützten Zauber
verriegeln. Die Implementierung prüft deshalb unmittelbar vor dem Scharfschalten
und behauptet keine absolute Garantie gegen einen Zustandswechsel nach dieser
Prüfung.

## Versandzähler

Der Gruß zeigt `[insgesamt: N Buffs verteilt]`. `N` ist die persistente
Charakter-Gesamtsumme bestätigter Segenszauber, die FMB über
`UNIT_SPELLCAST_SUCCEEDED` erfasst hat. Ein Tastendruck allein zählt nicht.
Heilungen werden nicht in diesen Buffzähler aufgenommen. Bestehende Nachrichten
mit dem alten Zusatz `[lokal: N Buffs]` bleiben beim Empfang gültig.

## Prüfen und debuggen

Im Projektverzeichnis:

```sh
lua tests/test_api.lua
lua tests/test_core.lua
lua tests/test_app.lua
lua tests/test_greetings.lua
lua tests/test_diagnostics.lua
```

Gezielte PvP-Fälle lassen sich mit den Testnamen `pvp`, `final_pvp_guard` und
`pvp_state_is_rechecked` auswählen, zum Beispiel:

```sh
lua tests/test_app.lua pvp_state_is_rechecked_after_safe_preview_before_click_arming
```

Im Spiel zeigen `/fmb status` und `/fmb diag` die verständliche Sperrmeldung und
die datensparsamen Diagnosecodes. Die Tests emulieren Lua-Entscheidungen und
geschützte UI-Attribute; sie emulieren nicht die WoW-Engine oder einen echten
Spielserver.
