# Wallpaper

Ein kuratiertes Wallpaper-Archiv. Dauerhaft dunkel, mit Motivfiltern, Merkliste und Downloads für Desktop und Handy.

## Start

Node.js 22 oder neuer, keine zusätzlichen Pakete nötig.

```sh
node build.mjs
node preview.mjs
```

Danach `http://127.0.0.1:4173` öffnen. Alternativ den Inhalt von `dist` auf einem beliebigen statischen Webserver hosten.

## Dateien

- `assets/`: sämtliche Original-Wallpaper (`*-full.jpg`) und optimierte Galerie-Vorschauen (`*-thumb.jpg`).
- `photos.json`: tatsächliche Bildgrößen, Fotograf:innen und Originalquellen.
- `app.js`: redaktionelle Titel, Filter, Merkliste und Ausschnitt-Downloads.

Die Merkliste wird ausschließlich lokal im Browser gespeichert. Die Website braucht kein Konto und keine externen Skripte, Schriftarten oder Bildserver.

## Bildrechte

Die Fotografien stammen von Unsplash, bezogen über Lorem Picsum. Die Originalquellen und Urheber stehen in `photos.json` und in jeder Bildansicht. Es gilt die [Unsplash-Lizenz](https://unsplash.com/license); die Rechte an den Fotos verbleiben bei den jeweiligen Urhebern. Die redaktionellen Bildtitel sind keine Ortsangaben. Zugeschnittene Downloads werden im Browser aus der jeweiligen Originaldatei erstellt.
