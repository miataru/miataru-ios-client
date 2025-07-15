# MiataruAPIClient

Dieses Repository enthält ein Swift Package zur Nutzung der Miataru API sowie eine Beispielapplikation.

## Struktur

- `Sources/MiataruAPIClient/` – Das eigentliche Swift Package (Library)
- `Examples/MiataruTestApp/` – Beispielapplikation und Dockerfile

## Nutzung als Swift Package in Xcode

1. Öffne dein Xcode-Projekt.
2. Wähle im Menü: **File > Add Packages...**
3. Gib den lokalen Pfad zu diesem Ordner oder das Git-Repository an.
4. Füge das Produkt **MiataruAPIClient** als Abhängigkeit hinzu.
5. Importiere das Package in deinem Code:
   ```swift
   import MiataruAPIClient
   ```

## Beispielapplikation lokal ausführen

```bash
cd Examples/MiataruTestApp
swift run
```

## Beispielapplikation mit Docker ausführen (aus Projekt-Root)

```bash
docker build -f Examples/MiataruTestApp/Dockerfile -t miataru-testapp .
docker run -it --rm miataru-testapp
```

## Hinweise
- Die Beispielapplikation sendet und liest Testdaten von https://service.miataru.com.
- Passe ggf. die Device-IDs in `main.swift` an.
- Die Library kann in eigenen Swift-Projekten verwendet werden. 