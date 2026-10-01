# Tileroam

[English](README.md) · [Nederlands](README.nl.md) · [Français](README.fr.md) · [Español](README.es.md) · **Deutsch**

Tileroam ist eine App für iPhone und iPad, die zeigt, wo du auf deinen Radtouren, Läufen und Wanderungen überall warst: jede Kartenkachel, Gemeinde und jedes Postleitzahlgebiet, das du besucht hast. Sie liest `.fit`-Dateien aus einem oder mehreren iCloud Drive-Ordnern (zum Beispiel Exporte aus HealthFit, Garmin oder Wahoo) und kann deinen Verlauf aus Strava importieren. Außerdem plant sie Radrouten zu Orten, an denen du noch nicht warst.

![Tileroam auf dem iPhone: Kacheln, Squadratinhos, Gemeinden und Routenplanung](docs/screenshots/overview.jpg)

## Funktionen

- **Kacheln**: Kartenkacheln auf Zoom 14 (~1,5 km, wie bei VeloViewer, StatsHunters und [rideeverytile.com](https://rideeverytile.com/how-big-is-a-tile)) und *Squadratinhos* auf Zoom 17 (~190 m, wie bei Squadrats). Beide werden immer gezählt; du wählst, welche die Karte zeigt. Mit deinem **Max-Quadrat** und deinem **größten Cluster**.
- **Routen**: alle deine Aktivitäten auf einer Karte, nach Sportart eingefärbt.
- **Gemeinden und Postleitzahlen** in 22 europäischen Ländern, mit besucht/gesamt pro Land.
- **Routenplanung**: Tippe auf unbesuchte Kacheln, Gemeinden oder Postleitzahlen, und Tileroam plant die kürzeste Radrundfahrt ab deinem Standort durch alle diese Orte. Teile sie als **GPX** oder speichere sie in deinem iCloud-Ordner. Du kannst auch ein vorhandenes GPX öffnen, um zu sehen, welche neuen Orte es bringen würde.
- **Strava**: Importiere deinen gesamten Verlauf mit GPS. Aktivitäten werden außerdem als Standard-`.fit`-Dateien in einem Ordner deiner Wahl gespeichert.
- **Doppelte zusammengeführt**: Dasselbe Training, von mehreren Geräten oder Apps aufgezeichnet (Uhr, Zwift, Strava, HealthFit), zählt nur einmal.
- **Eddington-Zahl** für Radfahren und Laufen, auch als **Widget** auf dem Home-Bildschirm und Sperrbildschirm.
- **Statistik**: besuchte Länder und Gemeinden, Eddington-Zahlen für Radfahren, Gehen und Laufen sowie Summen pro Sportart für dieses Jahr und insgesamt.
- **Indoor- und virtuelle Fahrten** (Zwift, Rouvy, MyWhoosh, Rollentrainer) zählen in der Statistik, bleiben aber von Karte, Kacheln, Gemeinden und Postleitzahlen fern.
- **Speicher ist optional**: Ohne gewählten Ordner speichert Tileroam Routen und Strava-Dateien im eigenen Speicher (Dateien-App › Auf meinem iPhone › Tileroam) und liest auch `.fit`-Dateien aus dem Ordner Import dort.
- **iPad**-Layout mit Seitenleiste, allen Ausrichtungen und Multitasking.
- Verfügbar auf **Englisch, Niederländisch, Französisch, Spanisch und Deutsch**.
- Die Karte öffnet sich auf deinem größten Cluster, dort, wo du am meisten fährst.

## Bildschirmfotos

| Kacheln (Zoom 14) | Squadratinhos (Zoom 17) | Routen | Gemeinden |
|---|---|---|---|
| ![Kacheln](docs/screenshots/tiles.jpg) | ![Squadratinhos](docs/screenshots/squadratinhos.jpg) | ![Routen](docs/screenshots/routes.jpg) | ![Gemeinden](docs/screenshots/municipalities.jpg) |

| Postleitzahlen | Routenplanung | Einstellungen | Einführung |
|---|---|---|---|
| ![Postleitzahlen](docs/screenshots/postcodes.jpg) | ![Routenplanung](docs/screenshots/planning.jpg) | ![Einstellungen](docs/screenshots/settings.jpg) | ![Einführung](docs/screenshots/intro.jpg) |

**iPad**

| Kacheln | Routenplanung |
|---|---|
| ![Kacheln auf dem iPad](docs/screenshots/ipad-tiles.jpg) | ![Routenplanung auf dem iPad](docs/screenshots/ipad-planning.jpg) |

*Die Bildschirmfotos zeigen generierte Demo-Fahrten rund um Utrecht, keine echten Aktivitäten.*

## Länder

| Land | Gemeinden | Postleitzahlen |
|---|---|---|
| Niederlande | 342 gemeenten | 4.071 (PC4) |
| Belgien | 565 | 1.150 |
| Luxemburg | 100 communes | – |
| Deutschland | 10.949 Gemeinden | 8.173 PLZ |
| Frankreich | 34.888 communes | 6.158 (angenäherte Zonen) |
| Spanien | 8.223 municipios | 10.874 |
| Portugal | 308 concelhos | – |
| Italien | 7.904 comuni | – |
| Schweiz | 2.128 Gemeinden | 3.181 PLZ |
| Österreich | 2.092 Gemeinden | – |
| Liechtenstein, Monaco, Andorra, San Marino, Vatikanstadt | 11 / 1 / 7 / 9 / 1 | – |
| Vereinigtes Königreich | 361 Local Authorities | 2.836 Postcode Districts |
| Irland | 31 Local Authorities | – |
| Dänemark | 98 kommuner | 592 |
| Norwegen | 357 kommuner | – |
| Schweden | 290 kommuner | – |
| Finnland | 308 kunnat | 3.026 |
| Island | 61 sveitarfélög | – |

Postleitzahlen sind nur dort enthalten, wo ihre Grenzen als offene Daten veröffentlicht sind. Länder werden anhand deiner Aktivitäten automatisch aktiviert; du kannst sie in den Einstellungen ändern.

## Erste Schritte

Voraussetzungen: Xcode 27 oder neuer, iOS/iPadOS 26 oder neuer und ein kostenpflichtiges Apple-Developer-Konto zum Signieren (nötig für iCloud und von Apple gehostete Asset Packs).

1. Klone das Repository und öffne `Tileroam.xcodeproj`.
2. Wähle für die Targets **Tileroam** und **TileroamWidget** dein Team unter *Signing & Capabilities*. Ändere den Bundle Identifier (`nl.petervanmanen.Tileroam`) und die App Group (`group.nl.petervanmanen.Tileroam`) auf deine eigenen.
3. Optional, für Strava: siehe unten.
4. Starte die App auf deinem iPhone oder iPad. Wähle beim ersten Start einen oder mehrere iCloud Drive-Ordner mit deinen `.fit`-Dateien. Ordner kannst du später unter *Einstellungen → Importordner* hinzufügen oder entfernen.

### Strava (optional)

Die Anmeldung läuft über die **Strava-App** (ein Tippen auf *Authorize*) oder, ohne Strava-App, über die Web-Anmeldung von Strava. Das Client Secret liegt auf einem kleinen **Token-Dienst** ([`backend/strava-auth`](backend/strava-auth), ein Cloudflare Worker); die App enthält nur die Client ID.

1. Lege unter [strava.com/settings/api](https://www.strava.com/settings/api) eine API-Anwendung mit `localhost` als *Authorization Callback Domain* an.
2. Richte den Token-Dienst ein, wie in [`backend/strava-auth/README.md`](backend/strava-auth/README.md) beschrieben.
3. Kopiere `StravaConfig.example.plist` nach `Tileroam/StravaConfig.plist` und trage `ClientID` und `TokenServiceURL` ein (die Worker-URL mit `/token` am Ende). Keiner der Werte ist geheim; die Datei steht in `.gitignore`, weil sie deine eigene Konfiguration ist.
4. Baue und starte die App und tippe auf *Connect with Strava*.

Das Client Secret liegt nur im Token-Dienst, nie in der App. Strava ist über die Kompilierbedingung `STRAVA` in Debug- und Release-Builds enthalten; entferne sie aus den *Active Compilation Conditions*, um ohne Strava zu bauen. Für andere Nutzer muss Strava zuerst das Athletenlimit deiner Anwendung erhöhen (standardmäßig ein Athlet).

Strava erlaubt etwa 100 Anfragen pro 15 Minuten und 1.000 pro Tag. Die Aktivitätenliste kommt schnell mit vereinfachten Strecken; detailliertes GPS wird danach ergänzt, und die Synchronisierung läuft automatisch weiter.

## So funktioniert es

- **FIT-Dateien** werden von einem kleinen eingebauten Decoder gelesen (`FIT/FITDecoder.swift`). Strecken, Kacheln und besuchte Gebiete werden zwischengespeichert, sodass beim nächsten Start nur neue oder geänderte Dateien gelesen werden.
- **Kacheln** verwenden die Standardformel für Web-Mercator-Kacheln (`Geo/TileGrid.swift`). Max-Quadrat und Cluster werden nur über die besuchten Kacheln berechnet und bleiben so auch für Zoom-17-Kacheln quer durch Europa schnell.
- **Doppelte**: Aktivitäten derselben Art, die sich zeitlich überschneiden, werden zusammengeführt (`Import/ActivityMerge.swift`); die Kopie mit dem besten GPS und der längsten Distanz bleibt erhalten.
- **Gemeinden und Postleitzahlen** sind kompakte Binärdateien (`AssetPacks/Regions/*.fmr`, insgesamt 33 MB) mit einem räumlichen Index für schnelle Abfragen. Sie sind nicht in der App: Jedes Land ist ein von Apple gehostetes Asset Pack (`regions-NL`, …), das die App mit Background Assets lädt, sobald du dort eine Aktivität hast. `Tools/build_asset_packs.sh` erstellt die Packs für App Store Connect; im Simulator liest `-RegionsDir <repo>/AssetPacks/Regions` sie direkt.
- Die **Routenplanung** nutzt den öffentlichen [OSRM](https://project-osrm.org)-Fahrradrouter von [openstreetmap.de](https://routing.openstreetmap.de). Er bestimmt die beste Reihenfolge; danach wählt Tileroam in jedem Ziel den Punkt, der den Umweg am kleinsten hält.

## Grenzdaten

Die Grenzdateien werden von `Tools/build_regions.py` aus den offenen Datenquellen erzeugt, die unter *Einstellungen → Quellen und Lizenzen* aufgeführt sind:

```bash
python3 -m venv venv && venv/bin/pip install pyshp pyproj shapely
venv/bin/python Tools/build_regions.py <download-ordner> AssetPacks/Regions
```

Das Skript dokumentiert, woher jede Quelldatei stammt. Es projiziert nach WGS84 um, führt Teile pro Code zusammen, vereinfacht die Grenzen auf ~25 m (Gemeinden) bzw. ~20 m (Postleitzahlen) und schreibt das kompakte Format.

| Land | Quelle und Lizenz |
|---|---|
| Niederlande | CBS / Kadaster über PDOK (CC BY 4.0) |
| Belgien | NGI-IGN, bpost über Opendatasoft (Postleitzahl-Lizenz: siehe Quelle) |
| Deutschland | BKG (dl-de/by-2-0); Postleitzahlen © OpenStreetMap-Mitwirkende (ODbL) |
| Frankreich | IGN, INSEE; Postleitzahlzonen Etalab / BAN (Licence Ouverte 2.0) |
| Spanien | IGN, CNIG, Correos (CC BY 4.0) |
| Portugal | Direção-Geral do Território (gemeinfrei) |
| Italien | ISTAT (CC BY 3.0) |
| Schweiz | swisstopo (opendata.swiss) |
| Österreich | Statistik Austria (CC BY 4.0) |
| Luxemburg | ACT (CC0) |
| Vereinigtes Königreich | ONS, OS (OGL v3.0); Postcode Districts (CC BY 4.0) |
| Irland | Tailte Éireann (CC BY 4.0) |
| Dänemark | SDFI / Klimadatastyrelsen DAGI |
| Norwegen | Kartverket (CC BY 4.0) |
| Schweden | © OpenStreetMap-Mitwirkende (ODbL) |
| Finnland | Statistics Finland (CC BY 4.0) |
| Island | Náttúrufræðistofnun Íslands (CC BY 4.0) |
| Kleinstaaten | geoBoundaries / © OpenStreetMap-Mitwirkende (ODbL) |

Routenplanung: © OpenStreetMap-Mitwirkende (ODbL), Routing durch OSRM / FOSSGIS.

## Datenschutz

Tileroam hat keinen Server und keine Analysewerkzeuge. Deine Aktivitäten, Kacheln und Statistiken bleiben auf deinem Gerät und in den iCloud-Ordnern, die du auswählst. Strava-Tokens werden im Schlüsselbund gespeichert. Der Strava-Anmeldecode und das Erneuern der Tokens laufen über den Token-Dienst (Cloudflare Worker), der nichts speichert oder protokolliert. Wenn du eine Route planst, werden Startpunkt und Stopps an den OSRM-Routingdienst von openstreetmap.de gesendet.

## Projektstruktur

```
Tileroam/
  FIT/          FIT-Decoder und -Encoder
  Geo/          Kacheln, Gemeinden/Postleitzahlen, Eddington, Vereinfachung
  Import/       Ordnerzugriff, Import, Cache, Zusammenführen, ActivityStore
  Map/          MKMapView-Wrapper und Overlays (Kacheln, Gebiete, Routen)
  Planning/     Routenplanung (OSRM), GPX, Abdeckung
  Strava/       Strava-API-Client, Export als .fit
  Views/        SwiftUI-Bildschirme (Karte, Einstellungen, Einführung, Planungsleiste)
  (AssetPacks/Regions/ Grenzen von Gemeinden und Postleitzahlen, als Asset Packs)
TileroamWidget/   Eddington-Widget
TileroamTests/    Unit-Tests (Swift Testing)
Tools/             Skript und Quellen für die Grenzdaten
```

## Tests

```bash
xcodebuild test -project Tileroam.xcodeproj -scheme Tileroam -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Einschränkungen

- Postleitzahlgrenzen sind in Österreich, Luxemburg, Irland, Portugal, Italien, Norwegen, Schweden und Island keine offenen Daten.
- Französische Postleitzahlzonen sind berechnete Umrisse um Adressen und können sich überschneiden.
- Die britischen Postcode Districts (2018) und die spanischen Postleitzahlen (um 2015) sind ältere Datensätze.
- Die Routenplanung hängt vom öffentlichen OSRM-Server ab, einem kostenlosen Community-Dienst ohne Garantien.

## Lizenz

Der Quellcode steht unter der [MIT-Lizenz](LICENSE). Die mitgelieferten Grenzdaten behalten die Lizenzen ihrer Quellen (CC BY, OGL, Licence Ouverte, ODbL und andere); siehe [DATA-LICENSES.md](DATA-LICENSES.md).
