# Tileroam

[English](README.md) · [Nederlands](README.nl.md) · [Français](README.fr.md) · **Español** · [Deutsch](README.de.md)

Tileroam es una app para iPhone y iPad que muestra todos los lugares por los que has pasado en tus salidas en bici, carreras y paseos: cada tesela del mapa, municipio y código postal que has visitado. Lee archivos `.fit` de una o varias carpetas de iCloud Drive (por ejemplo, exportaciones de HealthFit, Garmin o Wahoo) y puede importar tu historial de Strava. También planifica rutas en bici hacia lugares donde aún no has estado.

![Tileroam en iPhone: teselas, squadratinhos, municipios y planificación de rutas](docs/screenshots/overview.jpg)

## Funciones

- **Teselas**: teselas de mapa de zoom 14 (~1,5 km, como en VeloViewer, StatsHunters y [rideeverytile.com](https://rideeverytile.com/how-big-is-a-tile)) y *squadratinhos* de zoom 17 (~190 m, como en Squadrats). Siempre se cuentan ambos; tú eliges cuál muestra el mapa. Incluye tu **cuadrado máximo** y tu **mayor clúster**.
- **Subidas**: todas las subidas de las carreteras (Cat. 4 a HC como en Strava, y repechos cortos), obtenidas de datos de altitud; cuáles has hecho, en una pestaña del mapa y en Estadísticas, y subidas para incluir al planificar una ruta. Ver [docs/CLIMBS.md](docs/CLIMBS.md).
- **Actividades**: una lista de todas las actividades, de la más reciente a la más antigua, con duración, distancia y potencia media (con medidor de potencia) o velocidad media.
- **Municipios y códigos postales** en los Países Bajos, Bélgica, Luxemburgo, Alemania, Francia, Suiza y Austria, con visitados/total por país.
- **Planificación de rutas** en los Países Bajos, Bélgica, Luxemburgo, Alemania, Francia, Suiza y Austria: toca teselas, municipios o códigos postales sin visitar y Tileroam planifica la ruta circular en bici más corta que pasa por todos. Empieza en tu ubicación, o en un **punto de partida** que buscas o eliges manteniendo pulsado el mapa (se recuerdan los puntos recientes). Las rutas se calculan **en el dispositivo**, así que planificar también funciona sin conexión una vez descargada la zona. Comparte la ruta como **GPX** o guárdala en tu carpeta de iCloud. También puedes abrir un GPX existente para ver qué lugares nuevos aportaría.
- **Strava**: importa todo tu historial con GPS. Las actividades también se guardan como archivos `.fit` estándar en la carpeta que elijas.
- **Duplicados fusionados**: el mismo entrenamiento registrado por varios dispositivos o apps (reloj, Zwift, Strava, HealthFit) cuenta una sola vez.
- **Widgets**: *Teselas a tu alrededor* (un mapa de las teselas cerca de ti) y *Número de Eddington*, en la pantalla de inicio y la pantalla bloqueada.
- **Estadísticas**: países y municipios visitados, números de Eddington para ciclismo, caminar y carrera, y totales por deporte de este año y desde siempre.
- Las **salidas en interior y virtuales** (Zwift, Rouvy, MyWhoosh, rodillo) cuentan en las estadísticas pero quedan fuera del mapa, las teselas, los municipios y los códigos postales.
- **Tu propia copia, sincronizada con iCloud**: los archivos `.fit` importados y las descargas de Strava se guardan en la app (app Archivos › En mi iPhone › Tileroam › Activities), y con la sincronización de iCloud también en iCloud Drive › Tileroam, sin duplicados; otro dispositivo no necesita configuración. Importar es una copia única. Las actividades se eliminan en la lista Actividades.
- **Ajustes → Almacenamiento** muestra los datos de mapa descargados y permite eliminarlos. Las descargas de mapas de más de 25 MB esperan al wifi, salvo que permitas los datos móviles.
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
| Alemania | 10.949 Gemeinden | 8.173 (PLZ) |
| Francia | 34.888 communes | 6.158 (zonas aproximadas) |
| Suiza | 2.128 Gemeinden | 3.181 PLZ |
| Austria | 2.092 Gemeinden | – |

Las teselas, rutas y estadísticas funcionan en todas partes; los municipios, códigos postales y la planificación cubren estos siete países. Los códigos postales solo se incluyen donde sus límites se publican como datos abiertos. Los límites de un país se descargan automáticamente la primera vez que tienes una actividad allí.

## Primeros pasos

Requisitos: Xcode 27 o posterior, iOS/iPadOS 26 o posterior, y una cuenta de pago de Apple Developer para firmar (necesaria para iCloud y los asset packs alojados por Apple).

1. Clona el repositorio y abre `Tileroam.xcodeproj`.
2. En los targets **Tileroam** y **TileroamWidget**, elige tu equipo en *Signing & Capabilities*. Cambia el identificador de bundle (`nl.petervanmanen.Tileroam`) y el App Group (`group.nl.petervanmanen.Tileroam`) por los tuyos.
3. Opcional, para Strava: ver abajo.
4. Ejecuta la app en tu iPhone o iPad. En el primer inicio, importa archivos `.fit` (o una carpeta), conecta Strava o prueba las rutas de ejemplo. Importa más después en *Ajustes → Actividades*.

### Strava (opcional)

El inicio de sesión se hace con la **app de Strava** (un toque en *Authorize*) o, sin la app, con el inicio de sesión web de Strava. El Client Secret se queda en un pequeño **servicio de tokens** ([`backend/strava-auth`](backend/strava-auth), un Cloudflare Worker); la app solo contiene el Client ID.

1. Crea una aplicación de API en [strava.com/settings/api](https://www.strava.com/settings/api) con `localhost` como *Authorization Callback Domain*.
2. Despliega el servicio de tokens como se describe en [`backend/strava-auth/README.md`](backend/strava-auth/README.md).
3. Copia `StravaConfig.example.plist` a `Tileroam/StravaConfig.plist` y rellena `ClientID`. No es secreto; el archivo está en `.gitignore` porque es tu propia configuración. La dirección del servicio de tokens es `StravaServiceURL` en `Tileroam/Servers.plist`, el único archivo con los servidores de la app (también las teselas de planificación); pon ahí la URL de tu Worker.
4. Compila y ejecuta, y toca *Connect with Strava*.

El Client Secret solo se guarda en el servicio de tokens, nunca en la app. Strava forma parte de las compilaciones Debug y Release mediante la condición de compilación `STRAVA`; quítala de *Active Compilation Conditions* para compilar sin Strava. Para otros usuarios, Strava debe aumentar primero el límite de deportistas de tu aplicación (uno por defecto).

Strava permite unas 100 solicitudes cada 15 minutos y 1.000 al día. La lista de actividades llega rápido con rutas simplificadas; el GPS detallado se completa después y la sincronización continúa automáticamente.

## Cómo funciona

- Los **archivos FIT** se leen con un pequeño decodificador integrado (`FIT/FITDecoder.swift`). Rutas, teselas y zonas visitadas se guardan en caché, así que en el siguiente inicio solo se leen los archivos nuevos o modificados.
- **Almacenamiento** (`Import/Library.swift`): cada actividad y ruta está en la app (`Documents/Activities`, `Documents/Routes`). Con la sincronización de iCloud, `Library.pull`/`push` las reflejan en iCloud Drive › Tileroam, tras eliminar archivos duplicados (`ActivityMerge.preferredFile`). Las actividades eliminadas se recuerdan en el almacenamiento clave-valor de iCloud (`Deletions`), para que otros dispositivos eliminen su copia y Strava no las traiga de vuelta. Las carpetas de versiones anteriores se copian una vez (`Library.migrate`).
- Las **teselas** usan la fórmula estándar de teselas Web Mercator (`Geo/TileGrid.swift`). El cuadrado máximo y el clúster se calculan solo sobre las teselas visitadas, por lo que siguen siendo rápidos incluso con teselas de zoom 17 repartidas por Europa.
- **Duplicados**: las actividades del mismo tipo que se solapan en el tiempo se fusionan (`Import/ActivityMerge.swift`); se conserva la copia con el mejor GPS y la mayor distancia.
- Los **municipios y códigos postales** son archivos binarios compactos (`AssetPacks/Regions/*.fmr`, 6,3 MB en total) con un índice espacial para búsquedas rápidas. No van en la app: cada país es un asset pack alojado por Apple (`regions-NL`, …) que la app descarga con Background Assets en cuanto tienes una actividad allí. `Tools/build_asset_packs.sh` los prepara para App Store Connect; en el simulador, `-RegionsDir <repo>/AssetPacks/Regions` los lee directamente.
- La **planificación** funciona en el dispositivo con [Valhalla](https://github.com/valhalla/valhalla), a través de [valhalla-mobile](https://github.com/Rallista/valhalla-mobile), y teselas de OpenStreetMap de los Países Bajos, Bélgica, Luxemburgo, Alemania, Francia, Suiza y Austria. Las teselas están en Cloudflare R2; un plan solo descarga las teselas de Valhalla a su alrededor (25–75 MB, en lugar de 2,2 GB para todo). Las descargas de más de 25 MB esperan al wifi (`MapDataDownloads`). El orden de visita se resuelve con distancias en línea recta (`TripSolver`, mucho más rápido que una matriz de rutas en el dispositivo); después, dentro de cada objetivo, el planificador elige el punto que minimiza el desvío, y Valhalla calcula la ruta circular. Cómo generar y subir las teselas y añadir países: [docs/ROUTING.md](docs/ROUTING.md).

## Datos de límites

Los archivos de límites se generan con `Tools/build_regions.py` a partir de las fuentes abiertas indicadas en *Ajustes → Fuentes y licencias*:

```bash
python3 -m venv venv && venv/bin/pip install pyshp pyproj shapely
venv/bin/python Tools/build_regions.py <carpeta-de-descargas> AssetPacks/Regions
```

El script documenta de dónde viene cada archivo fuente. Reproyecta a WGS84, fusiona las partes por código, simplifica los límites a ~25 m (municipios) o ~20 m (códigos postales) y escribe el formato compacto.

| País | Fuente y licencia |
|---|---|
| Países Bajos | CBS / Kadaster vía PDOK (CC BY 4.0) |
| Bélgica | NGI-IGN, bpost vía Opendatasoft (licencia de códigos postales: ver la fuente) |
| Luxemburgo | ACT (CC0) |
| Alemania | BKG VG250 (dl-de/by-2-0); códigos postales: OpenStreetMap (ODbL) |
| Francia | IGN, INSEE; zonas postales Etalab / BAN (Licence Ouverte 2.0) |
| Suiza | swisstopo (opendata.swiss) |
| Austria | Statistik Austria (CC BY 4.0) |

Planificación de rutas: © colaboradores de OpenStreetMap (ODbL), rutas calculadas por Valhalla en el dispositivo.

## Documentación

- [Guía de uso](docs/MANUAL.md) (en inglés)
- [Soporte y preguntas frecuentes](SUPPORT.md) (en inglés)
- [Kit para la App Store](docs/appstore/README.md): metadatos, capturas, respuestas de privacidad, notas para la revisión

## Estructura del proyecto

```
Tileroam/
  FIT/          decodificador y codificador FIT
  Geo/          teselas, municipios/códigos postales, Eddington, simplificación
  Import/       acceso a carpetas, importación, caché, fusión de duplicados, ActivityStore
  Map/          contenedor de MKMapView y capas (teselas, zonas, rutas)
  Planning/     planificación (Valhalla en el dispositivo), datos de rutas, puntos de partida, GPX, cobertura
  Strava/       cliente de la API de Strava, eventos webhook, exportación a .fit
  Views/        pantallas SwiftUI (mapa, ajustes, almacenamiento, introducción, panel de planificación)
TileroamAssets/   extensión de descarga de Background Assets
TileroamWidget/   widgets: Teselas a tu alrededor, Número de Eddington
TileroamTests/    pruebas unitarias (Swift Testing)
AssetPacks/       límites de municipios y códigos postales, servidos como asset packs
backend/          servicio de tokens de Strava y cola de eventos webhook (Cloudflare Worker)
Tools/            scripts de datos, rutas, asset packs, capturas y publicación
```

## Pruebas

```bash
xcodebuild test -project Tileroam.xcodeproj -scheme Tileroam -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

## Limitaciones

- Los municipios, códigos postales y la planificación cubren solo los Países Bajos, Bélgica, Luxemburgo, Alemania, Francia, Suiza y Austria. [docs/ROUTING.md](docs/ROUTING.md) explica cómo añadir países.
- Luxemburgo no tiene límites de códigos postales como datos abiertos.
- Las rutas son circulares; las rutas de ida de A a B aún no son compatibles.

## Privacidad

Tileroam no tiene cuentas, analíticas ni seguimiento. Tus actividades, teselas y estadísticas se quedan en tu dispositivo y en tu propio iCloud, y la planificación se hace en el dispositivo. Los tokens de Strava se guardan en el llavero. Los servidores son el servicio de tokens de Strava ([`backend/strava-auth`](backend/strava-auth)): intercambia el código de inicio de sesión sin guardar tokens, y conserva los eventos webhook de Strava (números de deportista y de actividad, 30 días como máximo) para que la app pueda eliminar las actividades que borraste en Strava, y los datos de mapa para planificar en Cloudflare R2, que no guarda registros. Consulta la [política de privacidad](PRIVACY.md) (en inglés).

## Licencia

El código fuente está bajo la [licencia MIT](LICENSE). Los datos de límites mantienen las licencias de sus fuentes (CC BY 4.0, CC0, dl-de/by-2-0, ODbL y las licencias de NGI y bpost), y los datos de rutas son © colaboradores de OpenStreetMap (ODbL); consulta [DATA-LICENSES.md](DATA-LICENSES.md).
