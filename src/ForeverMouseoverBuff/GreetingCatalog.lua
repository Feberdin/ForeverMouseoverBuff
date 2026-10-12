-- Purpose: select class-appropriate greeting templates without game APIs.
-- Input: public sender class/race tokens; output: twelve templates and a short form.
-- Invariants: no identities, persistence, randomness or shared mutable results.
-- Debug: lua tests/test_greeting_catalog.lua from the project directory.
local _, ns = ...
local Catalog = {COUNT = 12}
ns.GreetingCatalog = Catalog

-- The sender's class determines the voice. These are original friendly wishes,
-- not official quotes or claims about specialization, talents or actual power.
-- The two cultural slots are separate so Paladin's twelve base texts stay exact.
local classes = {
    PALADIN = {
        short = "Licht und Segen, %s!", gift = "Licht im Gepäck", guide = "einem hellen Segen",
        templates = {
            "Das Licht sei mit Euch, %s!",
            "Möge Euch ein heller Funke begleiten, %s!",
            "Gute Wege und einen sicheren Heimweg, %s!",
            "Ein wenig Licht für Euren nächsten Schritt, %s!",
            "Möge dieser Segen Euch Zuversicht schenken, %s!",
            "Für Euch, %s: Licht im Gepäck und Mut im Herzen!",
            "Bleibt behütet, %s, auch auf dunklen Wegen!",
            "Eine helle Stunde und gute Gesellschaft wünsche ich Euch, %s!",
            "Für die Reise: ein Segen und ein freundlicher Gruß, %s!",
            "Möge Euer Weg nach Hause stets beleuchtet sein, %s!",
            "Nehmt diesen Funken Zuversicht mit, %s!",
            "Auf gute Wege und ein Wiedersehen am Herdfeuer, %s!",
        },
    },
    PRIEST = {
        short = "Mut für %s!", gift = "Zuversicht im Herzen", guide = "festem Willen",
        templates = {
            "Einen festen Willen und Zuversicht wünsche ich Euch, %s!",
            "Möge Euer Mut auch in stillen Stunden wachsen, %s!",
            "Ein wenig Schutz für Euren nächsten Weg, %s!",
            "Ruhe im Herzen und Stärke im Geist, %s!",
            "Möge Euch die Zuversicht ein guter Begleiter sein, %s!",
            "Für Euch, %s: ein klarer Gedanke und neuer Mut!",
            "Bleibt standhaft und bewahrt Euren eigenen Weg, %s!",
            "Möge Euch ein ruhiger Atem durch den Tag tragen, %s!",
            "Für die Reise wünsche ich Euch Kraft und Geborgenheit, %s!",
            "Haltet an Eurer Hoffnung fest, %s!",
            "Nehmt ein wenig seelische Stärke mit, %s!",
            "Auf einen friedlichen Heimweg und ein warmes Herdfeuer, %s!",
        },
    },
    DRUID = {
        short = "Natur für %s!", gift = "die Kraft der Natur", guide = "der Ruhe des Waldes",
        templates = {
            "Die Kraft der Natur begleite Euch, %s!",
            "Möge Euer Weg so sicher sein wie tiefe Wurzeln, %s!",
            "Einen frischen Wind und neuen Mut wünsche ich Euch, %s!",
            "Nehmt die Ruhe des Waldes mit auf Eure Reise, %s!",
            "Möge Euch die Erde unter den Füßen Halt geben, %s!",
            "Für Euch, %s: frisches Grün und einen wachen Sinn!",
            "Bleibt behütet unter dem weiten Blätterdach, %s!",
            "Möge Euer Mut mit jedem neuen Morgen wachsen, %s!",
            "Für die Reise: die Geduld der Bäume und einen freundlichen Gruß, %s!",
            "Findet stets einen guten Pfad durch die Wildnis, %s!",
            "Nehmt einen Hauch Waldluft und Zuversicht mit, %s!",
            "Auf gesunde Wurzeln und ein Wiedersehen am warmen Feuer, %s!",
        },
    },
    SHAMAN = {
        short = "Kraft für %s!", gift = "die Stärke der Elemente", guide = "einem Gruß der Elemente",
        templates = {
            "Die Elemente mögen Euch Kraft schenken, %s!",
            "Einen festen Stand und günstigen Wind wünsche ich Euch, %s!",
            "Möge die Erde Eure Schritte tragen, %s!",
            "Nehmt die Wärme eines guten Feuers mit, %s!",
            "Möge ein klarer Quell Euren Mut erneuern, %s!",
            "Für Euch, %s: die Ruhe der Erde und die Freiheit des Windes!",
            "Bleibt standhaft, auch wenn der Wind sich dreht, %s!",
            "Möge Euch ein sanfter Wind nach Hause führen, %s!",
            "Für die Reise: elementare Kraft und einen freundlichen Gruß, %s!",
            "Einen ruhigen Strom und sicheren Boden wünsche ich Euch, %s!",
            "Nehmt ein wenig Feuerwärme und Zuversicht mit, %s!",
            "Auf gute Wege zwischen Erde, Wasser, Wind und Feuer, %s!",
        },
    },
    MAGE = {
        short = "Magie für %s!", gift = "ein Funke arkaner Kraft", guide = "ruhiger arkaner Kraft",
        templates = {
            "Ein Funke arkaner Kraft begleite Euch, %s!",
            "Einen klaren Kopf und gute Einfälle wünsche ich Euch, %s!",
            "Möge Euch die Magie auf Eurem Weg zur Seite stehen, %s!",
            "Nehmt ein wenig arkane Ruhe mit auf die Reise, %s!",
            "Möge Eure Neugier stets einen guten Weg finden, %s!",
            "Für Euch, %s: ein klarer Gedanke und ein Hauch Magie!",
            "Bleibt aufmerksam für die kleinen Wunder am Weg, %s!",
            "Möge jeder neue Morgen einen guten Einfall bringen, %s!",
            "Für die Reise: arkane Kraft und einen freundlichen Gruß, %s!",
            "Einen sicheren Heimweg und einen ruhigen Geist wünsche ich Euch, %s!",
            "Nehmt diesen kleinen Funken Zauberkraft mit, %s!",
            "Auf gute Wege und anregende Gespräche am Herdfeuer, %s!",
        },
    },
    WARLOCK = {
        short = "Kraft für %s!", gift = "gezähmte Schattenkraft", guide = "Kraft aus dem Dunkel",
        templates = {
            "Ein wenig Kraft aus dem Dunkel für Euren Weg, %s!",
            "Mögen gezähmte Schatten Euch Zuversicht schenken, %s!",
            "Einen festen Willen und einen sicheren Heimweg wünsche ich Euch, %s!",
            "Nehmt diesen freundlichen Funken Schattenkraft mit, %s!",
            "Möge Euer Mut auch im Unbekannten bestehen, %s!",
            "Für Euch, %s: dunkle Kraft mit freundlicher Absicht!",
            "Bleibt gelassen, auch wenn der Weg im Schatten liegt, %s!",
            "Möge ein ruhiger Geist Euch durch die Dämmerung führen, %s!",
            "Für die Reise: gezähmte Magie und einen freundlichen Gruß, %s!",
            "Einen klaren Blick und festen Boden wünsche ich Euch, %s!",
            "Nehmt ein wenig geheimnisvolle Stärke mit, %s!",
            "Auf gute Wege und eine warme Taverne nach Einbruch der Nacht, %s!",
        },
    },
    WARRIOR = {
        short = "Mut für %s!", gift = "Mut im Herzen", guide = "Mut und Standhaftigkeit",
        templates = {
            "Mut und Standhaftigkeit seien mit Euch, %s!",
            "Einen festen Schritt und ein tapferes Herz wünsche ich Euch, %s!",
            "Möge Eure Entschlossenheit Euch sicher tragen, %s!",
            "Nehmt ein wenig Zuversicht für den nächsten Weg mit, %s!",
            "Möge Euch die Kraft nicht vor dem Heimweg ausgehen, %s!",
            "Für Euch, %s: Mut im Herzen und einen sicheren Stand!",
            "Bleibt aufrecht und bewahrt Euren guten Willen, %s!",
            "Möge ein tiefer Atem Euch neue Stärke geben, %s!",
            "Für die Reise: Entschlossenheit und einen freundlichen Gruß, %s!",
            "Einen ruhigen Blick und einen festen Griff wünsche ich Euch, %s!",
            "Nehmt diesen kleinen Ansporn mit auf Euren Weg, %s!",
            "Auf tapfere Schritte und ein Wiedersehen am Herdfeuer, %s!",
        },
    },
    HUNTER = {
        short = "Gute Jagd, %s!", gift = "den Spürsinn der Wildnis", guide = "dem Gespür der Wildnis",
        templates = {
            "Das Gespür der Wildnis begleite Euch, %s!",
            "Wache Sinne und sichere Pfade wünsche ich Euch, %s!",
            "Möge Euch ein günstiger Wind den Weg weisen, %s!",
            "Nehmt die Geduld der Wildnis mit auf Eure Reise, %s!",
            "Möge Euer Blick auch kleine Wegzeichen finden, %s!",
            "Für Euch, %s: einen wachen Sinn und ein ruhiges Händchen!",
            "Bleibt aufmerksam auf den Pfaden zwischen Wald und Wiese, %s!",
            "Möge jeder neue Morgen eine gute Spur bereithalten, %s!",
            "Für die Reise: Spürsinn und einen freundlichen Gruß, %s!",
            "Einen trockenen Rastplatz und einen sicheren Heimweg wünsche ich Euch, %s!",
            "Nehmt ein wenig Wildnisruhe und Zuversicht mit, %s!",
            "Auf gute Fährten und ein warmes Feuer am Ende des Weges, %s!",
        },
    },
    ROGUE = {
        short = "Glück, %s!", gift = "ein sicheres Händchen", guide = "Geschick und einem leisen Schritt",
        templates = {
            "Geschick und ein wacher Blick seien mit Euch, %s!",
            "Ein sicheres Händchen und gute Gelegenheiten wünsche ich Euch, %s!",
            "Möge Euer nächster Schritt gut überlegt sein, %s!",
            "Nehmt ein wenig Fingerspitzengefühl mit auf die Reise, %s!",
            "Möge Euer Gespür Euch stets den passenden Weg zeigen, %s!",
            "Für Euch, %s: einen leisen Schritt und einen klaren Kopf!",
            "Bleibt flink und bewahrt Euren guten Humor, %s!",
            "Möge Euch ein kluger Einfall im rechten Augenblick finden, %s!",
            "Für die Reise: Geschick und einen freundlichen Gruß, %s!",
            "Einen sicheren Tritt und einen entspannten Heimweg wünsche ich Euch, %s!",
            "Nehmt diesen kleinen Schub Zuversicht mit, %s!",
            "Auf geschickte Schritte und einen gemütlichen Platz am Herdfeuer, %s!",
        },
    },
}

-- These gentle cultural accents describe the sender's fantasy voice, never the
-- recipient's beliefs or gender. Every pair combines with the selected class;
-- e.g. Tauren/DRUID keeps nature and roots, Tauren/SHAMAN keeps elements and earth.
local races = {
    Human = {gift = "Zuversicht für den Heimweg", path = "auf den Straßen der Heimat"},
    Dwarf = {gift = "die Ruhe tiefer Berge", path = "über Stein und Bergpfade"},
    NightElf = {gift = "die Stille des Mondwaldes", path = "unter dem Mond zwischen alten Bäumen"},
    Gnome = {gift = "ein guter Einfall zur rechten Zeit", path = "auf erfinderischen Wegen zu neuen Zielen"},
    Draenei = {gift = "Hoffnung auf ein neues Morgen", path = "auf der Suche nach einer guten Heimstatt"},
    Orc = {gift = "den Mut der Ahnen", path = "auf den Spuren der Ahnen"},
    Scourge = {gift = "Mut für einen neuen Anfang", path = "auf Eurem eigenen Weg in die Zukunft"},
    Tauren = {gift = "die Geduld tiefer Wurzeln", path = "über die weite Erde"},
    Troll = {gift = "das Geleit freundlicher Geister", path = "im Takt der Trommeln"},
    BloodElf = {gift = "die Ruhe alter Gärten", path = "durch die Gärten der Heimat"},
}

-- Unknown sender classes get a genuinely neutral voice. Missing metadata must
-- never silently turn a Druid or an unfamiliar future class into a Paladin.
local neutral = {
    short = "Gute Wege, %s!",
    templates = {
        "Gute Wege, %s!",
        "Einen sicheren Heimweg wünsche ich Euch, %s!",
        "Möge Euch die Zuversicht auf Eurer Reise begleiten, %s!",
        "Ein freundlicher Gruß für Euren nächsten Schritt, %s!",
        "Möge Euer Tag gute Begegnungen bereithalten, %s!",
        "Für Euch, %s: neuen Mut und einen klaren Kopf!",
        "Bleibt wohlauf, wohin Euer Weg Euch auch führt, %s!",
        "Eine ruhige Stunde und gute Gesellschaft wünsche ich Euch, %s!",
        "Für die Reise: einen guten Wunsch und einen freundlichen Gruß, %s!",
        "Möge Euch am Ende des Tages ein warmer Rastplatz erwarten, %s!",
        "Nehmt ein wenig Zuversicht mit, %s!",
        "Auf einen guten Weg und ein Wiedersehen am Feuer, %s!",
    },
}

-- Return a detached table, so callers can choose or inspect text without ever
-- changing the shared catalog. Only exact public tokens select an entry; no
-- coercion, user metatable, game API, random generator or persistent state runs.
-- Short forms contain <=32 UTF-8 bytes including %s. Two 96-byte names, the
-- addon prefix and quotation punctuation still fit inside the 255-byte budget.
function Catalog.Select(senderClass, senderRace)
    local style = type(senderClass) == "string" and classes[senderClass] or nil
    local race = type(senderRace) == "string" and races[senderRace] or nil
    local source, result = style or neutral, {}
    for index = 1, Catalog.COUNT do result[index] = source.templates[index] end
    if style and race then
        result[6] = "Für Euch, %s: " .. style.gift .. " und " .. race.gift .. "!"
        result[12] = "Mit " .. style.guide .. " " .. race.path .. ", %s!"
    end
    return result, source.short
end
