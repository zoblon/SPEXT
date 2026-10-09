# SPEXT

**Deutsch** | [English](README.md)

SPEXT ist eine kleine macOS-Menüleisten-App zum Diktieren. Du hältst einen Hotkey, sprichst und lässt los: Deine Sprache wird von OpenAI transkribiert und in die App eingefügt, in der du gerade arbeitest. Ein zweiter Hotkey startet einen Umformulierungsmodus, der aus einem ungeordneten Diktat eine saubere, gut gegliederte Nachricht macht.

## Funktionen

- Zwei globale Hotkeys: reines Diktat und Nachrichtenmodus (Umformulierung)
- Transkription mit OpenAI `gpt-transcribe`, Umformulierung im Nachrichtenmodus mit `gpt-6.1-sol`
- Der Text wird direkt in die aktive App eingefügt, gefolgt von einem Leerzeichen, damit du weiterschreiben kannst
- Wörterbuch für Namen und Fachbegriffe, die oft falsch erkannt werden
- Spracheinstellung: Deutsch, Englisch oder automatische Erkennung
- Oberfläche auf Deutsch und Englisch, passend zur macOS-Systemsprache
- Schwebende Aufnahmeanzeige mit Live-Wellenform und Hinweis, wenn kein Sprachsignal ankommt
- Aufnahmen ohne Sprache werden verworfen statt gesendet. So entstehen keine erfundenen »Transkripte« von Stille
- Zuverlässiger Umgang mit AirPods- und iPhone-Mikrofonen (Continuity), auf Wunsch mit automatischem Vorrang für AirPods
- Optional Stummschalten des Systemtons während der Aufnahme
- Aufnahmen bis 10 Minuten

## Voraussetzungen

- macOS 14 (Sonoma) oder neuer
- Ein Mac mit Apple Silicon
- Ein eigener OpenAI-API-Key. Transkription und Umformulierung rechnet OpenAI nutzungsabhängig ab, siehe [OpenAI-Preise](https://openai.com/api/pricing/).

## Installation

1. Lade das aktuelle ZIP von [GitHub Releases](https://github.com/zoblon/SPEXT/releases/latest) herunter.
2. Entpacke es und verschiebe `SPEXT.app` in den Ordner »Programme«.
3. Die App ist signiert, aber nicht von Apple notarisiert. macOS blockiert deshalb den ersten Start. Klicke die App mit der rechten Maustaste an und wähle »Öffnen« oder gehe zu »Systemeinstellungen > Datenschutz & Sicherheit« und klicke auf »Trotzdem öffnen«.
4. Trage in den Einstellungen deinen OpenAI-API-Key ein.
5. Erteile die Berechtigungen, nach denen SPEXT fragt. Beim Start prüft SPEXT sie und zeigt ein Einrichtungsfenster, falls etwas fehlt:
   - **Mikrofon**: um deine Stimme aufzunehmen.
   - **Eingabeüberwachung**: um die globalen Hotkeys zu erkennen, während eine andere App im Vordergrund ist.
   - **Bedienungshilfen**: um den Text per simuliertem ⌘V in die aktive App einzufügen.

macOS erlaubt Apps nicht, diese Berechtigungen selbst zu aktivieren. SPEXT kann nur die Systemabfragen auslösen und die passenden Bereiche in den Systemeinstellungen öffnen.

## Bedienung

Die Oberfläche gibt es auf Deutsch und Englisch; sie folgt der macOS-Systemsprache. Die Diktatsprache (Deutsch, Englisch oder automatisch) ist eine eigene Einstellung und unabhängig von der Oberflächensprache.

| Hotkey (Standard) | Modus |
|---|---|
| rechte Wahltaste + rechte Befehlstaste | Diktat: Deine Worte werden so eingefügt, wie du sie sprichst |
| rechte Control-Taste + rechte Wahltaste | Nachricht: Dein Diktat wird zu einer sauberen Nachricht umformuliert und dann eingefügt |

- Halte den Hotkey gedrückt, während du sprichst, und lass ihn los, wenn du fertig bist. SPEXT transkribiert dann die Aufnahme und fügt den Text ein.
- Beide Hotkeys lassen sich in den Einstellungen ändern.
- Trage im Wörterbuch Wörter ein, damit Namen, Marken und Fachbegriffe besser erkannt werden.
- Stell die Sprache auf Deutsch oder Englisch, wenn du immer in einer Sprache diktierst. Wenn du wechselst, nimm die automatische Erkennung.
- Der letzte Text steht auch im Menüleisten-Popover, damit du ihn noch einmal kopieren kannst. Wechselt die aktive App vor dem Einfügen, fügt SPEXT nicht ins falsche Fenster ein; der Text bleibt in der Zwischenablage.

## Datenschutz

- Audio und Text werden mit deinem eigenen API-Key an die OpenAI-API gesendet. Es gelten die Datenrichtlinien von OpenAI.
- Dein API-Key liegt im macOS-Schlüsselbund und wird nie protokolliert.
- SPEXT hat keine Telemetrie und keine Analyse und kontaktiert keinen anderen Server als die OpenAI-API.
- Aufnahmen und Transkripte werden nicht gespeichert. Temporäre Audiodateien werden nach der Verarbeitung gelöscht. Lokal gespeichert werden nur Einstellungen wie Hotkeys, Sprache, Mikrofon und Wörterbuch.

Details findest du in [PRIVACY.md](PRIVACY.md).

## Aus dem Quellcode bauen

1. Öffne `SPEXT.xcodeproj` in Xcode.
2. Wähle unter »Signing & Capabilities« dein eigenes Entwicklerteam.
3. Baue und starte das Scheme `SPEXT`.

Berechtigungen wie Eingabeüberwachung und Bedienungshilfen sind an die Signatur der App gebunden. Startest du einen Build mit anderer Signatur, musst du sie unter Umständen erneut erteilen.

Die Guard-Tests laufen ohne den Test-Runner von Xcode:

```sh
sh SPEXTTests/run-guard-tests.sh
```

## Entwicklung

Architektur, Implementierungsdetails und bekannte Einschränkungen sind in [CLAUDE.md](CLAUDE.md) beschrieben (identisch mit [AGENTS.md](AGENTS.md), beide auf Englisch). Modellvergleiche liegen in [docs/](docs/).

## Danksagung

Die Idee zu SPEXT stammt von der Open-Source-App [blitztext](https://github.com/cmagnussen/blitztext-app) von cmagnussen. SPEXT ist eine unabhängige Umsetzung.

## Lizenz und Marken

MIT-Lizenz, siehe [LICENSE](LICENSE).

SPEXT ist ein unabhängiges Projekt und steht in keiner Verbindung zu OpenAI oder Apple. OpenAI ist eine Marke von OpenAI; macOS und AirPods sind Marken von Apple Inc.
