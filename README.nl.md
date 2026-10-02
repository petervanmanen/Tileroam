# Tileroam

[English](README.md) · **Nederlands** · [Français](README.fr.md) · [Español](README.es.md) · [Deutsch](README.de.md)

Tileroam is een app voor iPhone en iPad die laat zien waar je allemaal bent geweest tijdens je fietsritten, hardlooprondes en wandelingen: elke kaarttegel, gemeente en elk postcodegebied dat je hebt bezocht. De app leest `.fit`-bestanden uit een of meer iCloud Drive-mappen (bijvoorbeeld exports van HealthFit, Garmin of Wahoo) en kan je geschiedenis uit Strava importeren. Daarnaast plant Tileroam fietsroutes naar plekken waar je nog niet bent geweest.

![Tileroam op iPhone: tegels, squadratinho's, gemeenten en routeplanning](docs/screenshots/overview.jpg)

## Functies

- **Tegels**: kaarttegels op zoom 14 (~1,5 km, zoals bij VeloViewer, StatsHunters en [rideeverytile.com](https://rideeverytile.com/how-big-is-a-tile)) en *squadratinho's* op zoom 17 (~190 m, zoals bij Squadrats). Beide worden altijd geteld; jij kiest welke de kaart toont. Inclusief je **max. vierkant** en **grootste cluster**.
- **Routes**: al je activiteiten op één kaart, gekleurd per sport.
- **Gemeenten en postcodes** in Nederland, België, Luxemburg en Duitsland, met bezocht/totaal per land.
- **Routeplanning** in Nederland, België, Luxemburg en Duitsland: tik op onbezochte tegels, gemeenten of postcodes en Tileroam plant de kortste fietsrondrit langs al die plekken. Hij start vanaf je locatie, of vanaf een **startpunt** dat je zoekt of op de kaart ingedrukt houdt (recente startpunten worden onthouden). Routes worden **op het apparaat** berekend, dus plannen werkt ook offline zodra een gebied is gedownload. Deel de route als **GPX** of bewaar hem in je iCloud-map. Je kunt ook een bestaande GPX openen om te zien welke nieuwe plekken die oplevert.
- **Strava**: importeer je volledige geschiedenis met gps. Activiteiten worden ook als standaard `.fit`-bestanden bewaard in een map naar keuze.
- **Dubbele activiteiten samengevoegd**: dezelfde training die door meerdere apparaten of apps is vastgelegd (horloge, Zwift, Strava, HealthFit) telt één keer.
- **Widgets**: *Tegels om je heen* (een kaart van de tegels bij jou in de buurt) en *Eddington-getal*, op het beginscherm en toegangsscherm.
- **Statistieken**: bezochte landen en gemeenten, Eddington-getallen voor fietsen, wandelen en hardlopen, en totalen per sport voor dit jaar en in totaal.
- **Binnen- en virtuele ritten** (Zwift, Rouvy, MyWhoosh, trainerritten) tellen mee in de statistieken maar blijven van de kaart, tegels, gemeenten en postcodes.
- **Opslag is optioneel**: zonder gekozen map bewaart Tileroam routes en Strava-bestanden in de eigen opslag (Bestanden-app › Op mijn iPhone › Tileroam) en leest het ook `.fit`-bestanden uit de map Import daar.
- **Instellingen → Opslag** toont de gedownloade kaartgegevens en laat je ze verwijderen. Kaartdownloads groter dan 25 MB wachten op wifi, tenzij je mobiele data toestaat.
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
| Duitsland | 10.949 Gemeinden | 8.173 (PLZ) |

Tegels, routes en statistieken werken overal; gemeenten, postcodes en routeplanning dekken deze vier landen. Postcodes zijn alleen opgenomen waar de grenzen als open data beschikbaar zijn. De grenzen van een land worden automatisch gedownload zodra je er een activiteit hebt.

## Aan de slag

Vereisten: Xcode 27 of nieuwer, iOS/iPadOS 26 of nieuwer, en een betaald Apple Developer-account om te ondertekenen (nodig voor iCloud en door Apple gehoste asset packs).

1. Clone de repository en open `Tileroam.xcodeproj`.
2. Kies bij de targets **Tileroam** en **TileroamWidget** je team onder *Signing & Capabilities*. Verander de bundle identifier (`nl.petervanmanen.Tileroam`) en de App Group (`group.nl.petervanmanen.Tileroam`) naar je eigen waarden.
3. Optioneel, voor Strava: zie hieronder.
4. Start de app op je iPhone of iPad. Kies bij de eerste start een of meer iCloud Drive-mappen met je `.fit`-bestanden. Je kunt later mappen toevoegen of verwijderen via *Instellingen → Importmappen*.

### Strava (optioneel)

Inloggen gaat via de **Strava-app** (één tik op *Authorize*) of, zonder Strava-app, via de webinlog van Strava. Het Client Secret staat op een kleine **tokenservice** ([`backend/strava-auth`](backend/strava-auth), een Cloudflare Worker); de app zelf bevat alleen de Client ID.

1. Maak een API-applicatie op [strava.com/settings/api](https://www.strava.com/settings/api) met als *Authorization Callback Domain* `localhost`.
2. Zet de tokenservice live zoals beschreven in [`backend/strava-auth/README.md`](backend/strava-auth/README.md).
3. Kopieer `StravaConfig.example.plist` naar `Tileroam/StravaConfig.plist` en vul `ClientID` en `TokenServiceURL` in (de Worker-URL eindigend op `/token`). Geen van beide is geheim; het bestand staat in `.gitignore` omdat het je eigen configuratie is.
4. Bouw en start de app en tik op *Connect with Strava*.

Het Client Secret staat alleen in de tokenservice, nooit in de app. Strava zit in Debug- en Release-builds via de compilatievoorwaarde `STRAVA`; haal die weg uit *Active Compilation Conditions* om zonder Strava te bouwen. Voor andere gebruikers moet Strava eerst de sporterlimiet van je applicatie verhogen (standaard één sporter).

Strava staat ongeveer 100 verzoeken per 15 minuten en 1.000 per dag toe. De activiteitenlijst komt snel binnen met vereenvoudigde routes; gedetailleerde gps wordt daarna aangevuld en de synchronisatie gaat automatisch verder.

## Hoe het werkt

- **FIT-bestanden** worden gelezen door een kleine ingebouwde decoder (`FIT/FITDecoder.swift`). Routes, tegels en bezochte gebieden worden bewaard in een cache, zodat bij de volgende start alleen nieuwe of gewijzigde bestanden worden gelezen.
- **Tegels** gebruiken de standaard Web Mercator-tegelformule (`Geo/TileGrid.swift`). Max. vierkant en cluster worden alleen over de bezochte tegels berekend, zodat dat ook snel blijft voor zoom 17-tegels verspreid over Europa.
- **Dubbelen**: activiteiten van hetzelfde soort die in de tijd overlappen worden samengevoegd (`Import/ActivityMerge.swift`); de kopie met de beste gps en de langste afstand blijft over.
- **Gemeenten en postcodes** zijn compacte binaire bestanden (`AssetPacks/Regions/*.fmr`, samen 6,3 MB) met een ruimtelijke index voor snelle opzoekingen. Ze zitten niet in de app: elk land is een door Apple gehost asset pack (`regions-NL`, …) dat de app met Background Assets downloadt zodra je er een activiteit hebt. `Tools/build_asset_packs.sh` maakt de packs voor App Store Connect; in de simulator leest `-RegionsDir <repo>/AssetPacks/Regions` ze rechtstreeks.
- **Routeplanning** draait op het apparaat met [Valhalla](https://github.com/valhalla/valhalla), via [valhalla-mobile](https://github.com/Rallista/valhalla-mobile), en OpenStreetMap-tegels voor Nederland, België, Luxemburg en Duitsland. De tegels komen als door Apple gehoste asset packs per gebied van 1° × 1°, zodat een plan alleen het eigen gebied downloadt (ongeveer 100 MB voor een plan in één gebied, in plaats van 2,3 GB voor alles). Downloads groter dan 25 MB wachten op wifi (`MapDataDownloads`). De volgorde wordt bepaald op hemelsbrede afstanden (`TripSolver`, veel sneller dan een routematrix op het apparaat); daarna kiest de planner binnen elk doel het punt dat de omweg het kleinst houdt, en Valhalla berekent de rondrit. Hoe je de tegels bouwt en landen toevoegt: [docs/ROUTING.md](docs/ROUTING.md).

## Grensdata

De grensbestanden worden gemaakt door `Tools/build_regions.py` uit de open databronnen die in *Instellingen → Bronnen en licenties* staan:

```bash
python3 -m venv venv && venv/bin/pip install pyshp pyproj shapely
venv/bin/python Tools/build_regions.py <download-map> AssetPacks/Regions
```

Het script beschrijft waar elk bronbestand vandaan komt. Het herprojecteert naar WGS84, voegt delen per code samen, vereenvoudigt de grenzen tot ~25 m (gemeenten) of ~20 m (postcodes) en schrijft het compacte formaat.

| Land | Bron en licentie |
|---|---|
| Nederland | CBS / Kadaster via PDOK (CC BY 4.0) |
| België | NGI-IGN, bpost via Opendatasoft (postcodelicentie: zie bron) |
| Luxemburg | ACT (CC0) |
| Duitsland | BKG VG250 (dl-de/by-2-0); postcodes: OpenStreetMap (ODbL) |

Routeplanning: © OpenStreetMap-bijdragers (ODbL), routering door Valhalla op het apparaat.

## Documentatie

- [Gebruikershandleiding](docs/MANUAL.md) (Engels)
- [Ondersteuning en veelgestelde vragen](SUPPORT.md) (Engels)
- [App Store-pakket](docs/appstore/README.md): metadata, schermafbeeldingen, privacyantwoorden, notities voor de review

## Projectstructuur

```
Tileroam/
  FIT/          FIT-decoder en -encoder
  Geo/          tegels, gemeenten/postcodes, Eddington, vereenvoudiging
  Import/       maptoegang, import, cache, samenvoegen, ActivityStore
  Map/          MKMapView-wrapper en overlays (tegels, gebieden, routes)
  Planning/     routeplanning (Valhalla op het apparaat), routeringsdata, startpunten, GPX, dekking
  Strava/       Strava-API-client, webhook-meldingen, export naar .fit
  Views/        SwiftUI-schermen (kaart, instellingen, opslag, introductie, planpaneel)
TileroamAssets/   Background Assets-downloadextensie
TileroamWidget/   widgets: Tegels om je heen, Eddington-getal
TileroamTests/    unittests (Swift Testing)
AssetPacks/       grenzen van gemeenten en postcodes, als asset packs
backend/          Strava-tokenservice en wachtrij voor webhook-meldingen (Cloudflare Worker)
Tools/            scripts voor data, routering, asset packs, schermafbeeldingen en releases
```

## Tests

```bash
xcodebuild test -project Tileroam.xcodeproj -scheme Tileroam -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

## Beperkingen

- Gemeenten, postcodes en routeplanning dekken alleen Nederland, België, Luxemburg en Duitsland. [docs/ROUTING.md](docs/ROUTING.md) beschrijft hoe je landen toevoegt.
- Luxemburg heeft geen open postcodegrenzen.
- Routes zijn rondritten; enkele routes van A naar B worden nog niet ondersteund.

## Privacy

Tileroam heeft geen accounts, analytics of tracking. Je activiteiten, tegels en statistieken blijven op je apparaat en in je eigen iCloud, en routeplanning draait op het apparaat. Strava-tokens worden in de sleutelhanger bewaard. De enige server is de Strava-tokenservice ([`backend/strava-auth`](backend/strava-auth)): die wisselt de inlogcode om zonder tokens te bewaren, en houdt de webhook-meldingen van Strava bij (sporter- en activiteitnummers, hoogstens 30 dagen), zodat de app activiteiten kan verwijderen die je op Strava hebt verwijderd. Zie het [privacybeleid](PRIVACY.md) (Engels).

## Licentie

De broncode valt onder de [MIT-licentie](LICENSE). De grensdata houdt de licenties van de bronnen (CC BY 4.0, CC0, dl-de/by-2-0, ODbL en de licenties van NGI en bpost), en de routeringsdata is © OpenStreetMap-bijdragers (ODbL); zie [DATA-LICENSES.md](DATA-LICENSES.md).
