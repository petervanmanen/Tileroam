# Tileroam

[English](README.md) · **Nederlands** · [Français](README.fr.md) · [Español](README.es.md) · [Deutsch](README.de.md)

Tileroam is een app voor iPhone en iPad die laat zien waar je allemaal bent geweest tijdens je fietsritten, hardlooprondes en wandelingen: elke kaarttegel, gemeente en elk postcodegebied dat je hebt bezocht. De app leest `.fit`-bestanden uit een of meer iCloud Drive-mappen (bijvoorbeeld exports van HealthFit, Garmin of Wahoo) en kan je geschiedenis uit Strava importeren. Daarnaast plant Tileroam fietsroutes naar plekken waar je nog niet bent geweest.

![Tileroam op iPhone: tegels, squadratinho's, gemeenten en routeplanning](docs/screenshots/overview.jpg)

## Functies

- **Tegels**: kaarttegels op zoom 14 (~1,5 km, zoals bij VeloViewer, StatsHunters en [rideeverytile.com](https://rideeverytile.com/how-big-is-a-tile)) en *squadratinho's* op zoom 17 (~190 m, zoals bij Squadrats). Beide worden altijd geteld; jij kiest welke de kaart toont. Inclusief je **max. vierkant** en **grootste cluster**.
- **Routes**: al je activiteiten op één kaart, gekleurd per sport.
- **Gemeenten en postcodes** in 22 Europese landen, met bezocht/totaal per land.
- **Routeplanning**: tik op onbezochte tegels, gemeenten of postcodes en Tileroam plant de kortste fietsrondrit vanaf je locatie langs al die plekken. Deel hem als **GPX** of bewaar hem in je iCloud-map. Je kunt ook een bestaande GPX openen om te zien welke nieuwe plekken die oplevert.
- **Strava**: importeer je volledige geschiedenis met gps. Activiteiten worden ook als standaard `.fit`-bestanden bewaard in een map naar keuze.
- **Dubbele activiteiten samengevoegd**: dezelfde training die door meerdere apparaten of apps is vastgelegd (horloge, Zwift, Strava, HealthFit) telt één keer.
- **Eddington-getal** voor fietsen en hardlopen, ook als **widget** op het beginscherm en toegangsscherm.
- **Statistieken**: bezochte landen en gemeenten, Eddington-getallen voor fietsen, wandelen en hardlopen, en totalen per sport voor dit jaar en in totaal.
- **Binnen- en virtuele ritten** (Zwift, Rouvy, MyWhoosh, trainerritten) tellen mee in de statistieken maar blijven van de kaart, tegels, gemeenten en postcodes.
- **Opslag is optioneel**: zonder gekozen map bewaart Tileroam routes en Strava-bestanden in de eigen opslag (Bestanden-app › Op mijn iPhone › Tileroam) en leest het ook `.fit`-bestanden uit de map Import daar.
- **iPad**-weergave met zijpaneel, alle oriëntaties en multitasking.
- Beschikbaar in het **Engels, Nederlands, Frans, Spaans en Duits**.
- De kaart opent op je grootste cluster, zodat je begint waar je het meest rijdt.

## Schermafbeeldingen

| Tegels (zoom 14) | Squadratinho's (zoom 17) | Routes | Gemeenten |
|---|---|---|---|
| ![Tegels](docs/screenshots/tiles.jpg) | ![Squadratinho's](docs/screenshots/squadratinhos.jpg) | ![Routes](docs/screenshots/routes.jpg) | ![Gemeenten](docs/screenshots/municipalities.jpg) |

| Postcodes | Routeplanning | Instellingen | Introductie |
|---|---|---|---|
| ![Postcodes](docs/screenshots/postcodes.jpg) | ![Routeplanning](docs/screenshots/planning.jpg) | ![Instellingen](docs/screenshots/settings.jpg) | ![Introductie](docs/screenshots/intro.jpg) |

**iPad**

| Tegels | Routeplanning |
|---|---|
| ![iPad tegels](docs/screenshots/ipad-tiles.jpg) | ![iPad routeplanning](docs/screenshots/ipad-planning.jpg) |

*De schermafbeeldingen gebruiken gegenereerde demoritten rond Utrecht, geen echte activiteiten.*

## Landen

| Land | Gemeenten | Postcodes |
|---|---|---|
| Nederland | 342 gemeenten | 4.071 (PC4) |
| België | 565 | 1.150 |
| Luxemburg | 100 communes | – |
| Duitsland | 10.949 Gemeinden | 8.173 PLZ |
| Frankrijk | 34.888 communes | 6.158 (benaderde zones) |
| Spanje | 8.223 municipios | 10.874 |
| Portugal | 308 concelhos | – |
| Italië | 7.904 comuni | – |
| Zwitserland | 2.128 Gemeinden | 3.181 PLZ |
| Oostenrijk | 2.092 Gemeinden | – |
| Liechtenstein, Monaco, Andorra, San Marino, Vaticaanstad | 11 / 1 / 7 / 9 / 1 | – |
| Verenigd Koninkrijk | 361 local authorities | 2.836 postcodedistricten |
| Ierland | 31 local authorities | – |
| Denemarken | 98 kommuner | 592 |
| Noorwegen | 357 kommuner | – |
| Zweden | 290 kommuner | – |
| Finland | 308 kunnat | 3.026 |
| IJsland | 61 sveitarfélög | – |

Postcodes zijn alleen opgenomen waar de grenzen als open data beschikbaar zijn. Landen worden automatisch ingeschakeld op basis van je activiteiten; je kunt dit aanpassen in Instellingen.

## Aan de slag

Vereisten: Xcode 27 of nieuwer, iOS/iPadOS 18 of nieuwer, een Apple ID om te ondertekenen (een gratis account werkt; apps verlopen dan na 7 dagen).

1. Clone de repository en open `Tileroam.xcodeproj`.
2. Kies bij de targets **Tileroam** en **TileroamWidget** je team onder *Signing & Capabilities*. Verander de bundle identifier (`nl.petervanmanen.Tileroam`) en de App Group (`group.nl.petervanmanen.Tileroam`) naar je eigen waarden.
3. Optioneel, voor Strava: zie hieronder.
4. Start de app op je iPhone of iPad. Kies bij de eerste start een of meer iCloud Drive-mappen met je `.fit`-bestanden. Je kunt later mappen toevoegen of verwijderen via *Instellingen → Importmappen*.

### Strava (optioneel)

Strava zit alleen in **ontwikkelbuilds**: de compilatievoorwaarde `STRAVA` staat aan voor de Debug-configuratie. Release-builds (Archive voor TestFlight en de App Store) bevatten geen Strava-schermen, doen geen Strava-verzoeken en laten `StravaSecrets.plist` weg. Wil je Strava toch in een Release-build, voeg dan `STRAVA` toe aan *Active Compilation Conditions* voor Release.


1. Maak een API-applicatie op [strava.com/settings/api](https://www.strava.com/settings/api) met als *Authorization Callback Domain* `localhost`.
2. Kopieer `StravaSecrets.example.plist` naar `Tileroam/StravaSecrets.plist` en vul `ClientID` en `ClientSecret` in. Dit bestand staat in `.gitignore`.
3. Bouw en start de app en kies *Koppel met Strava* in Instellingen.

De app praat rechtstreeks met de Strava-API, met het Client Secret in de app. Voor persoonlijk gebruik met je eigen API-applicatie is dat prima. Voor publieke distributie verplaats je de tokenuitwisseling naar een kleine server, zodat het secret niet in de app zit, en vraag je Strava om de limiet van één sporter te verhogen.

Strava staat ongeveer 100 verzoeken per 15 minuten en 1.000 per dag toe. De activiteitenlijst komt snel binnen met vereenvoudigde routes; gedetailleerde gps wordt daarna aangevuld en de synchronisatie gaat automatisch verder.

## Hoe het werkt

- **FIT-bestanden** worden gelezen door een kleine ingebouwde decoder (`FIT/FITDecoder.swift`). Routes, tegels en bezochte gebieden worden bewaard in een cache, zodat bij de volgende start alleen nieuwe of gewijzigde bestanden worden gelezen.
- **Tegels** gebruiken de standaard Web Mercator-tegelformule (`Geo/TileGrid.swift`). Max. vierkant en cluster worden alleen over de bezochte tegels berekend, zodat dat ook snel blijft voor zoom 17-tegels verspreid over Europa.
- **Dubbelen**: activiteiten van hetzelfde soort die in de tijd overlappen worden samengevoegd (`Import/ActivityMerge.swift`); de kopie met de beste gps en de langste afstand blijft over.
- **Gemeenten en postcodes** zitten in de app als compacte binaire bestanden (`Resources/Regions/*.fmr`, samen 33 MB) met een ruimtelijke index voor snelle opzoekingen.
- **Routeplanning** gebruikt de publieke [OSRM](https://project-osrm.org)-fietsrouteplanner van [openstreetmap.de](https://routing.openstreetmap.de). Die bepaalt de beste volgorde; daarna kiest Tileroam binnen elk doel het punt dat de omweg het kleinst houdt.

## Grensdata

De grensbestanden worden gemaakt door `Tools/build_regions.py` uit de open databronnen die in *Instellingen → Bronnen en licenties* staan:

```bash
python3 -m venv venv && venv/bin/pip install pyshp pyproj shapely
venv/bin/python Tools/build_regions.py <download-map> Tileroam/Resources/Regions
```

Het script beschrijft waar elk bronbestand vandaan komt. Het herprojecteert naar WGS84, voegt delen per code samen, vereenvoudigt de grenzen tot ~25 m (gemeenten) of ~20 m (postcodes) en schrijft het compacte formaat.

| Land | Bron en licentie |
|---|---|
| Nederland | CBS / Kadaster via PDOK (CC BY 4.0) |
| België | NGI-IGN, bpost via Opendatasoft (postcodelicentie: zie bron) |
| Duitsland | BKG (dl-de/by-2-0); postcodes © OpenStreetMap-bijdragers (ODbL) |
| Frankrijk | IGN, INSEE; postcodezones Etalab / BAN (Licence Ouverte 2.0) |
| Spanje | IGN, CNIG, Correos (CC BY 4.0) |
| Portugal | Direção-Geral do Território (publiek domein) |
| Italië | ISTAT (CC BY 3.0) |
| Zwitserland | swisstopo (opendata.swiss) |
| Oostenrijk | Statistik Austria (CC BY 4.0) |
| Luxemburg | ACT (CC0) |
| Verenigd Koninkrijk | ONS, OS (OGL v3.0); postcodedistricten (CC BY 4.0) |
| Ierland | Tailte Éireann (CC BY 4.0) |
| Denemarken | SDFI / Klimadatastyrelsen DAGI |
| Noorwegen | Kartverket (CC BY 4.0) |
| Zweden | © OpenStreetMap-bijdragers (ODbL) |
| Finland | Statistics Finland (CC BY 4.0) |
| IJsland | Náttúrufræðistofnun Íslands (CC BY 4.0) |
| Microstaten | geoBoundaries / © OpenStreetMap-bijdragers (ODbL) |

Routeplanning: © OpenStreetMap-bijdragers (ODbL), routering door OSRM / FOSSGIS.

## Privacy

Tileroam heeft geen server en geen analytics. Je activiteiten, tegels en statistieken blijven op je apparaat en in de iCloud-mappen die je zelf kiest. Strava-tokens worden in de sleutelhanger bewaard. Als je een route plant, worden het startpunt en de stops naar de OSRM-routeplanner van openstreetmap.de gestuurd.

## Projectstructuur

```
Tileroam/
  FIT/          FIT-decoder en -encoder
  Geo/          tegels, gemeenten/postcodes, Eddington, vereenvoudiging
  Import/       maptoegang, import, cache, samenvoegen, ActivityStore
  Map/          MKMapView-wrapper en overlays (tegels, gebieden, routes)
  Planning/     routeplanning (OSRM), GPX, dekking
  Strava/       Strava-API-client, export naar .fit
  Views/        SwiftUI-schermen (kaart, instellingen, introductie, planpaneel)
  Resources/Regions/   meegeleverde grenzen van gemeenten en postcodes
TileroamWidget/   Eddington-widget
TileroamTests/    unittests (Swift Testing)
Tools/             script en bronnen voor de grensdata
```

## Tests

```bash
xcodebuild test -project Tileroam.xcodeproj -scheme Tileroam -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Beperkingen

- Postcodegrenzen zijn geen open data in Oostenrijk, Luxemburg, Ierland, Portugal, Italië, Noorwegen, Zweden en IJsland.
- Franse postcodezones zijn berekende omtrekken rond adressen en kunnen overlappen.
- De Britse postcodedistricten (2018) en Spaanse postcodes (rond 2015) zijn oudere datasets.
- Routeplanning hangt af van de publieke OSRM-server, een gratis communitydienst zonder garanties.

## Licentie

De broncode valt onder de [MIT-licentie](LICENSE). De meegeleverde grensdata houdt de licenties van de bronnen (CC BY, OGL, Licence Ouverte, ODbL en andere); zie [DATA-LICENSES.md](DATA-LICENSES.md).
