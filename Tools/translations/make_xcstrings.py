#!/usr/bin/env python3
"""Generates Tileroam's String Catalogs (en source; nl, fr, es, de)."""
import json
import os
import sys

ROOT = sys.argv[1]
LANGS = ["nl", "fr", "es", "de"]

# key: (nl, fr, es, de)
T = {
    # Map modes & header
    "Tiles": ("Tegels", "Tuiles", "Teselas", "Kacheln"),
    "Routes": ("Routes", "Parcours", "Rutas", "Routen"),
    "Municipalities": ("Gemeenten", "Communes", "Municipios", "Gemeinden"),
    "Postcodes": ("Postcodes", "Codes postaux", "Códigos postales", "Postleitzahlen"),
    "Mode": ("Weergave", "Affichage", "Vista", "Ansicht"),
    "Settings": ("Instellingen", "Réglages", "Ajustes", "Einstellungen"),
    "Stop route planning": ("Routeplanning stoppen", "Arrêter la planification", "Dejar de planificar", "Routenplanung beenden"),
    "Plan a route": ("Route plannen", "Planifier un parcours", "Planificar una ruta", "Route planen"),
    "Route planning · tap unvisited items to select them": (
        "Routeplanning · tik op onbezochte gebieden om ze te kiezen",
        "Planification · touchez les zones non visitées pour les choisir",
        "Planificación · toca zonas no visitadas para elegirlas",
        "Routenplanung · tippe auf unbesuchte Gebiete, um sie auszuwählen"),
    "%@ · max square %lld×%lld · cluster %lld": (
        "%1$@ · max. vierkant %2$lld×%3$lld · cluster %4$lld",
        "%1$@ · carré max %2$lld×%3$lld · cluster %4$lld",
        "%1$@ · cuadrado máx. %2$lld×%3$lld · clúster %4$lld",
        "%1$@ · Max-Quadrat %2$lld×%3$lld · Cluster %4$lld"),
    "%lld on map · %lld without GPS": (
        "%1$lld op de kaart · %2$lld zonder gps",
        "%1$lld sur la carte · %2$lld sans GPS",
        "%1$lld en el mapa · %2$lld sin GPS",
        "%1$lld auf der Karte · %2$lld ohne GPS"),
    "%lld / %lld municipalities visited": (
        "%1$lld / %2$lld gemeenten bezocht", "%1$lld / %2$lld communes visitées",
        "%1$lld / %2$lld municipios visitados", "%1$lld / %2$lld Gemeinden besucht"),
    "%lld / %lld postcodes visited": (
        "%1$lld / %2$lld postcodes bezocht", "%1$lld / %2$lld codes postaux visités",
        "%1$lld / %2$lld códigos postales visitados", "%1$lld / %2$lld Postleitzahlen besucht"),
    "Loading municipalities…": ("Gemeenten laden…", "Chargement des communes…", "Cargando municipios…", "Gemeinden werden geladen…"),
    "Loading postcodes…": ("Postcodes laden…", "Chargement des codes postaux…", "Cargando códigos postales…", "Postleitzahlen werden geladen…"),
    "Stop following location": ("Locatie niet meer volgen", "Ne plus suivre la position", "Dejar de seguir la ubicación", "Standort nicht mehr folgen"),
    "Center on my location": ("Centreren op mijn locatie", "Centrer sur ma position", "Centrar en mi ubicación", "Auf meinen Standort zentrieren"),
    "Location Access Is Off": ("Locatietoegang staat uit", "L’accès à la position est désactivé", "El acceso a la ubicación está desactivado", "Standortzugriff ist aus"),
    "Open Settings": ("Open Instellingen", "Ouvrir Réglages", "Abrir Ajustes", "Einstellungen öffnen"),
    "Cancel": ("Annuleer", "Annuler", "Cancelar", "Abbrechen"),
    "Allow Tileroam to use your location in Settings to center the map on where you are.": (
        "Sta Tileroam in Instellingen toe je locatie te gebruiken om de kaart op je positie te centreren.",
        "Autorisez Tileroam à utiliser votre position dans Réglages pour centrer la carte sur l’endroit où vous êtes.",
        "Permite que Tileroam use tu ubicación en Ajustes para centrar el mapa donde estás.",
        "Erlaube Tileroam in den Einstellungen, deinen Standort zu verwenden, um die Karte auf dich zu zentrieren."),
    "Choose Another Folder": ("Kies een andere map", "Choisir un autre dossier", "Elegir otra carpeta", "Anderen Ordner wählen"),
    "Scanning folder…": ("Map doorzoeken…", "Analyse du dossier…", "Analizando la carpeta…", "Ordner wird durchsucht…"),
    "Postcode %@": ("Postcode %@", "Code postal %@", "Código postal %@", "Postleitzahl %@"),
    "Visited": ("Bezocht", "Visité", "Visitado", "Besucht"),
    "Not visited": ("Niet bezocht", "Non visité", "No visitado", "Nicht besucht"),
    "Importing %lld of %lld activities…": (
        "%1$lld van %2$lld activiteiten importeren…", "Importation de %1$lld sur %2$lld activités…",
        "Importando %1$lld de %2$lld actividades…", "%1$lld von %2$lld Aktivitäten werden importiert…"),
    "Choose your activities folder": ("Kies je map met activiteiten", "Choisissez votre dossier d’activités", "Elige tu carpeta de actividades", "Wähle deinen Aktivitätenordner"),
    "Select the iCloud Drive folder that contains your .fit files.": (
        "Kies de iCloud Drive-map met je .fit-bestanden.", "Sélectionnez le dossier iCloud Drive qui contient vos fichiers .fit.",
        "Selecciona la carpeta de iCloud Drive con tus archivos .fit.", "Wähle den iCloud Drive-Ordner mit deinen .fit-Dateien."),
    "Choose Folder": ("Kies map", "Choisir un dossier", "Elegir carpeta", "Ordner wählen"),
    "Choose Folder…": ("Kies map…", "Choisir un dossier…", "Elegir carpeta…", "Ordner wählen…"),

    # Store / status messages
    "No .fit files found in “%@”. Choose the folder that contains your .fit files.": (
        "Geen .fit-bestanden gevonden in “%@”. Kies de map met je .fit-bestanden.",
        "Aucun fichier .fit trouvé dans « %@ ». Choisissez le dossier qui contient vos fichiers .fit.",
        "No se encontraron archivos .fit en “%@”. Elige la carpeta que contiene tus archivos .fit.",
        "Keine .fit-Dateien in „%@“ gefunden. Wähle den Ordner mit deinen .fit-Dateien."),
    "Could not read “%@”: %@": ("Kan “%1$@” niet lezen: %2$@", "Impossible de lire « %1$@ » : %2$@", "No se pudo leer “%1$@”: %2$@", "„%1$@“ konnte nicht gelesen werden: %2$@"),
    "Could not access “%@”: %@": ("Geen toegang tot “%1$@”: %2$@", "Impossible d’accéder à « %1$@ » : %2$@", "No se pudo acceder a “%1$@”: %2$@", "Kein Zugriff auf „%1$@“: %2$@"),
    "Could not move earlier saved files: %@": ("Kan eerder bewaarde bestanden niet verplaatsen: %@", "Impossible de déplacer les fichiers enregistrés : %@",
                                                "No se pudieron mover los archivos guardados: %@", "Früher gespeicherte Dateien konnten nicht verschoben werden: %@"),
    "Choose a save folder in Settings to download detailed GPS": (
        "Kies een bewaarmap in Instellingen om gedetailleerde gps te downloaden",
        "Choisissez un dossier d’enregistrement dans Réglages pour télécharger le GPS détaillé",
        "Elige una carpeta de guardado en Ajustes para descargar el GPS detallado",
        "Wähle in den Einstellungen einen Speicherordner, um detailliertes GPS zu laden"),
    "Strava limit reached – continuing at %@": ("Strava-limiet bereikt – verder om %@", "Limite Strava atteinte – reprise à %@",
                                                "Límite de Strava alcanzado – se reanuda a las %@", "Strava-Limit erreicht – weiter um %@"),
    "Fetching Strava activities…": ("Strava-activiteiten ophalen…", "Récupération des activités Strava…", "Obteniendo actividades de Strava…", "Strava-Aktivitäten werden geladen…"),
    "Checking Strava for new activities…": ("Strava controleren op nieuwe activiteiten…", "Recherche de nouvelles activités Strava…",
                                            "Buscando actividades nuevas en Strava…", "Suche nach neuen Strava-Aktivitäten…"),
    "Saving Strava activities to folder: %lld of %lld": (
        "Strava-activiteiten bewaren: %1$lld van %2$lld", "Enregistrement des activités Strava : %1$lld sur %2$lld",
        "Guardando actividades de Strava: %1$lld de %2$lld", "Strava-Aktivitäten werden gespeichert: %1$lld von %2$lld"),
    "Strava detailed GPS: %lld of %lld": ("Strava gedetailleerde gps: %1$lld van %2$lld", "GPS détaillé Strava : %1$lld sur %2$lld",
                                          "GPS detallado de Strava: %1$lld de %2$lld", "Detailliertes Strava-GPS: %1$lld von %2$lld"),
    "Could not save to folder: %@": ("Kan niet in map bewaren: %@", "Impossible d’enregistrer dans le dossier : %@",
                                     "No se pudo guardar en la carpeta: %@", "Speichern im Ordner fehlgeschlagen: %@"),
    "On My iPhone › Tileroam (app storage)": ("Op mijn iPhone › Tileroam (app-opslag)", "Sur mon iPhone › Tileroam (stockage de l’app)",
                                               "En mi iPhone › Tileroam (almacenamiento de la app)", "Auf meinem iPhone › Tileroam (App-Speicher)"),
    "On My iPhone": ("Op mijn iPhone", "Sur mon iPhone", "En mi iPhone", "Auf meinem iPhone"),
    "Location access is off. Allow Tileroam to use your location in Settings to plan a route from where you are.": (
        "Locatietoegang staat uit. Sta Tileroam in Instellingen toe je locatie te gebruiken om een route vanaf je positie te plannen.",
        "L’accès à la position est désactivé. Autorisez Tileroam dans Réglages à utiliser votre position pour planifier un parcours depuis l’endroit où vous êtes.",
        "El acceso a la ubicación está desactivado. Permite a Tileroam usar tu ubicación en Ajustes para planificar una ruta desde donde estás.",
        "Der Standortzugriff ist aus. Erlaube Tileroam in den Einstellungen, deinen Standort zu verwenden, um eine Route ab deinem Standort zu planen."),

    # Intro
    "Skip": ("Overslaan", "Passer", "Omitir", "Überspringen"),
    "Next": ("Volgende", "Suivant", "Siguiente", "Weiter"),
    "Get Started": ("Aan de slag", "Commencer", "Empezar", "Los geht’s"),
    "Welcome to Tileroam": ("Welkom bij Tileroam", "Bienvenue dans Tileroam", "Bienvenido a Tileroam", "Willkommen bei Tileroam"),
    "See everywhere you have been: every map tile, municipality and postcode area you have visited on your rides, runs and walks.": (
        "Zie overal waar je bent geweest: elke kaarttegel, gemeente en elk postcodegebied dat je hebt bezocht tijdens je ritten, hardlooprondes en wandelingen.",
        "Voyez partout où vous êtes allé : chaque tuile, commune et zone de code postal visitée lors de vos sorties à vélo, courses et marches.",
        "Mira todo lo que has recorrido: cada tesela del mapa, municipio y código postal que has visitado en tus salidas en bici, carreras y paseos.",
        "Sieh, wo du überall warst: jede Kartenkachel, Gemeinde und jedes Postleitzahlgebiet, das du auf Radtouren, Läufen und Wanderungen besucht hast."),
    "Tiles (zoom 14) and squadratinhos (zoom 17), with your max square and cluster": (
        "Tegels (zoom 14) en squadratinhos (zoom 17), met je max. vierkant en cluster",
        "Tuiles (zoom 14) et squadratinhos (zoom 17), avec votre carré max et votre cluster",
        "Teselas (zoom 14) y squadratinhos (zoom 17), con tu cuadrado máximo y clúster",
        "Kacheln (Zoom 14) und Squadratinhos (Zoom 17), mit Max-Quadrat und Cluster"),
    "Municipalities and postcodes in 22 European countries": (
        "Gemeenten en postcodes in 22 Europese landen", "Communes et codes postaux dans 22 pays européens",
        "Municipios y códigos postales en 22 países europeos", "Gemeinden und Postleitzahlen in 22 europäischen Ländern"),
    "Your Eddington number, also as a widget": ("Je Eddington-getal, ook als widget", "Votre nombre d’Eddington, aussi en widget",
                                                "Tu número de Eddington, también como widget", "Deine Eddington-Zahl, auch als Widget"),
    "Add Your Activities": ("Voeg je activiteiten toe", "Ajoutez vos activités", "Añade tus actividades", "Füge deine Aktivitäten hinzu"),
    "Choose the iCloud Drive folder with your .fit files, for example exports from HealthFit, Garmin or Wahoo. Tileroam reads them in place and picks up new files automatically.": (
        "Kies de iCloud Drive-map met je .fit-bestanden, bijvoorbeeld exports van HealthFit, Garmin of Wahoo. Tileroam leest ze ter plekke en ziet nieuwe bestanden automatisch.",
        "Choisissez le dossier iCloud Drive contenant vos fichiers .fit, par exemple des exports HealthFit, Garmin ou Wahoo. Tileroam les lit sur place et détecte automatiquement les nouveaux fichiers.",
        "Elige la carpeta de iCloud Drive con tus archivos .fit, por ejemplo exportaciones de HealthFit, Garmin o Wahoo. Tileroam los lee donde están y detecta los nuevos automáticamente.",
        "Wähle den iCloud Drive-Ordner mit deinen .fit-Dateien, zum Beispiel Exporte aus HealthFit, Garmin oder Wahoo. Tileroam liest sie direkt und erkennt neue Dateien automatisch."),
    "You can change this later in Settings.": ("Je kunt dit later wijzigen in Instellingen.", "Vous pourrez le modifier plus tard dans Réglages.",
                                               "Puedes cambiarlo más tarde en Ajustes.", "Du kannst das später in den Einstellungen ändern."),
    "Folder: %@": ("Map: %@", "Dossier : %@", "Carpeta: %@", "Ordner: %@"),
    "Connect Strava": ("Koppel Strava", "Connectez Strava", "Conecta Strava", "Strava verbinden"),
    "Optionally connect Strava to download your full history with GPS. Activities are also saved as .fit files in a save folder of your choice, such as iCloud Drive › Tileroam.": (
        "Koppel desgewenst Strava om je volledige geschiedenis met gps te downloaden. Activiteiten worden ook als .fit-bestand bewaard in een map naar keuze, zoals iCloud Drive › Tileroam.",
        "Connectez Strava si vous le souhaitez pour télécharger tout votre historique avec le GPS. Les activités sont aussi enregistrées en fichiers .fit dans le dossier de votre choix, par exemple iCloud Drive › Tileroam.",
        "Si quieres, conecta Strava para descargar todo tu historial con GPS. Las actividades también se guardan como archivos .fit en la carpeta que elijas, como iCloud Drive › Tileroam.",
        "Verbinde optional Strava, um deinen ganzen Verlauf mit GPS zu laden. Aktivitäten werden auch als .fit-Dateien in einem Ordner deiner Wahl gespeichert, etwa iCloud Drive › Tileroam."),
    "Connected as %@": ("Gekoppeld als %@", "Connecté en tant que %@", "Conectado como %@", "Verbunden als %@"),
    "Strava is not available in this version.": ("Strava is niet beschikbaar in deze versie.", "Strava n’est pas disponible dans cette version.",
                                                 "Strava no está disponible en esta versión.", "Strava ist in dieser Version nicht verfügbar."),
    "Choose Save Folder…": ("Kies bewaarmap…", "Choisir le dossier d’enregistrement…", "Elegir carpeta de guardado…", "Speicherordner wählen…"),
    "Save folder: %@": ("Bewaarmap: %@", "Dossier d’enregistrement : %@", "Carpeta de guardado: %@", "Speicherordner: %@"),
    "Plan Routes to New Places": ("Plan routes naar nieuwe plekken", "Planifiez des parcours vers de nouveaux lieux",
                                  "Planifica rutas a lugares nuevos", "Plane Routen zu neuen Orten"),
    "Tap the route button, select unvisited tiles, municipalities or postcodes, and Tileroam plans the shortest cycling round trip from where you are. Export it as GPX for your bike computer.": (
        "Tik op de routeknop, kies onbezochte tegels, gemeenten of postcodes en Tileroam plant de kortste fietsrondrit vanaf je locatie. Exporteer hem als GPX voor je fietscomputer.",
        "Touchez le bouton parcours, choisissez des tuiles, communes ou codes postaux non visités, et Tileroam planifie la boucle à vélo la plus courte depuis votre position. Exportez-la en GPX pour votre compteur.",
        "Toca el botón de ruta, elige teselas, municipios o códigos postales sin visitar y Tileroam planifica la ruta circular en bici más corta desde donde estás. Expórtala como GPX para tu ciclocomputador.",
        "Tippe auf die Routentaste, wähle unbesuchte Kacheln, Gemeinden oder Postleitzahlen, und Tileroam plant die kürzeste Radrundfahrt ab deinem Standort. Exportiere sie als GPX für deinen Radcomputer."),
    "Select as many places as you like, mixed types allowed": ("Kies zoveel plekken als je wilt, ook gemengd", "Choisissez autant de lieux que vous voulez, types mélangés",
                                                                "Elige tantos lugares como quieras, de cualquier tipo", "Wähle beliebig viele Orte, auch gemischt"),
    "Routes follow cycle-friendly roads": ("Routes volgen fietsvriendelijke wegen", "Les parcours suivent des routes adaptées au vélo",
                                           "Las rutas siguen vías aptas para bicis", "Routen folgen fahrradfreundlichen Wegen"),
    "Share as GPX or open an existing GPX to see what it would collect": (
        "Deel als GPX of open een bestaande GPX om te zien wat die oplevert",
        "Partagez en GPX ou ouvrez un GPX existant pour voir ce qu’il permettrait de collecter",
        "Compártela como GPX o abre un GPX existente para ver qué conseguirías",
        "Als GPX teilen oder ein vorhandenes GPX öffnen, um zu sehen, was es bringt"),
    "You're All Set": ("Je bent er klaar voor", "Tout est prêt", "Todo listo", "Alles bereit"),
    "Switch between tiles, routes, municipalities and postcodes at the top of the map. Settings has your statistics, countries and folders.": (
        "Wissel bovenaan de kaart tussen tegels, routes, gemeenten en postcodes. In Instellingen vind je je statistieken, landen en mappen.",
        "Passez des tuiles aux parcours, communes et codes postaux en haut de la carte. Réglages contient vos statistiques, pays et dossiers.",
        "Cambia entre teselas, rutas, municipios y códigos postales en la parte superior del mapa. En Ajustes están tus estadísticas, países y carpetas.",
        "Wechsle oben auf der Karte zwischen Kacheln, Routen, Gemeinden und Postleitzahlen. In den Einstellungen findest du Statistiken, Länder und Ordner."),

    # Planning
    "Route planning failed: %@": ("Routeplanning mislukt: %@", "Échec de la planification : %@", "Error al planificar la ruta: %@", "Routenplanung fehlgeschlagen: %@"),
    "Tap unvisited tiles, municipalities or postcodes to add them. The route starts and ends at the starting point; long-press the map to start or end there.": ("Tik op onbezochte tegels, gemeenten of postcodes om ze toe te voegen. De route begint en eindigt bij het startpunt; houd de kaart ingedrukt om daar te starten of te eindigen.", "Touchez des tuiles, communes ou codes postaux non visités pour les ajouter. Le parcours commence et se termine au point de départ ; appuyez longuement sur la carte pour partir ou arriver à cet endroit.", "Toca teselas, municipios o códigos postales sin visitar para añadirlos. La ruta empieza y termina en el punto de partida; mantén pulsado el mapa para empezar o terminar allí.", "Tippe auf unbesuchte Kacheln, Gemeinden oder Postleitzahlen, um sie hinzuzufügen. Die Route beginnt und endet am Startpunkt; halte die Karte gedrückt, um dort zu starten oder zu enden."),
    "Open GPX…": ("Open GPX…", "Ouvrir un GPX…", "Abrir GPX…", "GPX öffnen…"),
    "Clear": ("Wis", "Effacer", "Borrar", "Löschen"),
    "Plan Route": ("Plan route", "Planifier", "Planificar ruta", "Route planen"),
    "Selection changed – plan again to include it.": ("Selectie gewijzigd – plan opnieuw om die mee te nemen.", "Sélection modifiée – planifiez à nouveau pour l’inclure.",
                                                      "La selección ha cambiado: vuelve a planificar para incluirla.", "Auswahl geändert – plane neu, um sie einzubeziehen."),
    "New: %@": ("Nieuw: %@", "Nouveau : %@", "Nuevo: %@", "Neu: %@"),
    "Not reached: %@": ("Niet bereikt: %@", "Non atteint : %@", "No alcanzado: %@", "Nicht erreicht: %@"),
    "Close route": ("Route sluiten", "Fermer le parcours", "Cerrar ruta", "Route schließen"),
    "Replan": ("Opnieuw plannen", "Replanifier", "Volver a planificar", "Neu planen"),
    "Open Another GPX…": ("Open andere GPX…", "Ouvrir un autre GPX…", "Abrir otro GPX…", "Anderes GPX öffnen…"),
    "Share GPX": ("Deel GPX", "Partager le GPX", "Compartir GPX", "GPX teilen"),
    "Save to Folder": ("Bewaar in map", "Enregistrer dans le dossier", "Guardar en carpeta", "Im Ordner speichern"),
    "Save to %@": ("Bewaar in %@", "Enregistrer dans %@", "Guardar en %@", "In %@ speichern"),
    "Nothing selected": ("Niets geselecteerd", "Rien de sélectionné", "Nada seleccionado", "Nichts ausgewählt"),
    "Selected: %@": ("Geselecteerd: %@", "Sélection : %@", "Seleccionado: %@", "Ausgewählt: %@"),
    "Finding your location…": ("Je locatie bepalen…", "Recherche de votre position…", "Buscando tu ubicación…", "Standort wird ermittelt…"),
    "Checking which tiles and areas this route passes…": (
        "Controleren welke tegels en gebieden deze route raakt…", "Vérification des tuiles et zones traversées…",
        "Comprobando qué teselas y zonas recorre esta ruta…", "Prüfe, welche Kacheln und Gebiete die Route berührt…"),
    "Could not read “%@” as a GPX route.": ("Kan “%@” niet lezen als GPX-route.", "Impossible de lire « %@ » comme parcours GPX.",
                                           "No se pudo leer “%@” como ruta GPX.", "„%@“ konnte nicht als GPX-Route gelesen werden."),
    "Saved to %@/Routes/%@": ("Bewaard in %1$@/Routes/%2$@", "Enregistré dans %1$@/Routes/%2$@", "Guardado en %1$@/Routes/%2$@", "Gespeichert in %1$@/Routes/%2$@"),
    "Choose a save folder in Settings first (e.g. iCloud Drive › Tileroam).": (
        "Kies eerst een bewaarmap in Instellingen (bijv. iCloud Drive › Tileroam).",
        "Choisissez d’abord un dossier d’enregistrement dans Réglages (p. ex. iCloud Drive › Tileroam).",
        "Elige primero una carpeta de guardado en Ajustes (p. ej., iCloud Drive › Tileroam).",
        "Wähle zuerst einen Speicherordner in den Einstellungen (z. B. iCloud Drive › Tileroam)."),
    "Could not save: %@": ("Kan niet bewaren: %@", "Impossible d’enregistrer : %@", "No se pudo guardar: %@", "Speichern fehlgeschlagen: %@"),
    "Tile %lld/%lld": ("Tegel %1$lld/%2$lld", "Tuile %1$lld/%2$lld", "Tesela %1$lld/%2$lld", "Kachel %1$lld/%2$lld"),
    "Squadratinho %lld/%lld": ("Squadratinho %1$lld/%2$lld", "Squadratinho %1$lld/%2$lld", "Squadratinho %1$lld/%2$lld", "Squadratinho %1$lld/%2$lld"),
    "nothing new": ("niets nieuws", "rien de nouveau", "nada nuevo", "nichts Neues"),
    "Tileroam route": ("Tileroam-route", "Parcours Tileroam", "Ruta de Tileroam", "Tileroam-Route"),
    "Finding the best order…": ("Beste volgorde zoeken…", "Recherche du meilleur ordre…", "Buscando el mejor orden…", "Beste Reihenfolge wird gesucht…"),
    "Planning the cycling route…": ("Fietsroute plannen…", "Planification du parcours à vélo…", "Planificando la ruta en bici…", "Radroute wird geplant…"),
    "Improving the route…": ("Route verbeteren…", "Amélioration du parcours…", "Mejorando la ruta…", "Route wird verbessert…"),
    "Checking which tiles and areas you pass…": ("Controleren welke tegels en gebieden je passeert…", "Vérification des tuiles et zones traversées…",
                                                 "Comprobando qué teselas y zonas atraviesas…", "Prüfe, welche Kacheln und Gebiete du passierst…"),
    "Route planning": ("Routeplanning", "Planification d’itinéraire", "Planificación de rutas", "Routenplanung"),
    "Activity data from Strava when connected": ("Activiteitgegevens van Strava, indien gekoppeld", "Données d’activité de Strava si connecté",
                                                 "Datos de actividad de Strava, si está conectado", "Aktivitätsdaten von Strava, wenn verbunden"),

    # Settings
    "Import Folder": ("Importmap", "Dossier d’import", "Carpeta de importación", "Importordner"),
    "Statistics": ("Statistieken", "Statistiques", "Estadísticas", "Statistik"),
    "Could not read (%lld)": ("Niet leesbaar (%lld)", "Illisibles (%lld)", "No legibles (%lld)", "Nicht lesbar (%lld)"),
    "Selected": ("Gekozen", "Sélectionné", "Seleccionada", "Ausgewählt"),
    "None": ("Geen", "Aucun", "Ninguna", "Keiner"),
    "Save Folder": ("Bewaarmap", "Dossier d’enregistrement", "Carpeta de guardado", "Speicherordner"),
    "Tileroam saves downloaded activities as .fit files here, in a “%@” subfolder. Tip: in the picker, go to iCloud Drive, create a new folder “Tileroam” and open it.": (
        "Tileroam bewaart gedownloade activiteiten hier als .fit-bestanden, in een submap “%@”. Tip: ga in de kiezer naar iCloud Drive, maak een nieuwe map “Tileroam” en open die.",
        "Tileroam enregistre ici les activités téléchargées en fichiers .fit, dans un sous-dossier « %@ ». Astuce : dans le sélecteur, allez dans iCloud Drive, créez un dossier « Tileroam » et ouvrez-le.",
        "Tileroam guarda aquí las actividades descargadas como archivos .fit, en una subcarpeta “%@”. Consejo: en el selector, ve a iCloud Drive, crea una carpeta “Tileroam” y ábrela.",
        "Tileroam speichert geladene Aktivitäten hier als .fit-Dateien im Unterordner „%@“. Tipp: Gehe in der Auswahl zu iCloud Drive, erstelle einen Ordner „Tileroam“ und öffne ihn."),
    "Rescan Now": ("Nu opnieuw scannen", "Analyser maintenant", "Analizar ahora", "Jetzt neu scannen"),
    "Show on map": ("Toon op kaart", "Afficher sur la carte", "Mostrar en el mapa", "Auf Karte zeigen"),
    "Zoom 14 tiles (~1.5 km in the Netherlands) are the explorer tiles of VeloViewer, StatsHunters and rideeverytile.com. Zoom 17 squadratinhos (~190 m) are used by Squadrats. Both are always counted; this setting chooses which one the map, statistics and route planning use.": (
        "Zoom 14-tegels (~1,5 km in Nederland) zijn de explorer tiles van VeloViewer, StatsHunters en rideeverytile.com. Zoom 17-squadratinhos (~190 m) worden gebruikt door Squadrats. Beide worden altijd geteld; deze instelling bepaalt welke de kaart, statistieken en routeplanning gebruiken.",
        "Les tuiles zoom 14 (~1,5 km aux Pays-Bas) sont les explorer tiles de VeloViewer, StatsHunters et rideeverytile.com. Les squadratinhos zoom 17 (~190 m) sont utilisés par Squadrats. Les deux sont toujours comptés ; ce réglage choisit celui qu’utilisent la carte, les statistiques et la planification.",
        "Las teselas de zoom 14 (~1,5 km en los Países Bajos) son las explorer tiles de VeloViewer, StatsHunters y rideeverytile.com. Los squadratinhos de zoom 17 (~190 m) los usa Squadrats. Siempre se cuentan ambos; este ajuste elige cuál usan el mapa, las estadísticas y la planificación.",
        "Zoom-14-Kacheln (~1,5 km in den Niederlanden) sind die Explorer-Tiles von VeloViewer, StatsHunters und rideeverytile.com. Zoom-17-Squadratinhos (~190 m) nutzt Squadrats. Beide werden immer gezählt; diese Einstellung bestimmt, welche Karte, Statistik und Routenplanung verwenden."),
    "Eddington cycling": ("Eddington fietsen", "Eddington vélo", "Eddington ciclismo", "Eddington Radfahren"),
    "Eddington running": ("Eddington hardlopen", "Eddington course", "Eddington carrera", "Eddington Laufen"),
    "Activities": ("Activiteiten", "Activités", "Actividades", "Aktivitäten"),
    "Without GPS": ("Zonder gps", "Sans GPS", "Sin GPS", "Ohne GPS"),
    "Distance": ("Afstand", "Distance", "Distancia", "Distanz"),
    "Show Introduction": ("Toon introductie", "Afficher l’introduction", "Mostrar introducción", "Einführung anzeigen"),
    "Sources & Licenses": ("Bronnen en licenties", "Sources et licences", "Fuentes y licencias", "Quellen und Lizenzen"),
    "Clear Cache & Re-import": ("Cache wissen en opnieuw importeren", "Vider le cache et réimporter", "Borrar caché y reimportar", "Cache leeren und neu importieren"),
    "Activities without GPS (indoor workouts, or workouts synced into Apple Health without a route) are counted but can't be drawn.": (
        "Activiteiten zonder gps (binnentrainingen of trainingen die zonder route in Apple Gezondheid zijn gezet) tellen mee maar kunnen niet getekend worden.",
        "Les activités sans GPS (séances en intérieur ou synchronisées dans Santé sans tracé) sont comptées mais ne peuvent pas être dessinées.",
        "Las actividades sin GPS (entrenamientos en interior o sincronizados con Salud sin ruta) se cuentan pero no se pueden dibujar.",
        "Aktivitäten ohne GPS (Indoor-Training oder ohne Route in Apple Health synchronisiert) werden gezählt, können aber nicht gezeichnet werden."),
    "Done": ("Gereed", "OK", "OK", "Fertig"),
    "Max square %lld×%lld · cluster %lld": ("Max. vierkant %1$lld×%2$lld · cluster %3$lld", "Carré max %1$lld×%2$lld · cluster %3$lld",
                                            "Cuadrado máx. %1$lld×%2$lld · clúster %3$lld", "Max-Quadrat %1$lld×%2$lld · Cluster %3$lld"),
    "%@ %@": ("%1$@ %2$@", "%1$@ %2$@", "%1$@ %2$@", "%1$@ %2$@"),
    "%lld/%lld municipalities": ("%1$lld/%2$lld gemeenten", "%1$lld/%2$lld communes", "%1$lld/%2$lld municipios", "%1$lld/%2$lld Gemeinden"),
    "%lld/%lld municipalities · %lld/%lld postcodes": (
        "%1$lld/%2$lld gemeenten · %3$lld/%4$lld postcodes", "%1$lld/%2$lld communes · %3$lld/%4$lld codes postaux",
        "%1$lld/%2$lld municipios · %3$lld/%4$lld códigos postales", "%1$lld/%2$lld Gemeinden · %3$lld/%4$lld Postleitzahlen"),
    "Countries": ("Landen", "Pays", "Países", "Länder"),
    "Municipalities and postcodes are counted for the switched-on countries. Postcodes are only available where their boundaries are open data. In the United Kingdom and Ireland, local authorities count as municipalities; in Andorra and San Marino, parishes and castelli.": (
        "Gemeenten en postcodes worden geteld voor de ingeschakelde landen. Postcodes zijn er alleen waar de grenzen open data zijn. In het Verenigd Koninkrijk en Ierland tellen local authorities als gemeenten; in Andorra en San Marino de parochies en castelli.",
        "Les communes et codes postaux sont comptés pour les pays activés. Les codes postaux ne sont disponibles que là où leurs limites sont des données ouvertes. Au Royaume-Uni et en Irlande, les autorités locales comptent comme communes ; en Andorre et à Saint-Marin, les paroisses et castelli.",
        "Los municipios y códigos postales se cuentan para los países activados. Los códigos postales solo están disponibles donde sus límites son datos abiertos. En el Reino Unido e Irlanda, las autoridades locales cuentan como municipios; en Andorra y San Marino, las parroquias y castelli.",
        "Gemeinden und Postleitzahlen werden für die aktivierten Länder gezählt. Postleitzahlen gibt es nur, wo ihre Grenzen offene Daten sind. Im Vereinigten Königreich und in Irland zählen Local Authorities als Gemeinden, in Andorra und San Marino die Parroquias und Castelli."),
    "Countries are counted as soon as you have an activity there. Postcodes are only available where their boundaries are open data. In the United Kingdom and Ireland, local authorities count as municipalities; in Andorra and San Marino, parishes and castelli.": (
        "Een land telt mee zodra je er een activiteit hebt. Postcodes zijn er alleen waar de grenzen open data zijn. In het Verenigd Koninkrijk en Ierland tellen local authorities als gemeenten; in Andorra en San Marino de parochies en castelli.",
        "Un pays est compté dès que vous y avez une activité. Les codes postaux ne sont disponibles que là où leurs limites sont des données ouvertes. Au Royaume-Uni et en Irlande, les autorités locales comptent comme communes ; en Andorre et à Saint-Marin, les paroisses et castelli.",
        "Un país cuenta en cuanto tienes una actividad allí. Los códigos postales solo están disponibles donde sus límites son datos abiertos. En el Reino Unido e Irlanda, las autoridades locales cuentan como municipios; en Andorra y San Marino, las parroquias y castelli.",
        "Ein Land zählt, sobald du dort eine Aktivität hast. Postleitzahlen gibt es nur, wo ihre Grenzen offene Daten sind. Im Vereinigten Königreich und in Irland zählen Local Authorities als Gemeinden, in Andorra und San Marino die Parroquias und Castelli."),
    "Couldn't download the municipalities and postcodes of %@. They will load when you're online.": (
        "De gemeenten en postcodes van %@ konden niet worden gedownload. Ze worden geladen zodra je online bent.",
        "Impossible de télécharger les communes et codes postaux de %@. Ils se chargeront dès que vous serez en ligne.",
        "No se pudieron descargar los municipios y códigos postales de %@. Se cargarán cuando tengas conexión.",
        "Die Gemeinden und Postleitzahlen von %@ konnten nicht geladen werden. Sie werden geladen, sobald du online bist."),
    "Couldn't load the municipalities and postcodes of %@. Tileroam tries again when you open it.": (
        "De gemeenten en postcodes van %@ konden niet worden geladen. Tileroam probeert het opnieuw als je de app opent.",
        "Impossible de charger les communes et codes postaux de %@. Tileroam réessaie à la prochaine ouverture.",
        "No se pudieron cargar los municipios y códigos postales de %@. Tileroam lo intentará de nuevo al abrirla.",
        "Die Gemeinden und Postleitzahlen von %@ konnten nicht geladen werden. Tileroam versucht es beim nächsten Öffnen erneut."),
    "Try Again": ("Probeer opnieuw", "Réessayer", "Reintentar", "Erneut versuchen"),
    "Delete files saved from Strava?": ("Bestanden van Strava verwijderen?", "Supprimer les fichiers enregistrés depuis Strava ?",
                                        "¿Eliminar los archivos guardados de Strava?", "Von Strava gespeicherte Dateien löschen?"),
    "Delete Files Saved from Strava (%lld)": ("Verwijder bestanden van Strava (%lld)", "Supprimer les fichiers de Strava (%lld)",
                                              "Eliminar archivos de Strava (%lld)", "Dateien von Strava löschen (%lld)"),
    "Disconnect and Delete Strava Files": ("Ontkoppel en verwijder Strava-bestanden", "Déconnecter et supprimer les fichiers Strava",
                                           "Desconectar y eliminar archivos de Strava", "Trennen und Strava-Dateien löschen"),
    "Disconnect, Keep Files": ("Ontkoppel, bewaar bestanden", "Déconnecter, garder les fichiers",
                               "Desconectar, conservar archivos", "Trennen, Dateien behalten"),
    "Strava activities are removed from this device. You can also delete the .fit files Tileroam saved from Strava, in all its folders; files from other apps are never touched.": (
        "Strava-activiteiten worden van dit apparaat verwijderd. Je kunt ook de .fit-bestanden verwijderen die Tileroam van Strava heeft bewaard, in al zijn mappen; bestanden van andere apps blijven altijd staan.",
        "Les activités Strava sont supprimées de cet appareil. Vous pouvez aussi supprimer les fichiers .fit que Tileroam a enregistrés depuis Strava, dans tous ses dossiers ; les fichiers des autres apps ne sont jamais touchés.",
        "Las actividades de Strava se eliminan de este dispositivo. También puedes eliminar los archivos .fit que Tileroam guardó de Strava, en todas sus carpetas; los archivos de otras apps nunca se tocan.",
        "Strava-Aktivitäten werden von diesem Gerät entfernt. Du kannst auch die .fit-Dateien löschen, die Tileroam von Strava gespeichert hat, in all seinen Ordnern; Dateien anderer Apps bleiben unberührt."),
    "Only the .fit files Tileroam saved from Strava are deleted; files from other apps are kept.": (
        "Alleen de .fit-bestanden die Tileroam van Strava heeft bewaard worden verwijderd; bestanden van andere apps blijven staan.",
        "Seuls les fichiers .fit que Tileroam a enregistrés depuis Strava sont supprimés ; les fichiers des autres apps sont conservés.",
        "Solo se eliminan los archivos .fit que Tileroam guardó de Strava; los de otras apps se conservan.",
        "Nur die .fit-Dateien, die Tileroam von Strava gespeichert hat, werden gelöscht; Dateien anderer Apps bleiben erhalten."),
    "Strava access was revoked. Tileroam removed the activities it saved from Strava.": (
        "De toegang tot Strava is ingetrokken. Tileroam heeft de activiteiten verwijderd die het van Strava had bewaard.",
        "L’accès à Strava a été révoqué. Tileroam a supprimé les activités enregistrées depuis Strava.",
        "Se revocó el acceso a Strava. Tileroam eliminó las actividades que había guardado de Strava.",
        "Der Zugriff auf Strava wurde widerrufen. Tileroam hat die von Strava gespeicherten Aktivitäten gelöscht."),
    "Loading the route planning data…": ("Routeplanner laden…", "Chargement des données d’itinéraire…", "Cargando los datos de rutas…", "Routendaten werden geladen…"),
    "Route planning is available in the Netherlands, Belgium, Luxembourg, Germany, France, Switzerland and Austria. The starting point and all selected items must be there.": (
        "Routeplanning is beschikbaar in Nederland, België, Luxemburg, Duitsland, Frankrijk, Zwitserland en Oostenrijk. Het startpunt en alle geselecteerde onderdelen moeten daar liggen.",
        "La planification d’itinéraires est disponible aux Pays-Bas, en Belgique, au Luxembourg, en Allemagne, en France, en Suisse et en Autriche. Le point de départ et tous les éléments sélectionnés doivent s’y trouver.",
        "La planificación de rutas está disponible en los Países Bajos, Bélgica, Luxemburgo, Alemania, Francia, Suiza y Austria. El punto de partida y todos los elementos seleccionados deben estar allí.",
        "Die Routenplanung ist in den Niederlanden, Belgien, Luxemburg, Deutschland, Frankreich, der Schweiz und Österreich verfügbar. Der Startpunkt und alle ausgewählten Elemente müssen dort liegen."),
    "The route planning data couldn't be loaded: %@": ("De gegevens voor routeplanning konden niet worden geladen: %@",
        "Impossible de charger les données d’itinéraire : %@", "No se pudieron cargar los datos de rutas: %@",
        "Die Daten für die Routenplanung konnten nicht geladen werden: %@"),
    "Downloading map data for route planning (about %@)…": ("Kaartgegevens voor routeplanning downloaden (ongeveer %@)…",
        "Téléchargement des données de carte pour les itinéraires (environ %@)…",
        "Descargando datos de mapa para planificar rutas (unos %@)…",
        "Kartendaten für die Routenplanung werden geladen (etwa %@)…"),
    "Municipalities and postcodes in the Netherlands, Belgium, Luxembourg, Germany, France, Switzerland and Austria": ("Gemeenten en postcodes in Nederland, België, Luxemburg, Duitsland, Frankrijk, Zwitserland en Oostenrijk",
        "Communes et codes postaux aux Pays-Bas, en Belgique, au Luxembourg, en Allemagne, en France, en Suisse et en Autriche", "Municipios y códigos postales en los Países Bajos, Bélgica, Luxemburgo, Alemania, Francia, Suiza y Austria",
        "Gemeinden und Postleitzahlen in den Niederlanden, Belgien, Luxemburg, Deutschland, Frankreich, der Schweiz und Österreich"),
    # Storage & Wi-Fi rule
    "Storage": ("Opslag", "Stockage", "Almacenamiento", "Speicher"),
    "Activity cache": ("Activiteitencache", "Cache des activités", "Caché de actividades", "Aktivitäten-Cache"),
    "%@ area": ("Gebied %@", "Zone de %@", "Zona de %@", "Gebiet %@"),
    "Download Anyway": ("Toch downloaden", "Télécharger quand même", "Descargar de todos modos", "Trotzdem laden"),
    "Download Map Data over Mobile Data": ("Kaartgegevens via mobiele data downloaden", "Télécharger les cartes via les données cellulaires", "Descargar mapas con datos móviles", "Kartendaten über mobile Daten laden"),
    "Map data for this area (%@) downloads on Wi-Fi.": ("Kaartgegevens voor dit gebied (%@) worden via wifi gedownload.", "Les données cartographiques de cette zone (%@) se téléchargent en Wi-Fi.", "Los datos de mapa de esta zona (%@) se descargan con wifi.", "Kartendaten für dieses Gebiet (%@) werden über WLAN geladen."),
    "Map data larger than %@ downloads only on Wi-Fi, unless this is on. While planning, you can also choose Download Anyway.": (
        "Kaartgegevens groter dan %@ worden alleen via wifi gedownload, tenzij dit aan staat. Tijdens het plannen kun je ook kiezen voor Toch downloaden.",
        "Les données cartographiques de plus de %@ se téléchargent uniquement en Wi-Fi, sauf si cette option est activée. Pendant la planification, vous pouvez aussi choisir Télécharger quand même.",
        "Los datos de mapa de más de %@ solo se descargan con wifi, salvo que esto esté activado. Al planificar también puedes elegir Descargar de todos modos.",
        "Kartendaten über %@ werden nur über WLAN geladen, außer dies ist aktiviert. Beim Planen kannst du auch Trotzdem laden wählen."),
    "Areas of about 70 × 110 km, downloaded when you plan a route there. Swipe left to remove one; it downloads again the next time you plan there.": (
        "Gebieden van ongeveer 70 × 110 km, gedownload als je er een route plant. Veeg naar links om er een te verwijderen; het wordt opnieuw gedownload als je er weer plant.",
        "Zones d'environ 70 × 110 km, téléchargées quand vous y planifiez un parcours. Balayez vers la gauche pour en supprimer une ; elle sera retéléchargée la prochaine fois.",
        "Zonas de unos 70 × 110 km, descargadas cuando planificas una ruta allí. Desliza a la izquierda para eliminar una; se vuelve a descargar la próxima vez que planifiques allí.",
        "Gebiete von etwa 70 × 110 km, geladen, wenn du dort eine Route planst. Nach links wischen zum Entfernen; beim nächsten Planen dort wird es erneut geladen."),
    "Downloaded for the countries you have activities in. They're small and load again automatically, so they can't be removed here.": (
        "Gedownload voor de landen waarin je activiteiten hebt. Ze zijn klein en worden automatisch opnieuw geladen, dus je kunt ze hier niet verwijderen.",
        "Téléchargés pour les pays où vous avez des activités. Ils sont petits et se rechargent automatiquement, ils ne peuvent donc pas être supprimés ici.",
        "Descargados para los países donde tienes actividades. Son pequeños y se cargan de nuevo automáticamente, así que no se pueden eliminar aquí.",
        "Für die Länder geladen, in denen du Aktivitäten hast. Sie sind klein und werden automatisch neu geladen, daher kann man sie hier nicht entfernen."),
    "It downloads again the next time you plan a route.": ("Het wordt opnieuw gedownload als je weer een route plant.", "Elles seront retéléchargées la prochaine fois que vous planifierez un parcours.", "Se vuelve a descargar la próxima vez que planifiques una ruta.", "Sie werden beim nächsten Planen einer Route erneut geladen."),
    "Municipalities and Postcodes": ("Gemeenten en postcodes", "Communes et codes postaux", "Municipios y códigos postales", "Gemeinden und Postleitzahlen"),
    "No boundaries downloaded.": ("Geen grenzen gedownload.", "Aucune limite téléchargée.", "No hay límites descargados.", "Keine Grenzen geladen."),
    "No route planning areas downloaded.": ("Geen routeplanningsgebieden gedownload.", "Aucune zone de planification téléchargée.", "No hay zonas de planificación descargadas.", "Keine Routenplanungsgebiete geladen."),
    "Remove All": ("Alles verwijderen", "Tout supprimer", "Eliminar todo", "Alle entfernen"),
    "Remove All Route Planning Data": ("Alle routeplanningsgegevens verwijderen", "Supprimer toutes les données de planification", "Eliminar todos los datos de planificación", "Alle Routenplanungsdaten entfernen"),
    "Remove all route planning map data?": ("Alle kaartgegevens voor routeplanning verwijderen?", "Supprimer toutes les données cartographiques de planification ?", "¿Eliminar todos los datos de mapa de planificación?", "Alle Kartendaten für die Routenplanung entfernen?"),
    "Route Planning Map Data": ("Kaartgegevens routeplanning", "Données cartographiques de planification", "Datos de mapa para planificar", "Kartendaten für die Routenplanung"),
    "Tracks, tiles and areas read from your .fit files, so they don't have to be read again at every start. Clearing it reads all files again.": (
        "Sporen, tegels en gebieden uit je .fit-bestanden, zodat ze niet bij elke start opnieuw gelezen hoeven te worden. Wissen leest alle bestanden opnieuw.",
        "Traces, tuiles et zones lues dans vos fichiers .fit, pour ne pas les relire à chaque démarrage. Le vider relit tous les fichiers.",
        "Recorridos, teselas y zonas leídos de tus archivos .fit, para no tener que leerlos en cada inicio. Al vaciarla se leen todos los archivos de nuevo.",
        "Tracks, Kacheln und Gebiete aus deinen .fit-Dateien, damit sie nicht bei jedem Start neu gelesen werden. Leeren liest alle Dateien neu ein."),
    # Starting point
    "Start: %@": ("Start: %@", "Départ : %@", "Inicio: %@", "Start: %@"),
    "Start: My Location": ("Start: mijn locatie", "Départ : ma position", "Inicio: mi ubicación", "Start: mein Standort"),
    "My Location": ("Mijn locatie", "Ma position", "Mi ubicación", "Mein Standort"),
    "Starting Point": ("Startpunt", "Point de départ", "Punto de partida", "Startpunkt"),
    "Recent": ("Recent", "Récents", "Recientes", "Zuletzt verwendet"),
    "Search for an address or place": ("Zoek een adres of plaats", "Rechercher une adresse ou un lieu", "Buscar una dirección o lugar", "Adresse oder Ort suchen"),
    "Choose where the route starts": ("Kies waar de route begint", "Choisir où le parcours commence", "Elige dónde empieza la ruta", "Wähle, wo die Route beginnt"),
    # Point to point (1.9, issue #50)
    "Start Here": ("Start hier", "Partir d’ici", "Empezar aquí", "Hier starten"),
    "End Here": ("Eindig hier", "Arriver ici", "Terminar aquí", "Hier enden"),
    "End: %@": ("Einde: %@", "Arrivée : %@", "Final: %@", "Ziel: %@"),
    "End: Back to Start": ("Einde: terug naar start", "Arrivée : retour au départ", "Final: volver al inicio", "Ziel: zurück zum Start"),
    "Choose a round trip or where the route ends": ("Kies een rondrit of waar de route eindigt", "Choisir une boucle ou l’arrivée du parcours", "Elige una ruta circular o dónde termina la ruta", "Wähle eine Rundfahrt oder wo die Route endet"),
    "Back to Start": ("Terug naar start", "Retour au départ", "Volver al inicio", "Zurück zum Start"),
    "End Point": ("Eindpunt", "Point d’arrivée", "Punto final", "Zielpunkt"),
    "A round trip, or choose a place below to ride from the start to there; or long-press the map and choose End Here. You can drag the checkered flag to move it.": ("Een rondrit, of kies hieronder een plek om van de start daarheen te fietsen; of houd de kaart ingedrukt en kies Eindig hier. Je kunt de geblokte vlag verslepen.", "Une boucle, ou choisissez un lieu ci-dessous pour rouler du départ jusque-là ; ou appuyez longuement sur la carte et choisissez Arriver ici. Vous pouvez faire glisser le drapeau à damier.", "Una ruta circular, o elige un lugar abajo para ir del inicio hasta allí; o mantén pulsado el mapa y elige Terminar aquí. Puedes arrastrar la bandera a cuadros.", "Eine Rundfahrt, oder wähle unten einen Ort, um vom Start dorthin zu fahren; oder halte die Karte gedrückt und wähle Hier enden. Du kannst die Zielflagge verschieben."),
    "Tap unvisited tiles, municipalities or postcodes to add them. The route goes from the start to the end; drag the flags to move them.": ("Tik op onbezochte tegels, gemeenten of postcodes om ze toe te voegen. De route gaat van de start naar het einde; versleep de vlaggen om ze te verplaatsen.", "Touchez des tuiles, communes ou codes postaux non visités pour les ajouter. Le parcours va du départ à l’arrivée ; faites glisser les drapeaux pour les déplacer.", "Toca teselas, municipios o códigos postales sin visitar para añadirlos. La ruta va del inicio al final; arrastra las banderas para moverlas.", "Tippe auf unbesuchte Kacheln, Gemeinden oder Postleitzahlen, um sie hinzuzufügen. Die Route führt vom Start zum Ziel; verschiebe die Flaggen, um sie zu verlegen."),
    "Or long-press the map and choose Start Here. You can drag the green flag to move it.": ("Of houd de kaart ingedrukt en kies Start hier. Je kunt de groene vlag verslepen.", "Ou appuyez longuement sur la carte et choisissez Partir d’ici. Vous pouvez faire glisser le drapeau vert.", "O mantén pulsado el mapa y elige Empezar aquí. Puedes arrastrar la bandera verde.", "Oder halte die Karte gedrückt und wähle Hier starten. Du kannst die grüne Flagge verschieben."),
    "This place couldn't be found. Try another search.": ("Deze plaats is niet gevonden. Probeer een andere zoekopdracht.", "Ce lieu est introuvable. Essayez une autre recherche.", "No se encontró este lugar. Prueba otra búsqueda.", "Dieser Ort wurde nicht gefunden. Versuche eine andere Suche."),
    "Main roads": ("Hoofdwegen", "Routes principales", "Carreteras principales", "Hauptstraßen"),
    "Shared by all areas": ("Gedeeld door alle gebieden", "Communes à toutes les zones", "Compartidas por todas las zonas", "Von allen Gebieten genutzt"),
    "Map data is downloaded for the surroundings of each route you plan, and listed here per area of about 70 × 110 km. Swipe left to remove one; it downloads again the next time you plan there.": (
        "Kaartgegevens worden gedownload voor de omgeving van elke route die je plant, en staan hier per gebied van ongeveer 70 × 110 km. Veeg naar links om er een te verwijderen; het wordt opnieuw gedownload als je er weer plant.",
        "Les données cartographiques sont téléchargées pour les environs de chaque parcours planifié, et listées ici par zone d'environ 70 × 110 km. Balayez vers la gauche pour en supprimer une ; elle sera retéléchargée la prochaine fois.",
        "Los datos de mapa se descargan para los alrededores de cada ruta que planificas, y aparecen aquí por zonas de unos 70 × 110 km. Desliza a la izquierda para eliminar una; se vuelve a descargar la próxima vez que planifiques allí.",
        "Kartendaten werden für die Umgebung jeder geplanten Route geladen und hier pro Gebiet von etwa 70 × 110 km aufgeführt. Nach links wischen zum Entfernen; beim nächsten Planen dort wird es erneut geladen."),
    # Activities list
    "No Activities": ("Geen activiteiten", "Aucune activité", "Sin actividades", "Keine Aktivitäten"),
    "Indoor": ("Binnen", "Intérieur", "Interior", "Indoor"),
    "Without date": ("Zonder datum", "Sans date", "Sin fecha", "Ohne Datum"),
    "Add .fit files in Settings, or connect Strava.": ("Voeg .fit-bestanden toe in Instellingen, of koppel Strava.", "Ajoutez des fichiers .fit dans Réglages, ou connectez Strava.", "Añade archivos .fit en Ajustes o conecta Strava.", "Füge in den Einstellungen .fit-Dateien hinzu oder verbinde Strava."),
    # Resilient planning
    "Stop": ("Stop", "Arrêter", "Detener", "Stopp"),
    "Planning stopped. Map data downloaded so far is kept.": ("Plannen gestopt. De gedownloade kaartgegevens blijven bewaard.", "Planification arrêtée. Les données cartographiques déjà téléchargées sont conservées.", "Planificación detenida. Los datos de mapa ya descargados se conservan.", "Planung gestoppt. Bereits geladene Kartendaten bleiben erhalten."),
    "Downloading map data for route planning: %@ of %@…": ("Kaartgegevens voor routeplanning downloaden: %1$@ van %2$@…", "Téléchargement des données cartographiques : %1$@ sur %2$@…", "Descargando datos de mapa para planificar: %1$@ de %2$@…", "Kartendaten für die Routenplanung werden geladen: %1$@ von %2$@…"),
    "There's no internet connection, and map data for this area still has to be downloaded. Try again when you're online.": (
        "Er is geen internetverbinding en de kaartgegevens voor dit gebied moeten nog worden gedownload. Probeer het opnieuw als je online bent.",
        "Il n'y a pas de connexion Internet, et les données cartographiques de cette zone doivent encore être téléchargées. Réessayez une fois en ligne.",
        "No hay conexión a internet y aún hay que descargar los datos de mapa de esta zona. Inténtalo de nuevo cuando estés conectado.",
        "Es gibt keine Internetverbindung, und die Kartendaten für dieses Gebiet müssen noch geladen werden. Versuche es erneut, wenn du online bist."),
    "Downloading the map data timed out. Check your connection and try again; what was downloaded is kept.": (
        "Het downloaden van de kaartgegevens duurde te lang. Controleer je verbinding en probeer het opnieuw; wat al gedownload is, blijft bewaard.",
        "Le téléchargement des données cartographiques a expiré. Vérifiez votre connexion et réessayez ; ce qui a été téléchargé est conservé.",
        "La descarga de los datos de mapa tardó demasiado. Comprueba tu conexión e inténtalo de nuevo; lo ya descargado se conserva.",
        "Das Laden der Kartendaten hat zu lange gedauert. Prüfe deine Verbindung und versuche es erneut; bereits Geladenes bleibt erhalten."),
    "The map data couldn't be downloaded (%@). Try again; what was downloaded is kept.": (
        "De kaartgegevens konden niet worden gedownload (%@). Probeer het opnieuw; wat al gedownload is, blijft bewaard.",
        "Les données cartographiques n'ont pas pu être téléchargées (%@). Réessayez ; ce qui a été téléchargé est conservé.",
        "No se pudieron descargar los datos de mapa (%@). Inténtalo de nuevo; lo ya descargado se conserva.",
        "Die Kartendaten konnten nicht geladen werden (%@). Versuche es erneut; bereits Geladenes bleibt erhalten."),
    "Map data for this area isn't available yet. Please try again later.": (
        "Kaartgegevens voor dit gebied zijn nog niet beschikbaar. Probeer het later opnieuw.",
        "Les données cartographiques de cette zone ne sont pas encore disponibles. Réessayez plus tard.",
        "Los datos de mapa de esta zona aún no están disponibles. Inténtalo más tarde.",
        "Kartendaten für dieses Gebiet sind noch nicht verfügbar. Versuche es später erneut."),
    "The map data server had a problem (%lld). Try again later; what was downloaded is kept.": (
        "De server met kaartgegevens had een probleem (%lld). Probeer het later opnieuw; wat al gedownload is, blijft bewaard.",
        "Le serveur de données cartographiques a rencontré un problème (%lld). Réessayez plus tard ; ce qui a été téléchargé est conservé.",
        "El servidor de datos de mapa tuvo un problema (%lld). Inténtalo más tarde; lo ya descargado se conserva.",
        "Der Kartendaten-Server hatte ein Problem (%lld). Versuche es später erneut; bereits Geladenes bleibt erhalten."),
    "Map data arrived damaged several times. Try again; what was downloaded is kept.": (
        "Kaartgegevens kwamen meerdere keren beschadigd aan. Probeer het opnieuw; wat al gedownload is, blijft bewaard.",
        "Les données cartographiques sont arrivées endommagées plusieurs fois. Réessayez ; ce qui a été téléchargé est conservé.",
        "Los datos de mapa llegaron dañados varias veces. Inténtalo de nuevo; lo ya descargado se conserva.",
        "Kartendaten kamen mehrmals beschädigt an. Versuche es erneut; bereits Geladenes bleibt erhalten."),
    "These items are too far apart for one round trip (about %lld km as the crow flies; up to %lld km is possible). Select fewer or closer items.": (
        "Deze onderdelen liggen te ver uit elkaar voor één rondrit (ongeveer %1$lld km hemelsbreed; tot %2$lld km is mogelijk). Kies minder of dichterbij gelegen onderdelen.",
        "Ces éléments sont trop éloignés pour une seule boucle (environ %1$lld km à vol d'oiseau ; jusqu'à %2$lld km possible). Choisissez-en moins ou des plus proches.",
        "Estos elementos están demasiado separados para una sola ruta circular (unos %1$lld km en línea recta; se puede hasta %2$lld km). Elige menos o más cercanos.",
        "Diese Elemente liegen für eine Rundtour zu weit auseinander (etwa %1$lld km Luftlinie; bis %2$lld km ist möglich). Wähle weniger oder nähere Elemente."),
    "These items are too far apart for one round trip. Select fewer or closer items.": (
        "Deze onderdelen liggen te ver uit elkaar voor één rondrit. Kies minder of dichterbij gelegen onderdelen.",
        "Ces éléments sont trop éloignés pour une seule boucle. Choisissez-en moins ou des plus proches.",
        "Estos elementos están demasiado separados para una sola ruta circular. Elige menos o más cercanos.",
        "Diese Elemente liegen für eine Rundtour zu weit auseinander. Wähle weniger oder nähere Elemente."),
    "No cycling route was found between some of the stops, for example across water without a bridge or ferry. Try other items or another starting point.": (
        "Tussen sommige stops is geen fietsroute gevonden, bijvoorbeeld over water zonder brug of pont. Probeer andere onderdelen of een ander startpunt.",
        "Aucun itinéraire à vélo n'a été trouvé entre certains arrêts, par exemple au-dessus de l'eau sans pont ni bac. Essayez d'autres éléments ou un autre point de départ.",
        "No se encontró una ruta en bici entre algunas paradas, por ejemplo sobre agua sin puente ni ferry. Prueba otros elementos u otro punto de partida.",
        "Zwischen einigen Stopps wurde keine Radroute gefunden, zum Beispiel über Wasser ohne Brücke oder Fähre. Versuche andere Elemente oder einen anderen Startpunkt."),
    "The starting point or a selected item isn't near a road or path that can be cycled. Choose another one.": (
        "Het startpunt of een gekozen onderdeel ligt niet bij een weg of pad waarover je kunt fietsen. Kies een ander.",
        "Le point de départ ou un élément choisi n'est pas près d'une route ou d'un chemin cyclable. Choisissez-en un autre.",
        "El punto de partida o un elemento elegido no está cerca de una carretera o camino ciclable. Elige otro.",
        "Der Startpunkt oder ein gewähltes Element liegt nicht an einer befahrbaren Straße oder einem Weg. Wähle ein anderes."),
    # App storage and iCloud sync
    "Activity files": ("Activiteitbestanden", "Fichiers d'activité", "Archivos de actividad", "Aktivitätsdateien"),
    "Checking your activities…": ("Je activiteiten controleren…", "Vérification de vos activités…", "Comprobando tus actividades…", "Deine Aktivitäten werden geprüft…"),
    "Could not save the activity: %@": ("De activiteit kon niet worden bewaard: %@", "Impossible d'enregistrer l'activité : %@", "No se pudo guardar la actividad: %@", "Die Aktivität konnte nicht gespeichert werden: %@"),
    "Delete": ("Verwijder", "Supprimer", "Eliminar", "Löschen"),
    "Delete Activity": ("Verwijder activiteit", "Supprimer l'activité", "Eliminar actividad", "Aktivität löschen"),
    "Delete “%@”?": ("“%@” verwijderen?", "Supprimer « %@ » ?", "¿Eliminar “%@”?", "„%@“ löschen?"),
    "Import .fit files to see where you have been.": ("Importeer .fit-bestanden om te zien waar je bent geweest.", "Importez des fichiers .fit pour voir où vous êtes allé.", "Importa archivos .fit para ver dónde has estado.", "Importiere .fit-Dateien, um zu sehen, wo du warst."),
    "Import .fit files, or connect Strava, to see where you have been.": ("Importeer .fit-bestanden of koppel Strava om te zien waar je bent geweest.", "Importez des fichiers .fit ou connectez Strava pour voir où vous êtes allé.", "Importa archivos .fit o conecta Strava para ver dónde has estado.", "Importiere .fit-Dateien oder verbinde Strava, um zu sehen, wo du warst."),
    "Import your .fit files, for example exports from HealthFit, Garmin or Wahoo: separate files or a whole folder. Tileroam keeps its own copy, and with iCloud your other devices have them too.": (
        "Importeer je .fit-bestanden, bijvoorbeeld exports van HealthFit, Garmin of Wahoo: losse bestanden of een hele map. Tileroam bewaart een eigen kopie, en met iCloud hebben je andere apparaten ze ook.",
        "Importez vos fichiers .fit, par exemple des exports de HealthFit, Garmin ou Wahoo : des fichiers séparés ou un dossier entier. Tileroam garde sa propre copie, et avec iCloud vos autres appareils les ont aussi.",
        "Importa tus archivos .fit, por ejemplo exportaciones de HealthFit, Garmin o Wahoo: archivos sueltos o una carpeta entera. Tileroam guarda su propia copia y, con iCloud, tus otros dispositivos también los tienen.",
        "Importiere deine .fit-Dateien, zum Beispiel Exporte aus HealthFit, Garmin oder Wahoo: einzelne Dateien oder einen ganzen Ordner. Tileroam behält eine eigene Kopie, und mit iCloud haben deine anderen Geräte sie auch."),
    "Imported %lld .fit files.": ("%lld .fit-bestanden geïmporteerd.", "%lld fichiers .fit importés.", "%lld archivos .fit importados.", "%lld .fit-Dateien importiert."),
    "It's deleted from Tileroam on this device and from iCloud, so your other devices remove it too. It stays on Strava and wherever you imported it from.": (
        "Hij wordt uit Tileroam op dit apparaat en uit iCloud verwijderd, zodat je andere apparaten hem ook verwijderen. Hij blijft op Strava en waar je hem vandaan hebt geïmporteerd.",
        "Elle est supprimée de Tileroam sur cet appareil et d'iCloud, donc vos autres appareils la suppriment aussi. Elle reste sur Strava et là d'où vous l'avez importée.",
        "Se elimina de Tileroam en este dispositivo y de iCloud, así que tus otros dispositivos también la eliminan. Sigue en Strava y donde la importaste.",
        "Sie wird aus Tileroam auf diesem Gerät und aus iCloud gelöscht, sodass deine anderen Geräte sie auch entfernen. Sie bleibt auf Strava und dort, woher du sie importiert hast."),
    "Optionally connect Strava to download your full history with GPS. Activities are saved as .fit files in Tileroam and, with iCloud, on your other devices.": (
        "Koppel desgewenst Strava om je volledige geschiedenis met gps te downloaden. Activiteiten worden als .fit-bestanden in Tileroam bewaard en, met iCloud, op je andere apparaten.",
        "Connectez éventuellement Strava pour télécharger tout votre historique avec GPS. Les activités sont enregistrées en fichiers .fit dans Tileroam et, avec iCloud, sur vos autres appareils.",
        "Si quieres, conecta Strava para descargar todo tu historial con GPS. Las actividades se guardan como archivos .fit en Tileroam y, con iCloud, en tus otros dispositivos.",
        "Verbinde optional Strava, um deinen ganzen Verlauf mit GPS zu laden. Aktivitäten werden als .fit-Dateien in Tileroam gespeichert und, mit iCloud, auf deinen anderen Geräten."),
    "Save Route": ("Bewaar route", "Enregistrer le parcours", "Guardar ruta", "Route speichern"),
    "Saved to %@ › Routes › %@": ("Bewaard in %1$@ › Routes › %2$@", "Enregistré dans %1$@ › Routes › %2$@", "Guardado en %1$@ › Routes › %2$@", "Gespeichert in %1$@ › Routes › %2$@"),
    "Strava activities are saved as .fit files in Tileroam's activities. Detailed GPS downloads within Strava's rate limit (about 100 activities per 15 minutes, 1000 per day) and continues automatically.": (
        "Strava-activiteiten worden als .fit-bestanden bij de activiteiten van Tileroam bewaard. Gedetailleerde gps wordt gedownload binnen de limiet van Strava (ongeveer 100 activiteiten per 15 minuten, 1000 per dag) en gaat automatisch verder.",
        "Les activités Strava sont enregistrées en fichiers .fit avec les activités de Tileroam. Le GPS détaillé se télécharge dans la limite de Strava (environ 100 activités par 15 minutes, 1000 par jour) et continue automatiquement.",
        "Las actividades de Strava se guardan como archivos .fit con las actividades de Tileroam. El GPS detallado se descarga dentro del límite de Strava (unas 100 actividades cada 15 minutos, 1000 al día) y continúa automáticamente.",
        "Strava-Aktivitäten werden als .fit-Dateien bei den Aktivitäten von Tileroam gespeichert. Detailliertes GPS wird innerhalb des Strava-Limits geladen (etwa 100 Aktivitäten pro 15 Minuten, 1000 pro Tag) und läuft automatisch weiter."),
    "Switch between tiles, routes, municipalities and postcodes at the top of the map. Settings has your statistics, iCloud sync and imports.": (
        "Wissel bovenaan de kaart tussen tegels, routes, gemeenten en postcodes. In Instellingen vind je je statistieken, iCloud-synchronisatie en importeren.",
        "Passez des tuiles aux parcours, communes et codes postaux en haut de la carte. Les Réglages contiennent vos statistiques, la synchronisation iCloud et l'import.",
        "Cambia entre teselas, rutas, municipios y códigos postales en la parte superior del mapa. En Ajustes están tus estadísticas, la sincronización con iCloud y la importación.",
        "Wechsle oben auf der Karte zwischen Kacheln, Routen, Gemeinden und Postleitzahlen. In den Einstellungen findest du Statistiken, iCloud-Synchronisierung und Import."),
    "Sync with iCloud": ("Synchroniseer met iCloud", "Synchroniser avec iCloud", "Sincronizar con iCloud", "Mit iCloud synchronisieren"),
    "Tileroam keeps your activities and planned routes on this device (%@ › Activities and › Routes). Sign in to iCloud with iCloud Drive on to share them with your other devices. Imported files are copied once: the folder they came from isn't watched.": (
        "Tileroam bewaart je activiteiten en geplande routes op dit apparaat (%@ › Activities en › Routes). Log in bij iCloud met iCloud Drive aan om ze met je andere apparaten te delen. Geïmporteerde bestanden worden één keer gekopieerd: de map waar ze vandaan komen wordt niet gevolgd.",
        "Tileroam garde vos activités et parcours planifiés sur cet appareil (%@ › Activities et › Routes). Connectez-vous à iCloud avec iCloud Drive activé pour les partager avec vos autres appareils. Les fichiers importés sont copiés une fois : leur dossier d'origine n'est pas surveillé.",
        "Tileroam guarda tus actividades y rutas planificadas en este dispositivo (%@ › Activities y › Routes). Inicia sesión en iCloud con iCloud Drive activado para compartirlas con tus otros dispositivos. Los archivos importados se copian una vez: su carpeta de origen no se vigila.",
        "Tileroam speichert deine Aktivitäten und geplanten Routen auf diesem Gerät (%@ › Activities und › Routes). Melde dich mit aktiviertem iCloud Drive bei iCloud an, um sie mit deinen anderen Geräten zu teilen. Importierte Dateien werden einmal kopiert: Ihr Ursprungsordner wird nicht überwacht."),
    "Tileroam keeps your activities and planned routes on this device (%@ › Activities and › Routes). With iCloud sync, they're also in %@, without duplicates, so your other devices have them. Turning it off keeps both copies. Imported files are copied once: the folder they came from isn't watched.": (
        "Tileroam bewaart je activiteiten en geplande routes op dit apparaat (%1$@ › Activities en › Routes). Met iCloud-synchronisatie staan ze ook in %2$@, zonder dubbelen, zodat je andere apparaten ze hebben. Uitzetten houdt beide kopieën. Geïmporteerde bestanden worden één keer gekopieerd: de map waar ze vandaan komen wordt niet gevolgd.",
        "Tileroam garde vos activités et parcours planifiés sur cet appareil (%1$@ › Activities et › Routes). Avec la synchronisation iCloud, ils sont aussi dans %2$@, sans doublons, pour vos autres appareils. La désactiver garde les deux copies. Les fichiers importés sont copiés une fois : leur dossier d'origine n'est pas surveillé.",
        "Tileroam guarda tus actividades y rutas planificadas en este dispositivo (%1$@ › Activities y › Routes). Con la sincronización de iCloud también están en %2$@, sin duplicados, para tus otros dispositivos. Desactivarla conserva ambas copias. Los archivos importados se copian una vez: su carpeta de origen no se vigila.",
        "Tileroam speichert deine Aktivitäten und geplanten Routen auf diesem Gerät (%1$@ › Activities und › Routes). Mit iCloud-Synchronisierung sind sie auch in %2$@, ohne Duplikate, für deine anderen Geräte. Ausschalten behält beide Kopien. Importierte Dateien werden einmal kopiert: Ihr Ursprungsordner wird nicht überwacht."),
    "You can import more later in Settings.": ("Je kunt later meer importeren in Instellingen.", "Vous pourrez en importer d'autres plus tard dans Réglages.", "Puedes importar más después en Ajustes.", "Du kannst später in den Einstellungen mehr importieren."),
    "Your activities come from iCloud, from your other devices": ("Je activiteiten komen uit iCloud, van je andere apparaten", "Vos activités viennent d'iCloud, de vos autres appareils", "Tus actividades vienen de iCloud, de tus otros dispositivos", "Deine Aktivitäten kommen aus iCloud, von deinen anderen Geräten"),
    # Climbs
    "%lld climbs": ("%lld klimmen", "%lld montées", "%lld subidas", "%lld Anstiege"),
    "A climb needs more route points than other items. Remove a few items to add it.": ("Een klim heeft meer routepunten nodig dan andere onderdelen. Haal er een paar weg om hem toe te voegen.", "Une montée demande plus de points de passage que les autres éléments. Retirez-en quelques-uns pour l’ajouter.", "Una subida necesita más puntos de ruta que otros elementos. Quita algunos para añadirla.", "Ein Anstieg braucht mehr Routenpunkte als andere Elemente. Entferne ein paar, um ihn hinzuzufügen."),
    "%lld climbs climbed · %lld on the map": ("%1$lld klimmen beklommen · %2$lld op de kaart", "%1$lld montées gravies · %2$lld sur la carte", "%1$lld subidas hechas · %2$lld en el mapa", "%1$lld Anstiege gefahren · %2$lld auf der Karte"),
    "All Climbs": ("Alle klimmen", "Toutes les montées", "Todas las subidas", "Alle Anstiege"),
    "Cat 1": ("Cat. 1", "Cat. 1", "Cat. 1", "Kat. 1"),
    "Cat 2": ("Cat. 2", "Cat. 2", "Cat. 2", "Kat. 2"),
    "Cat 3": ("Cat. 3", "Cat. 3", "Cat. 3", "Kat. 3"),
    "Cat 4": ("Cat. 4", "Cat. 4", "Cat. 4", "Kat. 4"),
    "Climb": ("Klim", "Montée", "Subida", "Anstieg"),
    "Climb near %@": ("Klim bij %@", "Montée près de %@", "Subida cerca de %@", "Anstieg bei %@"),
    "Climbed %lld times, last on %@": ("%1$lld keer beklommen, laatst op %2$@", "Gravie %1$lld fois, la dernière le %2$@", "Subida %1$lld veces, la última el %2$@", "%1$lld-mal gefahren, zuletzt am %2$@"),
    "Climbed (%lld)": ("Beklommen (%lld)", "Gravies (%lld)", "Hechas (%lld)", "Gefahren (%lld)"),
    "Climbs": ("Klimmen", "Montées", "Subidas", "Anstiege"),
    "The download took too long.": ("Het downloaden duurde te lang.", "Le téléchargement a pris trop de temps.", "La descarga tardó demasiado.", "Der Download hat zu lange gedauert."),
    # Boscafé Challenge (1.8)
    "Boscafé Challenge": ("Boscafé-uitdaging", "Défi des cafés en forêt", "Desafío de cafés del bosque", "Waldcafé-Challenge"),
    "tab.boscafes": ("Boscafés", "Cafés forêt", "Cafés bosque", "Waldcafés"),
    "%lld of %lld boscafés visited": ("%1$lld van %2$lld boscafés bezocht", "%1$lld cafés en forêt visités sur %2$lld", "%1$lld de %2$lld cafés del bosque visitados", "%1$lld von %2$lld Waldcafés besucht"),
    "%lld boscafés": ("%lld boscafés", "%lld cafés en forêt", "%lld cafés del bosque", "%lld Waldcafés"),
    "Boscafés visited": ("Boscafés bezocht", "Cafés en forêt visités", "Cafés del bosque visitados", "Besuchte Waldcafés"),
    "Not visited yet: ride or walk within 200 m of the boscafé": ("Nog niet bezocht: fiets of wandel binnen 200 m van het boscafé", "Pas encore visité : passez à moins de 200 m du café", "Aún no visitado: pasa a menos de 200 m del café", "Noch nicht besucht: fahre oder gehe näher als 200 m am Waldcafé vorbei"),
    "The Boscafé Challenge: visit the cafés in the woods": ("De Boscafé-uitdaging: bezoek de cafés in het bos", "Le défi des cafés en forêt : visitez les cafés dans les bois", "El desafío de cafés del bosque: visita los cafés del bosque", "Die Waldcafé-Challenge: besuche die Cafés im Wald"),
    "Tap the route button, select unvisited tiles, municipalities, postcodes, climbs, Trappist breweries or boscafés, and Tileroam plans the shortest cycling round trip from where you are. Export it as GPX for your bike computer.": ("Tik op de routeknop, kies onbezochte tegels, gemeenten, postcodes, klimmen, trappistenbrouwerijen of boscafés, en Tileroam plant de kortste fietsrondrit vanaf waar je bent. Exporteer hem als GPX voor je fietscomputer.", "Touchez le bouton d’itinéraire, choisissez des tuiles, communes, codes postaux, montées, brasseries trappistes ou cafés en forêt non visités, et Tileroam planifie la boucle à vélo la plus courte depuis votre position. Exportez-la en GPX pour votre compteur.", "Toca el botón de ruta, elige teselas, municipios, códigos postales, subidas, cervecerías trapenses o cafés del bosque sin visitar, y Tileroam planifica la ruta circular en bici más corta desde donde estás. Expórtala como GPX para tu ciclocomputador.", "Tippe auf die Routentaste, wähle unbesuchte Kacheln, Gemeinden, Postleitzahlen, Anstiege, Trappistenbrauereien oder Waldcafés, und Tileroam plant die kürzeste Radrunde von deinem Standort. Exportiere sie als GPX für deinen Radcomputer."),
    "Mountain bike routes": ("Mountainbikeroutes", "Parcours VTT", "Rutas de BTT", "Mountainbike-Routen"),
    "tab.mtb": ("MTB", "VTT", "BTT", "MTB"),
    "Local route": ("Lokale route", "Parcours local", "Ruta local", "Lokale Route"),
    "Regional route": ("Regionale route", "Parcours régional", "Ruta regional", "Regionale Route"),
    "National route": ("Nationale route", "Parcours national", "Ruta nacional", "Nationale Route"),
    "International route": ("Internationale route", "Parcours international", "Ruta internacional", "Internationale Route"),
    "MTB route": ("Mountainbikeroute", "Parcours VTT", "Ruta de BTT", "MTB-Route"),
    "%lld of %lld mountain bike routes ridden": ("%1$lld van %2$lld mountainbikeroutes gereden", "%1$lld parcours VTT faits sur %2$lld", "%1$lld de %2$lld rutas de BTT hechas", "%1$lld von %2$lld Mountainbike-Routen gefahren"),
    "Ridden": ("Gereden", "Fait", "Hecha", "Gefahren"),
    "%lld%% of the route ridden": ("%lld%% van de route gereden", "%lld %% du parcours fait", "%lld %% de la ruta hecha", "%lld %% der Route gefahren"),
    "Not ridden yet": ("Nog niet gereden", "Pas encore fait", "Aún no hecha", "Noch nicht gefahren"),
    "Website": ("Website", "Site web", "Sitio web", "Website"),
    "Mountain bike routes ridden": ("Mountainbikeroutes gereden", "Parcours VTT faits", "Rutas de BTT hechas", "Gefahrene Mountainbike-Routen"),
    "Mountain bike routes: the signposted MTB routes of OpenStreetMap": ("Mountainbikeroutes: de bewegwijzerde MTB-routes uit OpenStreetMap", "Parcours VTT : les parcours VTT balisés d’OpenStreetMap", "Rutas de BTT: las rutas de BTT señalizadas de OpenStreetMap", "Mountainbike-Routen: die ausgeschilderten MTB-Routen aus OpenStreetMap"),
    "Checking iCloud…": ("iCloud controleren…", "Vérification d’iCloud…", "Comprobando iCloud…", "iCloud wird geprüft…"),
    "Reading your activities…": ("Je activiteiten lezen…", "Lecture de vos activités…", "Leyendo tus actividades…", "Deine Aktivitäten werden gelesen…"),
    "Saving to iCloud…": ("Opslaan in iCloud…", "Enregistrement dans iCloud…", "Guardando en iCloud…", "In iCloud sichern…"),
    "Klompenpaden": ("Klompenpaden", "Klompenpaden", "Klompenpaden", "Klompenpaden"),
    "tab.klompenpaden": ("Klompenpaden", "Klompenpaden", "Klompenpaden", "Klompenpaden"),
    "%lld of %lld Klompenpaden walked": ("%1$lld van %2$lld klompenpaden gelopen", "%1$lld Klompenpaden parcourus sur %2$lld", "%1$lld de %2$lld Klompenpaden recorridos", "%1$lld von %2$lld Klompenpaden gelaufen"),
    "From %@ · %@": ("Vanuit %1$@ · %2$@", "Depuis %1$@ · %2$@", "Desde %1$@ · %2$@", "Ab %1$@ · %2$@"),
    "Walked": ("Gelopen", "Parcouru", "Recorrido", "Gelaufen"),
    "%lld%% of the route walked": ("%lld%% van de route gelopen", "%lld %% du parcours effectué", "%lld %% de la ruta recorrida", "%lld %% der Route gelaufen"),
    "Not walked yet": ("Nog niet gelopen", "Pas encore parcouru", "Aún no recorrido", "Noch nicht gelaufen"),
    "Klompenpaden walked": ("Klompenpaden gelopen", "Klompenpaden parcourus", "Klompenpaden recorridos", "Gelaufene Klompenpaden"),
    "Klompenpaden: walk the 167 country paths of Gelderland and Utrecht": ("Klompenpaden: loop de 167 klompenpaden van Gelderland en Utrecht", "Klompenpaden : parcourez les 167 sentiers ruraux de Gueldre et d’Utrecht", "Klompenpaden: recorre los 167 senderos rurales de Güeldres y Utrecht", "Klompenpaden: lauf die 167 Landwege in Gelderland und Utrecht"),
    "See everywhere you have been, and take on challenges with your rides, runs and walks.": ("Zie waar je overal bent geweest en ga uitdagingen aan met je ritten, runs en wandelingen.", "Voyez partout où vous êtes passé et relevez des défis avec vos sorties à vélo, courses et marches.", "Mira todos los sitios por donde has pasado y acepta desafíos con tus salidas en bici, carreras y paseos.", "Sieh, wo du überall warst, und stell dich Herausforderungen mit deinen Fahrten, Läufen und Wanderungen."),
    "Map tiles, with your max square and cluster": ("Kaarttegels, met je grootste vierkant en cluster", "Tuiles de carte, avec votre plus grand carré et votre cluster", "Teselas del mapa, con tu mayor cuadrado y tu clúster", "Kartenkacheln, mit deinem größten Quadrat und Cluster"),
    "Challenges: municipalities and postcodes in the Netherlands, Belgium, Luxembourg, Germany, France, Switzerland and Austria": ("Uitdagingen: gemeenten en postcodes in Nederland, België, Luxemburg, Duitsland, Frankrijk, Zwitserland en Oostenrijk", "Défis : communes et codes postaux aux Pays-Bas, en Belgique, au Luxembourg, en Allemagne, en France, en Suisse et en Autriche", "Desafíos: municipios y códigos postales en los Países Bajos, Bélgica, Luxemburgo, Alemania, Francia, Suiza y Austria", "Herausforderungen: Gemeinden und Postleitzahlen in den Niederlanden, Belgien, Luxemburg, Deutschland, Frankreich, der Schweiz und Österreich"),
    "Climbs from short steep hills to HC, and the ones you climbed": ("Klimmen van korte steile heuvels tot HC, en welke je beklommen hebt", "Des montées, des courtes côtes raides au HC, et celles que vous avez gravies", "Subidas, de repechos cortos a HC, y las que has hecho", "Anstiege von kurzen steilen Rampen bis HC, und welche du gefahren bist"),
    "The Trappist Challenge: ride past the Trappist breweries": ("De Trappistenuitdaging: fiets langs de trappistenbrouwerijen", "Le défi trappiste : passez devant les brasseries trappistes", "El desafío trapense: pasa por las cervecerías trapenses", "Die Trappisten-Challenge: fahre an den Trappistenbrauereien vorbei"),
    "18 badges, from 100! and Everester to Festive 500 and Globetrotter": ("18 badges, van 100! en Everester tot Festive 500 en Wereldreiziger", "18 badges, de 100 ! et Everester à Festive 500 et Globe-trotter", "18 insignias, de ¡100! y Everester a Festive 500 y Trotamundos", "18 Abzeichen, von 100! und Everester bis Festive 500 und Weltenbummler"),
    "Tap the route button, select unvisited tiles, municipalities, postcodes, climbs or Trappist breweries, and Tileroam plans the shortest cycling round trip from where you are. Export it as GPX for your bike computer.": ("Tik op de routeknop, kies onbezochte tegels, gemeenten, postcodes, klimmen of trappistenbrouwerijen, en Tileroam plant de kortste fietsrondrit vanaf waar je bent. Exporteer hem als GPX voor je fietscomputer.", "Touchez le bouton d’itinéraire, choisissez des tuiles, communes, codes postaux, montées ou brasseries trappistes non visités, et Tileroam planifie la boucle à vélo la plus courte depuis votre position. Exportez-la en GPX pour votre compteur.", "Toca el botón de ruta, elige teselas, municipios, códigos postales, subidas o cervecerías trapenses sin visitar, y Tileroam planifica la ruta circular en bici más corta desde donde estás. Expórtala como GPX para tu ciclocomputador.", "Tippe auf die Routentaste, wähle unbesuchte Kacheln, Gemeinden, Postleitzahlen, Anstiege oder Trappistenbrauereien, und Tileroam plant die kürzeste Radrunde von deinem Standort. Exportiere sie als GPX für deinen Radcomputer."),
    "Tiles are at the top of the map; add the challenges you like with the +. The chart button has your statistics and badges, Settings your iCloud sync and imports.": ("Tegels staan boven aan de kaart; voeg de uitdagingen die je wilt toe met de +. De grafiekknop heeft je statistieken en badges, Instellingen je iCloud-synchronisatie en imports.", "Les tuiles sont en haut de la carte ; ajoutez les défis de votre choix avec le +. Le bouton graphique contient vos statistiques et badges, les Réglages la synchronisation iCloud et les imports.", "Las teselas están arriba en el mapa; añade los desafíos que quieras con el +. El botón de gráfico tiene tus estadísticas e insignias, y Ajustes la sincronización con iCloud y las importaciones.", "Kacheln stehen oben auf der Karte; füge mit dem + die Herausforderungen hinzu, die du willst. Die Diagrammtaste hat deine Statistiken und Abzeichen, die Einstellungen iCloud-Sync und Importe."),
    "Could Not Read": ("Kon niet lezen", "Illisibles", "No se pudieron leer", "Nicht lesbar"),
    "%lld activity files on this device, and with iCloud sync also in iCloud Drive › Tileroam. Imported files are copied once.": ("%lld activiteitbestanden op dit apparaat, en met iCloud-synchronisatie ook in iCloud Drive › Tileroam. Geïmporteerde bestanden worden één keer gekopieerd.", "%lld fichiers d’activité sur cet appareil, et avec la synchronisation iCloud aussi dans iCloud Drive › Tileroam. Les fichiers importés sont copiés une fois.", "%lld archivos de actividad en este dispositivo y, con la sincronización de iCloud, también en iCloud Drive › Tileroam. Los archivos importados se copian una vez.", "%lld Aktivitätsdateien auf diesem Gerät, mit iCloud-Sync auch in iCloud Drive › Tileroam. Importierte Dateien werden einmal kopiert."),
    "%lld activity files on this device. Sign in to iCloud with iCloud Drive on to share them with your other devices.": ("%lld activiteitbestanden op dit apparaat. Log in bij iCloud met iCloud Drive aan om ze met je andere apparaten te delen.", "%lld fichiers d’activité sur cet appareil. Connectez-vous à iCloud avec iCloud Drive activé pour les partager avec vos autres appareils.", "%lld archivos de actividad en este dispositivo. Inicia sesión en iCloud con iCloud Drive activado para compartirlos con tus otros dispositivos.", "%lld Aktivitätsdateien auf diesem Gerät. Melde dich bei iCloud mit aktiviertem iCloud Drive an, um sie mit deinen anderen Geräten zu teilen."),
    "Tiles are always on the map. Challenges you hide still count.": ("Tegels staan altijd op de kaart. Uitdagingen die je verbergt tellen gewoon mee.", "Les tuiles sont toujours sur la carte. Les défis masqués comptent quand même.", "Las teselas están siempre en el mapa. Los desafíos que ocultas siguen contando.", "Kacheln sind immer auf der Karte. Ausgeblendete Herausforderungen zählen trotzdem."),
    "Version": ("Versie", "Version", "Versión", "Version"),
    "%lld Trappist breweries": ("%lld trappistenbrouwerijen", "%lld brasseries trappistes", "%lld cervecerías trapenses", "%lld Trappistenbrauereien"),
    "Ride Zwift's Uber Pretzel: at least 128 km and 2,300 m of climbing": ("Rijd Zwifts Uber Pretzel: minstens 128 km en 2.300 hoogtemeters", "Roulez l’Uber Pretzel de Zwift : au moins 128 km et 2 300 m de dénivelé", "Rueda el Uber Pretzel de Zwift: al menos 128 km y 2.300 m de desnivel", "Fahre Zwifts Uber Pretzel: mindestens 128 km und 2.300 Höhenmeter"),
    "%lld of 50 countries so far": ("Tot nu toe %lld van 50 landen", "%lld pays sur 50 jusqu’ici", "%lld de 50 países por ahora", "Bisher %lld von 50 Ländern"),
    "Badges": ("Badges", "Badges", "Insignias", "Abzeichen"),
    "%lld of %lld": ("%1$lld van %2$lld", "%1$lld sur %2$lld", "%1$lld de %2$lld", "%1$lld von %2$lld"),
    "Badges in colour are yours; tap one to see what it takes. Indoor and virtual activities count too.": ("Badges in kleur heb je verdiend; tik erop om te zien wat ervoor nodig is. Indoor- en virtuele activiteiten tellen ook mee.", "Les badges en couleur sont à vous ; touchez-en un pour voir ce qu’il faut. Les activités en salle et virtuelles comptent aussi.", "Las insignias en color son tuyas; toca una para ver qué hace falta. Las actividades en interior y virtuales también cuentan.", "Farbige Abzeichen hast du verdient; tippe auf eines, um zu sehen, was es braucht. Indoor- und virtuelle Aktivitäten zählen auch."),
    "Not earned yet": ("Nog niet verdiend", "Pas encore obtenu", "Aún no conseguida", "Noch nicht verdient"),
    "Earned %lld times": ("%lld keer verdiend", "Obtenu %lld fois", "Conseguida %lld veces", "%lld-mal verdient"),
    "Closes this category": ("Sluit deze categorie", "Ferme cette catégorie", "Cierra esta categoría", "Schließt diese Kategorie"),
    "Opens this category": ("Opent deze categorie", "Ouvre cette catégorie", "Abre esta categoría", "Öffnet diese Kategorie"),
    "Snowboarding": ("Snowboarden", "Snowboard", "Snowboard", "Snowboarden"),
    "Cross-country skiing": ("Langlaufen", "Ski de fond", "Esquí de fondo", "Skilanglauf"),
    "100!": ("100!", "100 !", "¡100!", "100!"),
    "Century": ("Century", "Century", "Century", "Century"),
    "Hollander": ("Hollander", "Hollander", "Hollander", "Hollander"),
    "Everester": ("Everester", "Everester", "Everester", "Everester"),
    "Pretzel": ("Pretzel", "Bretzel", "Pretzel", "Brezel"),
    "Nosleep": ("Nosleep", "Nosleep", "Nosleep", "Nosleep"),
    "Every day I'm hustling": ("Every day I'm hustling", "Every day I'm hustling", "Every day I'm hustling", "Every day I'm hustling"),
    "Working 9 to 5": ("Working 9 to 5", "Working 9 to 5", "Working 9 to 5", "Working 9 to 5"),
    "Triple jump": ("Hink-stap-sprong", "Triple saut", "Triple salto", "Dreisprung"),
    "Triathlete": ("Triatleet", "Triathlète", "Triatleta", "Triathlet"),
    "Eddy the Eagle": ("Eddy the Eagle", "Eddy the Eagle", "Eddy the Eagle", "Eddy the Eagle"),
    "Marathon": ("Marathon", "Marathon", "Maratón", "Marathon"),
    "Half Marathon": ("Halve marathon", "Semi-marathon", "Media maratón", "Halbmarathon"),
    "Silent night": ("Stille nacht", "Douce nuit", "Noche de paz", "Stille Nacht"),
    "Giant leap": ("Reuzensprong", "Pas de géant", "Gran salto", "Riesensprung"),
    "Festive 500": ("Festive 500", "Festive 500", "Festive 500", "Festive 500"),
    "Globetrotter": ("Wereldreiziger", "Globe-trotter", "Trotamundos", "Weltenbummler"),
    "Taylor": ("Taylor", "Taylor", "Taylor", "Taylor"),
    "Cycle 100 km in one activity": ("Fiets 100 km in één activiteit", "Roulez 100 km en une activité", "Pedalea 100 km en una actividad", "Fahre 100 km in einer Aktivität"),
    "Cycle 100 miles in one activity": ("Fiets 100 mijl in één activiteit", "Roulez 100 miles en une activité", "Pedalea 100 millas en una actividad", "Fahre 100 Meilen in einer Aktivität"),
    "Cycle 100 km with less than 100 m of elevation": ("Fiets 100 km met minder dan 100 hoogtemeters", "Roulez 100 km avec moins de 100 m de dénivelé", "Pedalea 100 km con menos de 100 m de desnivel", "Fahre 100 km mit weniger als 100 Höhenmetern"),
    "Cycle more than 8,848 m of elevation within 24 hours": ("Fiets meer dan 8.848 hoogtemeters binnen 24 uur", "Grimpez plus de 8 848 m de dénivelé à vélo en 24 heures", "Sube más de 8.848 m de desnivel en bici en 24 horas", "Fahre mehr als 8.848 Höhenmeter innerhalb von 24 Stunden"),
    "Complete the indoor activity Uber Pretzel": ("Rijd de indooractiviteit Uber Pretzel", "Terminez l’activité en salle Uber Pretzel", "Completa la actividad en interior Uber Pretzel", "Absolviere die Indoor-Aktivität Uber Pretzel"),
    "Complete an activity that took more than 24 hours": ("Doe een activiteit die langer dan 24 uur duurde", "Terminez une activité de plus de 24 heures", "Completa una actividad de más de 24 horas", "Absolviere eine Aktivität, die länger als 24 Stunden dauerte"),
    "Complete an activity every day of the week": ("Elke dag van de week een activiteit", "Une activité chaque jour de la semaine", "Una actividad cada día de la semana", "Jeden Tag der Woche eine Aktivität"),
    "An activity every working day, none in the weekend before or after": ("Elke werkdag een activiteit, geen in het weekend ervoor of erna", "Une activité chaque jour ouvré, aucune le week-end avant ou après", "Una actividad cada día laborable, ninguna el fin de semana anterior ni posterior", "Jeden Werktag eine Aktivität, keine am Wochenende davor oder danach"),
    "Activity, 1 rest day, activity, 2 rest days, activity": ("Activiteit, 1 rustdag, activiteit, 2 rustdagen, activiteit", "Activité, 1 jour de repos, activité, 2 jours de repos, activité", "Actividad, 1 día de descanso, actividad, 2 días de descanso, actividad", "Aktivität, 1 Ruhetag, Aktivität, 2 Ruhetage, Aktivität"),
    "Swim, bike and run on the same day, in that order": ("Zwemmen, fietsen en hardlopen op één dag, in die volgorde", "Nagez, roulez et courez le même jour, dans cet ordre", "Nada, pedalea y corre el mismo día, en ese orden", "Schwimmen, Radfahren und Laufen am selben Tag, in dieser Reihenfolge"),
    "Descend more than 1,000 m in one day skiing or snowboarding": ("Daal op één dag meer dan 1.000 m af met skiën of snowboarden", "Descendez plus de 1 000 m en un jour à ski ou en snowboard", "Desciende más de 1.000 m en un día esquiando o en snowboard", "Fahre an einem Tag mehr als 1.000 m mit Ski oder Snowboard ab"),
    "Run a marathon distance": ("Loop een marathonafstand", "Courez la distance d’un marathon", "Corre la distancia de un maratón", "Laufe eine Marathondistanz"),
    "Run a half-marathon distance": ("Loop een halvemarathonafstand", "Courez la distance d’un semi-marathon", "Corre la distancia de una media maratón", "Laufe eine Halbmarathondistanz"),
    "Complete an activity on Christmas Eve": ("Doe een activiteit op kerstavond", "Une activité le soir de Noël", "Una actividad en Nochebuena", "Eine Aktivität an Heiligabend"),
    "Complete an activity on 29 February": ("Doe een activiteit op 29 februari", "Une activité le 29 février", "Una actividad el 29 de febrero", "Eine Aktivität am 29. Februar"),
    "500 km of activities from 24 to 31 December": ("500 km aan activiteiten van 24 tot en met 31 december", "500 km d’activités du 24 au 31 décembre", "500 km de actividades del 24 al 31 de diciembre", "500 km Aktivitäten vom 24. bis 31. Dezember"),
    "Complete activities in 50 countries": ("Activiteiten in 50 landen", "Des activités dans 50 pays", "Actividades en 50 países", "Aktivitäten in 50 Ländern"),
    "Complete 100 Zwift activities": ("Doe 100 Zwift-activiteiten", "Terminez 100 activités Zwift", "Completa 100 actividades en Zwift", "Absolviere 100 Zwift-Aktivitäten"),
    "Trappist Challenge": ("Trappistenuitdaging", "Défi trappiste", "Desafío trapense", "Trappisten-Challenge"),
    "tab.trappists": ("Trappisten", "Trappistes", "Trapenses", "Trappisten"),
    "%lld of %lld Trappist breweries visited": ("%1$lld van %2$lld trappistenbrouwerijen bezocht", "%1$lld brasseries trappistes visitées sur %2$lld", "%1$lld de %2$lld cervecerías trapenses visitadas", "%1$lld von %2$lld Trappistenbrauereien besucht"),
    "Visited %lld times, last on %@": ("%1$lld keer bezocht, laatst op %2$@", "Visitée %1$lld fois, dernière le %2$@", "Visitada %1$lld veces, la última el %2$@", "%1$lld-mal besucht, zuletzt am %2$@"),
    "Not visited yet: ride within 200 m of the brewery": ("Nog niet bezocht: rijd binnen 200 m van de brouwerij", "Pas encore visitée : passez à moins de 200 m de la brasserie", "Aún no visitada: pasa a menos de 200 m de la cervecería", "Noch nicht besucht: fahre näher als 200 m an der Brauerei vorbei"),
    "Challenges": ("Uitdagingen", "Défis", "Desafíos", "Herausforderungen"),
    "Tiles are always at the top of the map. Choose which other challenges are there too; the + at the end of that bar does the same. Everything is still counted, also for challenges you don't show.": ("Tegels staan altijd boven aan de kaart. Kies welke andere uitdagingen daar ook staan; de + aan het eind van die balk doet hetzelfde. Alles wordt gewoon geteld, ook voor uitdagingen die je niet toont.", "Les tuiles sont toujours en haut de la carte. Choisissez les autres défis à y afficher ; le + au bout de cette barre fait de même. Tout reste compté, même pour les défis que vous n’affichez pas.", "Las teselas están siempre en la parte superior del mapa. Elige qué otros desafíos aparecen también; el + al final de esa barra hace lo mismo. Todo se sigue contando, también en los desafíos que no muestras.", "Kacheln stehen immer oben auf der Karte. Wähle, welche anderen Herausforderungen dort auch stehen; das + am Ende dieser Leiste tut dasselbe. Gezählt wird trotzdem alles, auch für Herausforderungen, die du nicht anzeigst."),
    "Climbs appear once your activities are checked against the climbs of their area, or when you look at the Climbs map.": (
        "Klimmen verschijnen zodra je activiteiten zijn vergeleken met de klimmen in hun gebied, of als je de kaart Klimmen bekijkt.",
        "Les montées apparaissent une fois vos activités comparées aux montées de leur zone, ou quand vous regardez la carte Montées.",
        "Las subidas aparecen cuando tus actividades se comparan con las subidas de su zona, o al mirar el mapa Subidas.",
        "Anstiege erscheinen, sobald deine Aktivitäten mit den Anstiegen ihres Gebiets abgeglichen sind, oder wenn du die Karte Anstiege ansiehst."),
    "Climbs are found from elevation data along the roads; Cat 4 to HC as on Strava, and short steep hills. Gradients of short hills are often lower than signposted.": (
        "Klimmen worden gevonden uit hoogtegegevens langs de wegen; Cat. 4 tot HC zoals op Strava, en korte steile heuvels. Hellingspercentages van korte heuvels liggen vaak lager dan op de borden.",
        "Les montées sont trouvées à partir des données d'altitude le long des routes ; Cat. 4 à HC comme sur Strava, et courtes côtes raides. Les pentes des côtes courtes sont souvent plus faibles qu'indiqué.",
        "Las subidas se obtienen de datos de altitud a lo largo de las carreteras; Cat. 4 a HC como en Strava, y repechos cortos. Las pendientes de los repechos cortos suelen ser menores que las señalizadas.",
        "Anstiege werden aus Höhendaten entlang der Straßen ermittelt; Kat. 4 bis HC wie bei Strava, dazu kurze steile Hügel. Steigungen kurzer Hügel sind oft geringer als ausgeschildert."),
    "Climbs climbed": ("Klimmen beklommen", "Montées gravies", "Subidas hechas", "Anstiege gefahren"),
    "Climbs in the areas where you ride and that you looked at on the map.": ("Klimmen in de gebieden waar je rijdt en die je op de kaart hebt bekeken.", "Montées des zones où vous roulez et que vous avez regardées sur la carte.", "Subidas de las zonas donde ruedas y que has mirado en el mapa.", "Anstiege in den Gebieten, in denen du fährst und die du auf der Karte angesehen hast."),
    "Elevation and climbs": ("Hoogte en klimmen", "Altitude et montées", "Altitud y subidas", "Höhe und Anstiege"),
    "Hill": ("Heuvel", "Côte", "Repecho", "Hügel"),
    "No Climbs": ("Geen klimmen", "Aucune montée", "Sin subidas", "Keine Anstiege"),
    "No Climbs Yet": ("Nog geen klimmen", "Pas encore de montées", "Aún sin subidas", "Noch keine Anstiege"),
    "Not climbed yet": ("Nog niet beklommen", "Pas encore gravie", "Aún no subida", "Noch nicht gefahren"),
    "Not yet (%lld)": ("Nog niet (%lld)", "Pas encore (%lld)", "Aún no (%lld)", "Noch nicht (%lld)"),
    "Show": ("Toon", "Afficher", "Mostrar", "Zeigen"),
    "Steepest %@ · top at %lld m": ("Steilste %1$@ · top op %2$lld m", "Pente max. %1$@ · sommet à %2$lld m", "Máx. %1$@ · cima a %2$lld m", "Steilste %1$@ · Gipfel auf %2$lld m"),
    "Strava athlete": ("Strava-sporter", "Athlète Strava", "Deportista de Strava", "Strava-Athlet"),
    "Add your Strava API Client ID and Client Secret to StravaSecrets.plist in the Xcode project, then rebuild.": (
        "Zet je Strava API Client ID en Client Secret in StravaSecrets.plist in het Xcode-project en bouw opnieuw.",
        "Ajoutez votre Client ID et Client Secret de l’API Strava dans StravaSecrets.plist du projet Xcode, puis recompilez.",
        "Añade tu Client ID y Client Secret de la API de Strava a StravaSecrets.plist en el proyecto de Xcode y vuelve a compilar.",
        "Trage Client ID und Client Secret deiner Strava-API in StravaSecrets.plist im Xcode-Projekt ein und baue neu."),
    "Connected as": ("Gekoppeld als", "Connecté en tant que", "Conectado como", "Verbunden als"),
    "With detailed GPS": ("Met gedetailleerde gps", "Avec GPS détaillé", "Con GPS detallado", "Mit detailliertem GPS"),
    "Saved to folder": ("Bewaard in map", "Enregistrées dans le dossier", "Guardadas en la carpeta", "Im Ordner gespeichert"),
    "Sync Now": ("Nu synchroniseren", "Synchroniser", "Sincronizar ahora", "Jetzt synchronisieren"),
    "Disconnect Strava": ("Strava ontkoppelen", "Déconnecter Strava", "Desconectar Strava", "Strava trennen"),
    "Disconnect Strava?": ("Strava ontkoppelen?", "Déconnecter Strava ?", "¿Desconectar Strava?", "Strava trennen?"),
    "Strava": ("Strava", "Strava", "Strava", "Strava"),
    "Choose a save folder above to download detailed GPS and save Strava activities as .fit files.": (
        "Kies hierboven een bewaarmap om gedetailleerde gps te downloaden en Strava-activiteiten als .fit-bestanden te bewaren.",
        "Choisissez un dossier d’enregistrement ci-dessus pour télécharger le GPS détaillé et enregistrer les activités Strava en fichiers .fit.",
        "Elige arriba una carpeta de guardado para descargar el GPS detallado y guardar las actividades de Strava como archivos .fit.",
        "Wähle oben einen Speicherordner, um detailliertes GPS zu laden und Strava-Aktivitäten als .fit-Dateien zu speichern."),
    "Strava activities are saved as .fit files in “%@/%@”. Detailed GPS downloads within Strava's rate limit (about 100 activities per 15 minutes, 1000 per day) and continues automatically.": (
        "Strava-activiteiten worden als .fit-bestanden bewaard in “%1$@/%2$@”. Gedetailleerde gps wordt binnen de Strava-limiet gedownload (ongeveer 100 activiteiten per 15 minuten, 1000 per dag) en gaat automatisch verder.",
        "Les activités Strava sont enregistrées en fichiers .fit dans « %1$@/%2$@ ». Le GPS détaillé se télécharge dans la limite de Strava (environ 100 activités par 15 minutes, 1000 par jour) et reprend automatiquement.",
        "Las actividades de Strava se guardan como archivos .fit en “%1$@/%2$@”. El GPS detallado se descarga dentro del límite de Strava (unas 100 actividades cada 15 minutos, 1000 al día) y continúa automáticamente.",
        "Strava-Aktivitäten werden als .fit-Dateien in „%1$@/%2$@“ gespeichert. Detailliertes GPS wird im Rahmen des Strava-Limits geladen (etwa 100 Aktivitäten pro 15 Minuten, 1000 pro Tag) und läuft automatisch weiter."),
    "Disconnect": ("Ontkoppel", "Déconnecter", "Desconectar", "Trennen"),
    "Strava activities are removed from the map. Files already saved to your folder are kept.": (
        "Strava-activiteiten verdwijnen van de kaart. Bestanden die al in je map staan, blijven bewaard.",
        "Les activités Strava sont retirées de la carte. Les fichiers déjà enregistrés dans votre dossier sont conservés.",
        "Las actividades de Strava se quitan del mapa. Los archivos ya guardados en tu carpeta se conservan.",
        "Strava-Aktivitäten werden von der Karte entfernt. Bereits gespeicherte Dateien bleiben erhalten."),
    "Strava login failed: %@": ("Inloggen bij Strava mislukt: %@", "Échec de la connexion à Strava : %@", "Error al iniciar sesión en Strava: %@", "Strava-Anmeldung fehlgeschlagen: %@"),
    "Connect with Strava": ("Koppel met Strava", "Se connecter avec Strava", "Conectar con Strava", "Mit Strava verbinden"),
    "Not connected to Strava.": ("Niet gekoppeld met Strava.", "Non connecté à Strava.", "No conectado a Strava.", "Nicht mit Strava verbunden."),
    "Strava rate limit reached until %@.": ("Strava-limiet bereikt tot %@.", "Limite Strava atteinte jusqu’à %@.", "Límite de Strava alcanzado hasta las %@.", "Strava-Limit erreicht bis %@."),
    "Strava access was revoked. Please connect again.": ("Toegang tot Strava is ingetrokken. Koppel opnieuw.", "L’accès à Strava a été révoqué. Reconnectez-vous.",
                                                         "Se revocó el acceso a Strava. Vuelve a conectarte.", "Der Strava-Zugriff wurde widerrufen. Bitte neu verbinden."),
    "Strava error %lld: %@": ("Strava-fout %1$lld: %2$@", "Erreur Strava %1$lld : %2$@", "Error de Strava %1$lld: %2$@", "Strava-Fehler %1$lld: %2$@"),
    "Please allow access to your activities.": ("Geef toegang tot je activiteiten.", "Autorisez l’accès à vos activités.",
                                                "Permite el acceso a tus actividades.", "Bitte erlaube den Zugriff auf deine Aktivitäten."),
    "Tiles (14)": ("Tegels (14)", "Tuiles (14)", "Teselas (14)", "Kacheln (14)"),
    "Squadratinhos (17)": ("Squadratinhos (17)", "Squadratinhos (17)", "Squadratinhos (17)", "Squadratinhos (17)"),
    "Zoom 14": ("Zoom 14", "Zoom 14", "Zoom 14", "Zoom 14"),
    "Zoom 17": ("Zoom 17", "Zoom 17", "Zoom 17", "Zoom 17"),

    # Multiple import folders, builds without Strava
    "Choose it again in Settings.": ("Kies hem opnieuw in Instellingen.", "Choisissez-le à nouveau dans Réglages.", "Vuelve a elegirla en Ajustes.", "Wähle ihn in den Einstellungen erneut aus."),
    "Add Another Folder": ("Nog een map toevoegen", "Ajouter un autre dossier", "Añadir otra carpeta", "Weiteren Ordner hinzufügen"),
    "You can add more folders or change them later in Settings.": (
        "Je kunt later meer mappen toevoegen of ze wijzigen in Instellingen.", "Vous pourrez ajouter d’autres dossiers ou les modifier plus tard dans Réglages.",
        "Puedes añadir más carpetas o cambiarlas más tarde en Ajustes.", "Du kannst später weitere Ordner hinzufügen oder sie in den Einstellungen ändern."),
    "Tileroam saves planned routes here as GPX files, in a “Routes” subfolder. Tip: in the picker, go to iCloud Drive, create a new folder “Tileroam” and open it.": (
        "Tileroam bewaart geplande routes hier als GPX-bestanden, in een submap “Routes”. Tip: ga in de kiezer naar iCloud Drive, maak een nieuwe map “Tileroam” en open die.",
        "Tileroam enregistre ici les parcours planifiés en fichiers GPX, dans un sous-dossier « Routes ». Astuce : dans le sélecteur, allez dans iCloud Drive, créez un dossier « Tileroam » et ouvrez-le.",
        "Tileroam guarda aquí las rutas planificadas como archivos GPX, en una subcarpeta “Routes”. Consejo: en el selector, ve a iCloud Drive, crea una carpeta “Tileroam” y ábrela.",
        "Tileroam speichert geplante Routen hier als GPX-Dateien im Unterordner „Routes“. Tipp: Gehe in der Auswahl zu iCloud Drive, erstelle einen Ordner „Tileroam“ und öffne ihn."),
    "Add Folder…": ("Map toevoegen…", "Ajouter un dossier…", "Añadir carpeta…", "Ordner hinzufügen…"),
    "Remove": ("Verwijder", "Retirer", "Quitar", "Entfernen"),
    "Import Folders": ("Importmappen", "Dossiers d’import", "Carpetas de importación", "Importordner"),
    "Tileroam reads .fit files from these folders and their subfolders. Swipe left on a folder to remove it; its activities disappear from the map, the files themselves are not touched.": (
        "Tileroam leest .fit-bestanden uit deze mappen en hun submappen. Veeg een map naar links om hem te verwijderen; de activiteiten verdwijnen van de kaart, de bestanden zelf blijven ongemoeid.",
        "Tileroam lit les fichiers .fit de ces dossiers et de leurs sous-dossiers. Balayez un dossier vers la gauche pour le retirer ; ses activités disparaissent de la carte, les fichiers ne sont pas modifiés.",
        "Tileroam lee los archivos .fit de estas carpetas y sus subcarpetas. Desliza una carpeta a la izquierda para quitarla; sus actividades desaparecen del mapa, los archivos no se tocan.",
        "Tileroam liest .fit-Dateien aus diesen Ordnern und ihren Unterordnern. Wische einen Ordner nach links, um ihn zu entfernen; seine Aktivitäten verschwinden von der Karte, die Dateien selbst bleiben unverändert."),

    # Statistics and virtual rides
    "%lld on map · %lld indoor, virtual or without GPS": (
        "%1$lld op de kaart · %2$lld binnen, virtueel of zonder gps", "%1$lld sur la carte · %2$lld en intérieur, virtuelles ou sans GPS",
        "%1$lld en el mapa · %2$lld en interior, virtuales o sin GPS", "%1$lld auf der Karte · %2$lld indoor, virtuell oder ohne GPS"),
    "E-biking": ("E-biken", "Vélo électrique", "Bici eléctrica", "E-Bike"),
    "Walking": ("Wandelen", "Marche", "Caminar", "Gehen"),
    "Hiking": ("Hiken", "Randonnée", "Senderismo", "Wandern"),
    "Swimming": ("Zwemmen", "Natation", "Natación", "Schwimmen"),
    "Skiing": ("Skiën", "Ski", "Esquí", "Skifahren"),
    "Rowing": ("Roeien", "Aviron", "Remo", "Rudern"),
    "Inline skating": ("Inlineskaten", "Roller", "Patinaje en línea", "Inlineskaten"),
    "Fitness": ("Fitness", "Fitness", "Fitness", "Fitness"),
    "Other": ("Overig", "Autre", "Otros", "Sonstiges"),
    "This Year (%@)": ("Dit jaar (%@)", "Cette année (%@)", "Este año (%@)", "Dieses Jahr (%@)"),
    "All Time": ("Totaal", "Depuis le début", "Desde siempre", "Insgesamt"),
    "Overview": ("Overzicht", "Aperçu", "Resumen", "Überblick"),
    "Countries visited": ("Landen bezocht", "Pays visités", "Países visitados", "Besuchte Länder"),
    "Municipalities visited": ("Gemeenten bezocht", "Communes visitées", "Municipios visitados", "Besuchte Gemeinden"),
    "Postcodes visited": ("Postcodes bezocht", "Codes postaux visités", "Códigos postales visitados", "Besuchte Postleitzahlen"),
    "The largest number E such that you covered at least E km on at least E days. Walking includes hikes.": (
        "Het grootste getal E waarvoor je op minstens E dagen minstens E km hebt afgelegd. Wandelen telt hikes mee.",
        "Le plus grand nombre E tel que vous ayez parcouru au moins E km pendant au moins E jours. La marche inclut les randonnées.",
        "El mayor número E tal que has recorrido al menos E km en al menos E días. Caminar incluye el senderismo.",
        "Die größte Zahl E, für die du an mindestens E Tagen mindestens E km zurückgelegt hast. Gehen schließt Wanderungen ein."),
    "No municipalities visited yet.": ("Nog geen gemeenten bezocht.", "Aucune commune visitée pour l’instant.", "Aún no has visitado ningún municipio.", "Noch keine Gemeinden besucht."),
    "Municipalities per Country": ("Gemeenten per land", "Communes par pays", "Municipios por país", "Gemeinden pro Land"),
    "Counted for the countries switched on in Settings.": ("Geteld voor de landen die in Instellingen aanstaan.", "Comptées pour les pays activés dans Réglages.",
                                                          "Contados para los países activados en Ajustes.", "Gezählt für die in den Einstellungen aktivierten Länder."),
    "%lld / %lld": ("%1$lld / %2$lld", "%1$lld / %2$lld", "%1$lld / %2$lld", "%1$lld / %2$lld"),
    "No activities.": ("Geen activiteiten.", "Aucune activité.", "Sin actividades.", "Keine Aktivitäten."),
    "Total": ("Totaal", "Total", "Total", "Gesamt"),

    # Internal storage
    "On My iPad": ("Op mijn iPad", "Sur mon iPad", "En mi iPad", "Auf meinem iPad"),
    "Internal storage": ("Interne opslag", "Stockage interne", "Almacenamiento interno", "Interner Speicher"),
    "Use Internal Storage": ("Gebruik interne opslag", "Utiliser le stockage interne", "Usar almacenamiento interno", "Internen Speicher verwenden"),
    "Tileroam saves planned routes and downloaded activities here, in “Routes” and “%@” subfolders. Without a chosen folder they stay in the app's own storage, which you can open in the Files app. Choose a folder, for example a new “Tileroam” folder in iCloud Drive, to keep them in iCloud.": (
        "Tileroam bewaart geplande routes en gedownloade activiteiten hier, in de submappen “Routes” en “%@”. Zonder gekozen map blijven ze in de eigen opslag van de app, die je in de Bestanden-app kunt openen. Kies een map, bijvoorbeeld een nieuwe map “Tileroam” in iCloud Drive, om ze in iCloud te bewaren.",
        "Tileroam enregistre ici les parcours planifiés et les activités téléchargées, dans les sous-dossiers « Routes » et « %@ ». Sans dossier choisi, ils restent dans le stockage de l’app, accessible depuis l’app Fichiers. Choisissez un dossier, par exemple un nouveau dossier « Tileroam » dans iCloud Drive, pour les garder dans iCloud.",
        "Tileroam guarda aquí las rutas planificadas y las actividades descargadas, en las subcarpetas “Routes” y “%@”. Sin carpeta elegida se quedan en el almacenamiento propio de la app, que puedes abrir en la app Archivos. Elige una carpeta, por ejemplo una nueva carpeta “Tileroam” en iCloud Drive, para guardarlas en iCloud.",
        "Tileroam speichert geplante Routen und geladene Aktivitäten hier, in den Unterordnern „Routes“ und „%@“. Ohne gewählten Ordner bleiben sie im eigenen Speicher der App, den du in der Dateien-App öffnen kannst. Wähle einen Ordner, zum Beispiel einen neuen Ordner „Tileroam“ in iCloud Drive, um sie in iCloud zu behalten."),
    "Tileroam saves planned routes here, in a “Routes” subfolder. Without a chosen folder they stay in the app's own storage, which you can open in the Files app. Choose a folder, for example a new “Tileroam” folder in iCloud Drive, to keep them in iCloud.": (
        "Tileroam bewaart geplande routes hier, in een submap “Routes”. Zonder gekozen map blijven ze in de eigen opslag van de app, die je in de Bestanden-app kunt openen. Kies een map, bijvoorbeeld een nieuwe map “Tileroam” in iCloud Drive, om ze in iCloud te bewaren.",
        "Tileroam enregistre ici les parcours planifiés, dans un sous-dossier « Routes ». Sans dossier choisi, ils restent dans le stockage de l’app, accessible depuis l’app Fichiers. Choisissez un dossier, par exemple un nouveau dossier « Tileroam » dans iCloud Drive, pour les garder dans iCloud.",
        "Tileroam guarda aquí las rutas planificadas, en una subcarpeta “Routes”. Sin carpeta elegida se quedan en el almacenamiento propio de la app, que puedes abrir en la app Archivos. Elige una carpeta, por ejemplo una nueva carpeta “Tileroam” en iCloud Drive, para guardarlas en iCloud.",
        "Tileroam speichert geplante Routen hier im Unterordner „Routes“. Ohne gewählten Ordner bleiben sie im eigenen Speicher der App, den du in der Dateien-App öffnen kannst. Wähle einen Ordner, zum Beispiel einen neuen Ordner „Tileroam“ in iCloud Drive, um sie in iCloud zu behalten."),
    "Strava is not set up in this build: add StravaConfig.plist with the Client ID and token service URL, then rebuild.": (
        "Strava is niet ingesteld in deze build: voeg StravaConfig.plist toe met het Client ID en de URL van de tokenservice en bouw opnieuw.",
        "Strava n’est pas configuré dans ce build : ajoutez StravaConfig.plist avec le Client ID et l’URL du service de jetons, puis recompilez.",
        "Strava no está configurado en esta compilación: añade StravaConfig.plist con el Client ID y la URL del servicio de tokens y vuelve a compilar.",
        "Strava ist in diesem Build nicht eingerichtet: Füge StravaConfig.plist mit der Client ID und der URL des Token-Dienstes hinzu und baue neu."),
    "Try with Sample Rides": ("Probeer met voorbeeldritten", "Essayer avec des sorties d’exemple", "Probar con rutas de ejemplo", "Mit Beispielfahrten ausprobieren"),
    "Remove Sample Rides": ("Verwijder voorbeeldritten", "Supprimer les sorties d’exemple", "Quitar rutas de ejemplo", "Beispielfahrten entfernen"),
    # iCloud
    "Use iCloud Drive": ("Gebruik iCloud Drive", "Utiliser iCloud Drive", "Usar iCloud Drive", "iCloud Drive verwenden"),
    "iCloud Drive": ("iCloud Drive", "iCloud Drive", "iCloud Drive", "iCloud Drive"),
    "Tileroam saves planned routes and downloaded activities here, in “Routes” and “%@” subfolders. Without a chosen folder they go to Tileroam's folder in iCloud Drive, so your other devices have them too, or to the app's own storage when iCloud Drive is off.": (
        "Tileroam bewaart geplande routes en gedownloade activiteiten hier, in de submappen “Routes” en “%@”. Zonder gekozen map gaan ze naar de map van Tileroam in iCloud Drive, zodat je andere apparaten ze ook hebben, of naar de eigen opslag van de app als iCloud Drive uit staat.",
        "Tileroam enregistre ici les parcours planifiés et les activités téléchargées, dans les sous-dossiers « Routes » et « %@ ». Sans dossier choisi, ils vont dans le dossier Tileroam d’iCloud Drive, pour que vos autres appareils les aient aussi, ou dans le stockage de l’app si iCloud Drive est désactivé.",
        "Tileroam guarda aquí las rutas planificadas y las actividades descargadas, en las subcarpetas “Routes” y “%@”. Sin carpeta elegida van a la carpeta de Tileroam en iCloud Drive, para que tus otros dispositivos también las tengan, o al almacenamiento propio de la app si iCloud Drive está desactivado.",
        "Tileroam speichert geplante Routen und geladene Aktivitäten hier, in den Unterordnern „Routes“ und „%@“. Ohne gewählten Ordner landen sie im Tileroam-Ordner in iCloud Drive, damit deine anderen Geräte sie auch haben, oder im eigenen Speicher der App, wenn iCloud Drive aus ist."),
    "Tileroam saves planned routes here, in a “Routes” subfolder. Without a chosen folder they go to Tileroam's folder in iCloud Drive, so your other devices have them too, or to the app's own storage when iCloud Drive is off.": (
        "Tileroam bewaart geplande routes hier, in een submap “Routes”. Zonder gekozen map gaan ze naar de map van Tileroam in iCloud Drive, zodat je andere apparaten ze ook hebben, of naar de eigen opslag van de app als iCloud Drive uit staat.",
        "Tileroam enregistre ici les parcours planifiés, dans un sous-dossier « Routes ». Sans dossier choisi, ils vont dans le dossier Tileroam d’iCloud Drive, pour que vos autres appareils les aient aussi, ou dans le stockage de l’app si iCloud Drive est désactivé.",
        "Tileroam guarda aquí las rutas planificadas, en una subcarpeta “Routes”. Sin carpeta elegida van a la carpeta de Tileroam en iCloud Drive, para que tus otros dispositivos también las tengan, o al almacenamiento propio de la app si iCloud Drive está desactivado.",
        "Tileroam speichert geplante Routen hier im Unterordner „Routes“. Ohne gewählten Ordner landen sie im Tileroam-Ordner in iCloud Drive, damit deine anderen Geräte sie auch haben, oder im eigenen Speicher der App, wenn iCloud Drive aus ist."),
    "Tileroam reads .fit files from these folders and their subfolders, and always from its own folder in iCloud Drive, shared by your devices, and the Import folder in its own storage (put files there with the Files app or AirDrop). Swipe left on a folder to remove it; its activities disappear from the map, the files themselves are not touched.": (
        "Tileroam leest .fit-bestanden uit deze mappen en hun submappen, en altijd uit de eigen map in iCloud Drive, die je apparaten delen, en uit de map Import in de eigen opslag (zet bestanden daar met de Bestanden-app of AirDrop). Veeg een map naar links om hem te verwijderen; de activiteiten verdwijnen van de kaart, de bestanden zelf blijven ongemoeid.",
        "Tileroam lit les fichiers .fit de ces dossiers et de leurs sous-dossiers, ainsi que toujours de son dossier iCloud Drive, partagé par vos appareils, et du dossier Import de son propre stockage (déposez-y des fichiers avec l’app Fichiers ou AirDrop). Balayez un dossier vers la gauche pour le retirer ; ses activités disparaissent de la carte, les fichiers ne sont pas modifiés.",
        "Tileroam lee los archivos .fit de estas carpetas y sus subcarpetas, y siempre de su propia carpeta en iCloud Drive, compartida por tus dispositivos, y de la carpeta Import de su propio almacenamiento (pon archivos ahí con la app Archivos o AirDrop). Desliza una carpeta a la izquierda para quitarla; sus actividades desaparecen del mapa, los archivos no se tocan.",
        "Tileroam liest .fit-Dateien aus diesen Ordnern und ihren Unterordnern und immer aus dem eigenen Ordner in iCloud Drive, den deine Geräte teilen, sowie aus dem Ordner Import im eigenen Speicher (lege Dateien dort mit der Dateien-App oder AirDrop ab). Wische einen Ordner nach links, um ihn zu entfernen; seine Aktivitäten verschwinden von der Karte, die Dateien selbst bleiben unverändert."),
    "%@ › Import": ("%@ › Import", "%@ › Import", "%@ › Import", "%@ › Import"),
    "Tileroam reads .fit files from these folders and their subfolders, and always from the Import folder in its own storage (put files there with the Files app or AirDrop). Swipe left on a folder to remove it; its activities disappear from the map, the files themselves are not touched.": (
        "Tileroam leest .fit-bestanden uit deze mappen en hun submappen, en altijd uit de map Import in de eigen opslag (zet bestanden daar met de Bestanden-app of AirDrop). Veeg een map naar links om hem te verwijderen; de activiteiten verdwijnen van de kaart, de bestanden zelf blijven ongemoeid.",
        "Tileroam lit les fichiers .fit de ces dossiers et de leurs sous-dossiers, ainsi que toujours du dossier Import de son propre stockage (déposez-y des fichiers avec l’app Fichiers ou AirDrop). Balayez un dossier vers la gauche pour le retirer ; ses activités disparaissent de la carte, les fichiers ne sont pas modifiés.",
        "Tileroam lee los archivos .fit de estas carpetas y sus subcarpetas, y siempre de la carpeta Import de su propio almacenamiento (pon archivos ahí con la app Archivos o AirDrop). Desliza una carpeta a la izquierda para quitarla; sus actividades desaparecen del mapa, los archivos no se tocan.",
        "Tileroam liest .fit-Dateien aus diesen Ordnern und ihren Unterordnern und immer aus dem Ordner Import im eigenen Speicher (lege Dateien dort mit der Dateien-App oder AirDrop ab). Wische einen Ordner nach links, um ihn zu entfernen; seine Aktivitäten verschwinden von der Karte, die Dateien selbst bleiben unverändert."),
    "Strava activities are saved as .fit files in the save folder's “%@” subfolder. Detailed GPS downloads within Strava's rate limit (about 100 activities per 15 minutes, 1000 per day) and continues automatically.": (
        "Strava-activiteiten worden als .fit-bestanden bewaard in de submap “%@” van de bewaarmap. Gedetailleerde gps wordt binnen de Strava-limiet gedownload (ongeveer 100 activiteiten per 15 minuten, 1000 per dag) en gaat automatisch verder.",
        "Les activités Strava sont enregistrées en fichiers .fit dans le sous-dossier « %@ » du dossier d’enregistrement. Le GPS détaillé se télécharge dans la limite de Strava (environ 100 activités par 15 minutes, 1000 par jour) et reprend automatiquement.",
        "Las actividades de Strava se guardan como archivos .fit en la subcarpeta “%@” de la carpeta de guardado. El GPS detallado se descarga dentro del límite de Strava (unas 100 actividades cada 15 minutos, 1000 al día) y continúa automáticamente.",
        "Strava-Aktivitäten werden als .fit-Dateien im Unterordner „%@“ des Speicherordners gespeichert. Detailliertes GPS wird im Rahmen des Strava-Limits geladen (etwa 100 Aktivitäten pro 15 Minuten, 1000 pro Tag) und läuft automatisch weiter."),

    # Map layers
    "Map": ("Kaart", "Plan", "Mapa", "Karte"),
    "Satellite": ("Satelliet", "Satellite", "Satélite", "Satellit"),
    "Hybrid": ("Hybride", "Hybride", "Híbrido", "Hybrid"),
    "Map Style": ("Kaartstijl", "Style de carte", "Estilo de mapa", "Kartenstil"),

    # First-start prompt
    "Add your activities": ("Voeg je activiteiten toe", "Ajoutez vos activités", "Añade tus actividades", "Füge deine Aktivitäten hinzu"),
    "Choose a folder with .fit files, import files, or connect Strava to see where you have been.": (
        "Kies een map met .fit-bestanden, importeer bestanden of koppel Strava om te zien waar je bent geweest.",
        "Choisissez un dossier de fichiers .fit, importez des fichiers ou connectez Strava pour voir où vous êtes allé.",
        "Elige una carpeta con archivos .fit, importa archivos o conecta Strava para ver dónde has estado.",
        "Wähle einen Ordner mit .fit-Dateien, importiere Dateien oder verbinde Strava, um zu sehen, wo du warst."),
    "Choose a folder with .fit files or import files to see where you have been.": (
        "Kies een map met .fit-bestanden of importeer bestanden om te zien waar je bent geweest.",
        "Choisissez un dossier de fichiers .fit ou importez des fichiers pour voir où vous êtes allé.",
        "Elige una carpeta con archivos .fit o importa archivos para ver dónde has estado.",
        "Wähle einen Ordner mit .fit-Dateien oder importiere Dateien, um zu sehen, wo du warst."),
    "Import .fit Files…": ("Importeer .fit-bestanden…", "Importer des fichiers .fit…", "Importar archivos .fit…", ".fit-Dateien importieren…"),

    # Strava login
    "Powered by Strava": ("Powered by Strava",) * 4,
    "The login request expired. Please try again.": ("Het inlogverzoek is verlopen. Probeer het opnieuw.", "La demande de connexion a expiré. Réessayez.",
                                                    "La solicitud de inicio de sesión ha caducado. Inténtalo de nuevo.", "Die Anmeldeanfrage ist abgelaufen. Bitte versuche es erneut."),

    # Widget
    "%lld× %lld km to go": ("nog %1$lld× %2$lld km", "encore %1$lld× %2$lld km", "faltan %1$lld× %2$lld km", "noch %1$lld× %2$lld km"),
    "Eddington": ("Eddington", "Eddington", "Eddington", "Eddington"),
    "Cycling": ("Fietsen", "Vélo", "Ciclismo", "Radfahren"),
    "Running": ("Hardlopen", "Course", "Carrera", "Laufen"),
    "Eddington Number": ("Eddington-getal", "Nombre d’Eddington", "Número de Eddington", "Eddington-Zahl"),
    "Your cycling Eddington number: E rides of at least E km.": (
        "Je Eddington-getal voor fietsen: E ritten van minstens E km.", "Votre nombre d’Eddington à vélo : E sorties d’au moins E km.",
        "Tu número de Eddington en bici: E salidas de al menos E km.", "Deine Rad-Eddington-Zahl: E Fahrten à mindestens E km."),
    "Tiles Around You": ("Tegels om je heen", "Tuiles autour de vous", "Teselas a tu alrededor", "Kacheln um dich herum"),
    "A map of the tiles around your current location: visited tiles in green.": (
        "Een kaart van de tegels rond je huidige locatie: bezochte tegels in groen.",
        "Une carte des tuiles autour de votre position : les tuiles visitées en vert.",
        "Un mapa de las teselas alrededor de tu ubicación: las visitadas en verde.",
        "Eine Karte der Kacheln rund um deinen Standort: besuchte Kacheln in Grün."),
    "Loading map…": ("Kaart laden…", "Chargement de la carte…", "Cargando mapa…", "Karte wird geladen…"),
    "Open Tileroam to share your location": ("Open Tileroam om je locatie te delen", "Ouvrez Tileroam pour partager votre position",
                                             "Abre Tileroam para compartir tu ubicación", "Öffne Tileroam, um deinen Standort zu teilen"),
}

# Short tab titles (key -> en, nl, fr, es, de)
TABS = {
    "tab.tiles": ("Tiles", "Tegels", "Tuiles", "Teselas", "Kacheln"),
    "tab.routes": ("Routes", "Routes", "Parcours", "Rutas", "Routen"),
    "tab.municipalities": ("Towns", "Gemeenten", "Communes", "Municipios", "Gemeinden"),
    "tab.postcodes": ("Postcodes", "Postcodes", "Codes post.", "C. postales", "PLZ"),
    "tab.climbs": ("Climbs", "Klimmen", "Montées", "Subidas", "Anstiege"),
}

# Plural keys: key -> {lang: (one, other)}; "en" included.
P = {
    "Deleted %lld files saved from Strava.": {"en": ("Deleted %lld file saved from Strava.", "Deleted %lld files saved from Strava."),
        "nl": ("%lld bestand van Strava verwijderd.", "%lld bestanden van Strava verwijderd."),
        "fr": ("%lld fichier de Strava supprimé.", "%lld fichiers de Strava supprimés."),
        "es": ("%lld archivo de Strava eliminado.", "%lld archivos de Strava eliminados."),
        "de": ("%lld Datei von Strava gelöscht.", "%lld Dateien von Strava gelöscht.")},
    "Delete %lld Files": {"en": ("Delete %lld File", "Delete %lld Files"), "nl": ("Verwijder %lld bestand", "Verwijder %lld bestanden"),
        "fr": ("Supprimer %lld fichier", "Supprimer %lld fichiers"), "es": ("Eliminar %lld archivo", "Eliminar %lld archivos"),
        "de": ("%lld Datei löschen", "%lld Dateien löschen")},
    "%lld tiles": {"en": ("%lld tile", "%lld tiles"), "nl": ("%lld tegel", "%lld tegels"), "fr": ("%lld tuile", "%lld tuiles"),
                   "es": ("%lld tesela", "%lld teselas"), "de": ("%lld Kachel", "%lld Kacheln")},
    "%lld squadratinhos": {"en": ("%lld squadratinho", "%lld squadratinhos"), "nl": ("%lld squadratinho", "%lld squadratinho’s"),
                           "fr": ("%lld squadratinho", "%lld squadratinhos"), "es": ("%lld squadratinho", "%lld squadratinhos"),
                           "de": ("%lld Squadratinho", "%lld Squadratinhos")},
    "%lld municipalities": {"en": ("%lld municipality", "%lld municipalities"), "nl": ("%lld gemeente", "%lld gemeenten"),
                            "fr": ("%lld commune", "%lld communes"), "es": ("%lld municipio", "%lld municipios"),
                            "de": ("%lld Gemeinde", "%lld Gemeinden")},
    "%lld postcodes": {"en": ("%lld postcode", "%lld postcodes"), "nl": ("%lld postcode", "%lld postcodes"),
                       "fr": ("%lld code postal", "%lld codes postaux"), "es": ("%lld código postal", "%lld códigos postales"),
                       "de": ("%lld Postleitzahl", "%lld Postleitzahlen")},
    "%lld activities": {"en": ("%lld activity", "%lld activities"), "nl": ("%lld activiteit", "%lld activiteiten"),
                        "fr": ("%lld activité", "%lld activités"), "es": ("%lld actividad", "%lld actividades"),
                        "de": ("%lld Aktivität", "%lld Aktivitäten")},
    "%lld stops": {"en": ("%lld stop", "%lld stops"), "nl": ("%lld stop", "%lld stops"), "fr": ("%lld arrêt", "%lld arrêts"),
                   "es": ("%lld parada", "%lld paradas"), "de": ("%lld Stopp", "%lld Stopps")},
    "You can select up to %lld items per route.": {
        "en": ("You can select up to %lld item per route.", "You can select up to %lld items per route."),
        "nl": ("Je kunt maximaal %lld item per route kiezen.", "Je kunt maximaal %lld items per route kiezen."),
        "fr": ("Vous pouvez choisir jusqu’à %lld élément par parcours.", "Vous pouvez choisir jusqu’à %lld éléments par parcours."),
        "es": ("Puedes elegir hasta %lld elemento por ruta.", "Puedes elegir hasta %lld elementos por ruta."),
        "de": ("Du kannst bis zu %lld Element pro Route wählen.", "Du kannst bis zu %lld Elemente pro Route wählen.")},
}
# Keys with a plural on one argument among several: key -> (argNum, {lang: (format, one, other)}).
def rides(en1, en2, nl, fr, es, de):
    return {"en": en1, "nl": nl, "fr": fr, "es": es, "de": de} if en2 is None else None

S = {
    "Moved %lld files to %@.": (1, {
        "en": ("Moved %#@n@ to %2$@.", "%arg file", "%arg files"),
        "nl": ("%#@n@ verplaatst naar %2$@.", "%arg bestand", "%arg bestanden"),
        "fr": ("%#@n@ déplacé(s) vers %2$@.", "%arg fichier", "%arg fichiers"),
        "es": ("%#@n@ movido(s) a %2$@.", "%arg archivo", "%arg archivos"),
        "de": ("%#@n@ nach %2$@ verschoben.", "%arg Datei", "%arg Dateien")}),
    "Moved %lld earlier saved files to “%@”.": (1, {
        "en": ("Moved %#@n@ to “%2$@”.", "%arg earlier saved file", "%arg earlier saved files"),
        "nl": ("%#@n@ verplaatst naar “%2$@”.", "%arg eerder bewaard bestand", "%arg eerder bewaarde bestanden"),
        "fr": ("%#@n@ déplacé(s) vers « %2$@ ».", "%arg fichier enregistré", "%arg fichiers enregistrés"),
        "es": ("%#@n@ movido(s) a “%2$@”.", "%arg archivo guardado", "%arg archivos guardados"),
        "de": ("%#@n@ nach „%2$@“ verschoben.", "%arg früher gespeicherte Datei", "%arg früher gespeicherte Dateien")}),
    "Eddington %lld · %lld more rides of %lld km to reach %lld": (2, {
        "en": ("Eddington %1$lld · %#@n@ of %3$lld km to reach %4$lld", "%arg more ride", "%arg more rides"),
        "nl": ("Eddington %1$lld · nog %#@n@ van %3$lld km voor %4$lld", "%arg rit", "%arg ritten"),
        "fr": ("Eddington %1$lld · encore %#@n@ de %3$lld km pour atteindre %4$lld", "%arg sortie", "%arg sorties"),
        "es": ("Eddington %1$lld · %#@n@ más de %3$lld km para llegar a %4$lld", "%arg salida", "%arg salidas"),
        "de": ("Eddington %1$lld · noch %#@n@ à %3$lld km bis %4$lld", "%arg Fahrt", "%arg Fahrten")}),
    "%lld more rides of at least %lld km to reach %lld": (1, {
        "en": ("%#@n@ of at least %2$lld km to reach %3$lld", "%arg more ride", "%arg more rides"),
        "nl": ("Nog %#@n@ van minstens %2$lld km voor %3$lld", "%arg rit", "%arg ritten"),
        "fr": ("Encore %#@n@ d’au moins %2$lld km pour atteindre %3$lld", "%arg sortie", "%arg sorties"),
        "es": ("%#@n@ más de al menos %2$lld km para llegar a %3$lld", "%arg salida", "%arg salidas"),
        "de": ("Noch %#@n@ à mindestens %2$lld km bis %3$lld", "%arg Fahrt", "%arg Fahrten")}),
    "%lld more runs of at least %lld km to reach %lld": (1, {
        "en": ("%#@n@ of at least %2$lld km to reach %3$lld", "%arg more run", "%arg more runs"),
        "nl": ("Nog %#@n@ van minstens %2$lld km voor %3$lld", "%arg hardloopronde", "%arg hardlooprondes"),
        "fr": ("Encore %#@n@ d’au moins %2$lld km pour atteindre %3$lld", "%arg course", "%arg courses"),
        "es": ("%#@n@ más de al menos %2$lld km para llegar a %3$lld", "%arg carrera", "%arg carreras"),
        "de": ("Noch %#@n@ à mindestens %2$lld km bis %3$lld", "%arg Lauf", "%arg Läufe")}),
    "%lld more walks of at least %lld km to reach %lld": (1, {
        "en": ("%#@n@ of at least %2$lld km to reach %3$lld", "%arg more walk", "%arg more walks"),
        "nl": ("Nog %#@n@ van minstens %2$lld km voor %3$lld", "%arg wandeling", "%arg wandelingen"),
        "fr": ("Encore %#@n@ d’au moins %2$lld km pour atteindre %3$lld", "%arg marche", "%arg marches"),
        "es": ("%#@n@ más de al menos %2$lld km para llegar a %3$lld", "%arg caminata", "%arg caminatas"),
        "de": ("Noch %#@n@ à mindestens %2$lld km bis %3$lld", "%arg Spaziergang", "%arg Spaziergänge")}),
    "%lld more rides of %lld km": (1, {
        "en": ("%#@n@ of %2$lld km", "%arg more ride", "%arg more rides"),
        "nl": ("nog %#@n@ van %2$lld km", "%arg rit", "%arg ritten"),
        "fr": ("encore %#@n@ de %2$lld km", "%arg sortie", "%arg sorties"),
        "es": ("%#@n@ más de %2$lld km", "%arg salida", "%arg salidas"),
        "de": ("noch %#@n@ à %2$lld km", "%arg Fahrt", "%arg Fahrten")}),
    "%lld more runs of %lld km": (1, {
        "en": ("%#@n@ of %2$lld km", "%arg more run", "%arg more runs"),
        "nl": ("nog %#@n@ van %2$lld km", "%arg ronde", "%arg rondes"),
        "fr": ("encore %#@n@ de %2$lld km", "%arg course", "%arg courses"),
        "es": ("%#@n@ más de %2$lld km", "%arg carrera", "%arg carreras"),
        "de": ("noch %#@n@ à %2$lld km", "%arg Lauf", "%arg Läufe")}),
}


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def catalog(keys):
    strings = {}
    for key in keys:
        if key in P:
            strings[key] = {"localizations": {lang: {"variations": {"plural": {"one": unit(one), "other": unit(other)}}}
                                              for lang, (one, other) in P[key].items()}}
        elif key in S:
            arg, forms = S[key]
            strings[key] = {"localizations": {
                lang: {"stringUnit": {"state": "translated", "value": fmt},
                       "substitutions": {"n": {"argNum": arg, "formatSpecifier": "lld",
                                               "variations": {"plural": {"one": unit(one), "other": unit(other)}}}}}
                for lang, (fmt, one, other) in forms.items()}}
        elif key in TABS:
            strings[key] = {"extractionState": "manual",
                            "localizations": {lang: unit(v) for lang, v in zip(["en"] + LANGS, TABS[key])}}
        elif key in T:
            strings[key] = {"localizations": {lang: unit(v) for lang, v in zip(LANGS, T[key])}}
        else:
            strings[key] = {}
            print("UNTRANSLATED:", key)
    return {"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}


for target in ["Tileroam", "TileroamWidget"]:
    keys = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), f"keys-{target}.json")))
    if target == "Tileroam":
        keys = list(dict.fromkeys(keys + list(TABS)))
    with open(f"{ROOT}/{target}/Localizable.xcstrings", "w") as f:
        json.dump(catalog(keys), f, ensure_ascii=False, indent=2)

# Info.plist strings (app name stays; location permission text)
info = {
    "NSLocationWhenInUseUsageDescription": (
        "Tileroam uses your location to show where you are on the map and to plan cycling routes from there. Routes are calculated on your device.",
        ("Tileroam gebruikt je locatie om te tonen waar je bent en om fietsroutes vanaf daar te plannen. Routes worden op je apparaat berekend.",
         "Tileroam utilise votre position pour l’afficher sur la carte et planifier des parcours à vélo depuis celle-ci. Les parcours sont calculés sur votre appareil.",
         "Tileroam usa tu ubicación para mostrar dónde estás y planificar rutas en bici desde allí. Las rutas se calculan en tu dispositivo.",
         "Tileroam nutzt deinen Standort, um ihn auf der Karte zu zeigen und Radrouten ab dort zu planen. Routen werden auf deinem Gerät berechnet.")),
    "CFBundleDisplayName": ("Tileroam", ("Tileroam",) * 4),
}
strings = {}
for key, (en, translations) in info.items():
    locs = {"en": unit(en)}
    locs.update({lang: unit(v) for lang, v in zip(LANGS, translations)})
    strings[key] = {"localizations": locs, "shouldTranslate": key != "CFBundleDisplayName"}
with open(f"{ROOT}/Tileroam/InfoPlist.xcstrings", "w") as f:
    json.dump({"sourceLanguage": "en", "strings": strings, "version": "1.0"}, f, ensure_ascii=False, indent=2)
print("done")
