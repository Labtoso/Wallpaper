# Wallpaper

Dunkle Wallpaper-Galerie mit Kategorien aus Ordnern, Einzel- und Pack-Downloads, Merkliste und Bildansicht mit Zoom.

## Lokal starten

Node.js 22 oder neuer, keine zusätzlichen Pakete nötig.

```sh
node preview.mjs
```

Unter `http://127.0.0.1:4173` öffnen. Neue Ordner und Bilder werden während der Vorschau automatisch erkannt; die geöffnete Seite aktualisiert die Sammlung innerhalb von etwa acht Sekunden.

## Bilder und Packs hinzufügen

### Mit dem portablen Windows-Programm

1. **Wallpaper Upload.bat** direkt in diesem Projektordner doppelklicken. Der Starter und der Unterordner uploader gehören zusammen; eine Installation ist nicht nötig. Die vorhandene EXE bleibt als zusätzlicher Starter verwendbar.
2. Einen Packnamen eingeben oder ein vorhandenes Pack auswählen.
3. Bilder, einen ganzen Ordner oder Dateien per Drag-and-drop hinzufügen.
4. **Hochladen** drücken. Das Programm kopiert die Originale nach assets, erstellt einen Commit als Labtoso und pusht zu diesem Repo. GitHub Pages baut daraus automatisch Kategorien und ZIP-Packs.

Das Fenster nutzt durchgehend Darkmode: links Pack und Projekt, rechts eine Bilderliste mit Vorschauen, unten Upload-Status und Hauptaktion. Die ausführlichen Details sind einklappbar. Dateien lassen sich einzeln aus der Auswahl entfernen; dabei werden keine Originaldateien gelöscht.

Git for Windows und GitHub CLI müssen vorhanden sein; die vorhandene Anmeldung als Labtoso wird genutzt. Das Projekt ist voreingestellt und kann bei Bedarf über „Projekt ändern …“ geändert werden. „Nur lokal hinzufügen“ kopiert ohne Veröffentlichung.

Die 25-MiB-Grenze des GitHub-Web-Uploads entfällt beim Git-Upload; normale GitHub-Repos erlauben bis 100 MiB je Datei. Größere Einzelbilder werden vor dem Kopieren gemeldet, nicht still verkleinert. Ganze Packs dürfen aus vielen Bildern bestehen. [GitHub-Dateilimits](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github)

Vor Veröffentlichungen wird eine lokale Sicherung unter _old erstellt. Unterschiedliche Dateien mit gleichem Namen bekommen einen Zusatz, statt vorhandene Dateien zu überschreiben. Nur ausgewählte Bilder werden committed; fremde vorgemerkte Änderungen bleiben erhalten. Andere lokale, noch nicht veröffentlichte Commits stoppen den Upload mit einer Meldung.

Quellcode und wiederholbarer Windows-Build liegen in uploader. Optional neu bauen:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uploader\Build-Upload.ps1
```

### Direkt im Dateisystem

```text
assets/
  Wald/
    Nebel.jpg
    Lichtung.png
  Minimal/
    Dunkel.webp
```

Jeder direkte Unterordner von assets erscheint mit seinem Namen als Kategorie und als herunterladbares ZIP-Pack. Unterordner innerhalb eines Packs bleiben beim ZIP-Download erhalten. Bilder direkt in assets gehören zur Sammlung. Leere Ordner werden lokal ebenfalls angezeigt; auf GitHub für leere Ordner gegebenenfalls eine .gitkeep-Datei hinzufügen.

Unterstützt: JPG, JPEG, PNG, WebP, GIF, AVIF und SVG. Die Bildtitel werden aus den Dateinamen übernommen. Passende *-thumb-Dateien werden nur als Vorschauen genutzt, wenn die gleichnamige *-full-Datei vorhanden ist; im ZIP landen nur Originale.

## Quellen und Bildtitel

Optional eine sources.json im jeweiligen Pack ablegen:

```json
{
  "Nebel.jpg": {
    "title": "Morgen im Wald",
    "author": "Name",
    "url": "https://example.com/original",
    "license": "Lizenzname",
    "licenseUrl": "https://example.com/lizenz"
  }
}
```

Für verschachtelte Bilder kann der Schlüssel auch Unterordner/Bild.jpg lauten. Fehlende Angaben werden nicht erfunden. Für die ursprüngliche Sammlung stehen Urheber und Originalquellen in photos.json.

## Bedienung

- Bild anklicken: große Bildansicht.
- Dort auf das Bild klicken: 100-%-Zoom, nochmals klicken: einpassen. Lupe mit Plus/Minus; vergrößerte Bilder lassen sich verschieben.
- Pfeile oder Pfeiltasten: voriges/nächstes Bild. Auf Mobilgeräten auch wischen.
- Vorschaustreifen: direkt zu einem Bild wechseln. Esc schließt die Bildansicht.
- Vor jedem Download erscheint die Auswahl Original, Desktop (2560×1440) oder Mobil (1080×1920). Originale bleiben unverändert; Desktop und Mobil werden als mittiger JPEG-Ausschnitt erzeugt. Die Auswahl gilt für einzelne Bilder und ganze ZIP-Packs.
- Merkliste bleibt ausschließlich in diesem Browser gespeichert.
- Copyright: © aktuelles Jahr Labtoso; die Jahreszahl aktualisiert sich automatisch.

## GitHub Pages

```sh
node --test tests/catalog.test.mjs tests/downloads.test.mjs
node build.mjs
```

Der Build erzeugt dist mit Bildkatalog und ZIP-Packs. Der vorhandene GitHub-Pages-Workflow führt Tests und Build nach jedem Push auf main aus und veröffentlicht ausschließlich dist. Es muss kein Katalog von Hand gepflegt werden. Neue Dateien für die Online-Seite einfach unter assets committen und pushen.

Keine zusätzlichen Pakete, externen Skripte oder Schriftarten. ZIP-Packs enthalten Originale ohne Qualitätsverlust; maximale Packgröße derzeit 4 GB.

## Bildrechte

Die ursprünglichen Fotografien stammen von Unsplash, bezogen über Lorem Picsum. Quellen stehen pro Bild sowie unter Quellen auf der Website. Es gilt die [Unsplash-Lizenz](https://unsplash.com/license); die Rechte an den Fotos verbleiben bei ihren Urhebern. Für eigene Packs passende Quellen- und Lizenzangaben ergänzen.
