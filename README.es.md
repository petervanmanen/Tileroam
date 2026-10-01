# Tileroam

[English](README.md) · [Nederlands](README.nl.md) · [Français](README.fr.md) · **Español** · [Deutsch](README.de.md)

Tileroam es una app para iPhone y iPad que muestra todos los lugares por los que has pasado en tus salidas en bici, carreras y paseos: cada tesela del mapa, municipio y código postal que has visitado. Lee archivos `.fit` de una o varias carpetas de iCloud Drive (por ejemplo, exportaciones de HealthFit, Garmin o Wahoo) y puede importar tu historial de Strava. También planifica rutas en bici hacia lugares donde aún no has estado.

![Tileroam en iPhone: teselas, squadratinhos, municipios y planificación de rutas](docs/screenshots/overview.jpg)

## Funciones

- **Teselas**: teselas de mapa de zoom 14 (~1,5 km, como en VeloViewer, StatsHunters y [rideeverytile.com](https://rideeverytile.com/how-big-is-a-tile)) y *squadratinhos* de zoom 17 (~190 m, como en Squadrats). Siempre se cuentan ambos; tú eliges cuál muestra el mapa. Incluye tu **cuadrado máximo** y tu **mayor clúster**.
- **Rutas**: todas tus actividades en un mapa, coloreadas por deporte.
- **Municipios y códigos postales** en 22 países europeos, con visitados/total por país.
- **Planificación de rutas**: toca teselas, municipios o códigos postales sin visitar y Tileroam planifica la ruta circular en bici más corta desde tu ubicación pasando por todos. Compártela como **GPX** o guárdala en tu carpeta de iCloud. También puedes abrir un GPX existente para ver qué lugares nuevos conseguirías.
- **Strava**: importa todo tu historial con GPS. Las actividades también se guardan como archivos `.fit` estándar en la carpeta que elijas.
- **Duplicados fusionados**: el mismo entrenamiento registrado por varios dispositivos o apps (reloj, Zwift, Strava, HealthFit) cuenta una sola vez.
- **Número de Eddington** para ciclismo y carrera, también como **widget** en la pantalla de inicio y la pantalla bloqueada.
- Diseño para **iPad** con panel lateral, todas las orientaciones y multitarea.
- Disponible en **inglés, neerlandés, francés, español y alemán**.
- El mapa se abre en tu mayor clúster, donde más pedaleas.

## Capturas de pantalla

| Teselas (zoom 14) | Squadratinhos (zoom 17) | Rutas | Municipios |
|---|---|---|---|
| ![Teselas](docs/screenshots/tiles.jpg) | ![Squadratinhos](docs/screenshots/squadratinhos.jpg) | ![Rutas](docs/screenshots/routes.jpg) | ![Municipios](docs/screenshots/municipalities.jpg) |

| Códigos postales | Planificación | Ajustes | Introducción |
|---|---|---|---|
| ![Códigos postales](docs/screenshots/postcodes.jpg) | ![Planificación](docs/screenshots/planning.jpg) | ![Ajustes](docs/screenshots/settings.jpg) | ![Introducción](docs/screenshots/intro.jpg) |

**iPad**

| Teselas | Planificación |
|---|---|
| ![Teselas en iPad](docs/screenshots/ipad-tiles.jpg) | ![Planificación en iPad](docs/screenshots/ipad-planning.jpg) |

*Las capturas usan salidas de demostración generadas alrededor de Utrecht, no actividades reales.*

## Países

| País | Municipios | Códigos postales |
|---|---|---|
| Países Bajos | 342 gemeenten | 4.071 (PC4) |
| Bélgica | 565 | 1.150 |
| Luxemburgo | 100 communes | – |
| Alemania | 10.949 Gemeinden | 8.173 PLZ |
| Francia | 34.888 communes | 6.158 (zonas aproximadas) |
| España | 8.223 municipios | 10.874 |
| Portugal | 308 concelhos | – |
| Italia | 7.904 comuni | – |
| Suiza | 2.128 Gemeinden | 3.181 PLZ |
| Austria | 2.092 Gemeinden | – |
| Liechtenstein, Mónaco, Andorra, San Marino, Ciudad del Vaticano | 11 / 1 / 7 / 9 / 1 | – |
| Reino Unido | 361 local authorities | 2.836 postcode districts |
| Irlanda | 31 local authorities | – |
| Dinamarca | 98 kommuner | 592 |
| Noruega | 357 kommuner | – |
| Suecia | 290 kommuner | – |
| Finlandia | 308 kunnat | 3.026 |
| Islandia | 61 sveitarfélög | – |

Los códigos postales solo se incluyen donde sus límites se publican como datos abiertos. Los países se activan automáticamente según tus actividades; puedes cambiarlos en Ajustes.

## Primeros pasos

Requisitos: Xcode 27 o posterior, iOS/iPadOS 18 o posterior, un Apple ID para firmar (una cuenta gratuita sirve; las apps caducan entonces a los 7 días).

1. Clona el repositorio y abre `Tileroam.xcodeproj`.
2. En los targets **Tileroam** y **TileroamWidget**, elige tu equipo en *Signing & Capabilities*. Cambia el identificador de bundle (`nl.petervanmanen.Tileroam`) y el App Group (`group.nl.petervanmanen.Tileroam`) por los tuyos.
3. Opcional, para Strava: ver abajo.
4. Ejecuta la app en tu iPhone o iPad. En el primer inicio, elige una o varias carpetas de iCloud Drive con tus archivos `.fit`. Puedes añadir o quitar carpetas más tarde en *Ajustes → Carpetas de importación*.

### Strava (opcional)

Strava solo se incluye en las **compilaciones de desarrollo**: la condición de compilación `STRAVA` está activada en la configuración Debug. Las compilaciones Release (Archive para TestFlight y la App Store) no contienen pantallas de Strava, no hacen solicitudes a Strava y omiten `StravaSecrets.plist`. Para incluir Strava en una compilación Release, añade `STRAVA` a *Active Compilation Conditions* de Release.


1. Crea una aplicación de API en [strava.com/settings/api](https://www.strava.com/settings/api) con `localhost` como *Authorization Callback Domain*.
2. Copia `StravaSecrets.example.plist` a `Tileroam/StravaSecrets.plist` y rellena `ClientID` y `ClientSecret`. Este archivo está en `.gitignore`.
3. Compila y ejecuta, y elige *Conectar con Strava* en Ajustes.

La app se comunica directamente con la API de Strava, con el Client Secret dentro de la app. Para uso personal con tu propia aplicación de API está bien. Para distribución pública, traslada el intercambio de tokens a un pequeño servidor para que el secreto no vaya en la app, y pide a Strava que aumente el límite de deportistas de tu aplicación.

Strava permite unas 100 solicitudes cada 15 minutos y 1.000 al día. La lista de actividades llega rápido con rutas simplificadas; el GPS detallado se completa después y la sincronización continúa automáticamente.

## Cómo funciona

- Los **archivos FIT** se leen con un pequeño decodificador integrado (`FIT/FITDecoder.swift`). Rutas, teselas y zonas visitadas se guardan en caché, así que en el siguiente inicio solo se leen los archivos nuevos o modificados.
- Las **teselas** usan la fórmula estándar de teselas Web Mercator (`Geo/TileGrid.swift`). El cuadrado máximo y el clúster se calculan solo sobre las teselas visitadas, por lo que siguen siendo rápidos incluso con teselas de zoom 17 repartidas por Europa.
- **Duplicados**: las actividades del mismo tipo que se solapan en el tiempo se fusionan (`Import/ActivityMerge.swift`); se conserva la copia con el mejor GPS y la mayor distancia.
- Los **municipios y códigos postales** se incluyen como archivos binarios compactos (`Resources/Regions/*.fmr`, 33 MB en total) con un índice espacial para búsquedas rápidas.
- La **planificación** usa el planificador de rutas en bici público [OSRM](https://project-osrm.org) de [openstreetmap.de](https://routing.openstreetmap.de). Este determina el mejor orden; después Tileroam elige, dentro de cada objetivo, el punto que menos alarga la ruta.

## Datos de límites

Los archivos de límites se generan con `Tools/build_regions.py` a partir de las fuentes abiertas indicadas en *Ajustes → Fuentes y licencias*:

```bash
python3 -m venv venv && venv/bin/pip install pyshp pyproj shapely
venv/bin/python Tools/build_regions.py <carpeta-de-descargas> Tileroam/Resources/Regions
```

El script documenta de dónde viene cada archivo fuente. Reproyecta a WGS84, fusiona las partes por código, simplifica los límites a ~25 m (municipios) o ~20 m (códigos postales) y escribe el formato compacto.

| País | Fuente y licencia |
|---|---|
| Países Bajos | CBS / Kadaster vía PDOK (CC BY 4.0) |
| Bélgica | NGI-IGN, bpost vía Opendatasoft (licencia de códigos postales: ver la fuente) |
| Alemania | BKG (dl-de/by-2-0); códigos postales © colaboradores de OpenStreetMap (ODbL) |
| Francia | IGN, INSEE; zonas postales Etalab / BAN (Licence Ouverte 2.0) |
| España | IGN, CNIG, Correos (CC BY 4.0) |
| Portugal | Direção-Geral do Território (dominio público) |
| Italia | ISTAT (CC BY 3.0) |
| Suiza | swisstopo (opendata.swiss) |
| Austria | Statistik Austria (CC BY 4.0) |
| Luxemburgo | ACT (CC0) |
| Reino Unido | ONS, OS (OGL v3.0); postcode districts (CC BY 4.0) |
| Irlanda | Tailte Éireann (CC BY 4.0) |
| Dinamarca | SDFI / Klimadatastyrelsen DAGI |
| Noruega | Kartverket (CC BY 4.0) |
| Suecia | © colaboradores de OpenStreetMap (ODbL) |
| Finlandia | Statistics Finland (CC BY 4.0) |
| Islandia | Náttúrufræðistofnun Íslands (CC BY 4.0) |
| Microestados | geoBoundaries / © colaboradores de OpenStreetMap (ODbL) |

Planificación de rutas: © colaboradores de OpenStreetMap (ODbL), rutas por OSRM / FOSSGIS.

## Privacidad

Tileroam no tiene servidor ni analíticas. Tus actividades, teselas y estadísticas se quedan en tu dispositivo y en las carpetas de iCloud que elijas. Los tokens de Strava se guardan en el llavero. Cuando planificas una ruta, el punto de partida y las paradas se envían al servicio de rutas OSRM de openstreetmap.de.

## Estructura del proyecto

```
Tileroam/
  FIT/          decodificador y codificador FIT
  Geo/          teselas, municipios/códigos postales, Eddington, simplificación
  Import/       acceso a carpetas, importación, caché, fusión de duplicados, ActivityStore
  Map/          envoltorio de MKMapView y capas (teselas, zonas, rutas)
  Planning/     planificación (OSRM), GPX, cobertura
  Strava/       cliente de la API de Strava, exportación a .fit
  Views/        pantallas SwiftUI (mapa, ajustes, introducción, panel de planificación)
  Resources/Regions/   límites de municipios y códigos postales incluidos
TileroamWidget/   widget de Eddington
TileroamTests/    pruebas unitarias (Swift Testing)
Tools/             script y fuentes de los datos de límites
```

## Pruebas

```bash
xcodebuild test -project Tileroam.xcodeproj -scheme Tileroam -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Limitaciones

- Los límites de los códigos postales no son datos abiertos en Austria, Luxemburgo, Irlanda, Portugal, Italia, Noruega, Suecia e Islandia.
- Las zonas postales francesas son contornos calculados alrededor de direcciones y pueden solaparse.
- Los postcode districts británicos (2018) y los códigos postales españoles (hacia 2015) son conjuntos de datos más antiguos.
- La planificación depende del servidor OSRM público, un servicio comunitario gratuito sin garantías.
