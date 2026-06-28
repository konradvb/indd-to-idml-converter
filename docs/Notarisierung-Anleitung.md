# App von Apple verifizieren lassen (Notarisierung)

Diese Anleitung bringt die App in den Zustand, dass sie auf **jedem Mac per Doppelklick** öffnet — ohne den „Rechtsklick → Öffnen"-Trick und ohne die Warnung „nicht verifizierter Entwickler". Das nennt sich **Notarisierung**: Du signierst die App mit deinem Entwickler-Zertifikat und Apple prüft sie automatisch auf Schadsoftware.

> **Wichtig:** Das ist **nicht** der App Store. Die App bleibt frei über GitHub verteilbar. Notarisierung ist nur Apples Sicherheits-Stempel für Apps außerhalb des Stores.

---

## Was du einmalig brauchst

### Voraussetzung: bezahlte Developer-Mitgliedschaft
Notarisierung braucht das **Apple Developer Program** (99 $/Jahr).
Prüfen/abschließen unter: https://developer.apple.com/account → falls nötig „Join the Apple Developer Program".

*(Ein kostenloser Apple-Account reicht **nicht** — damit gibt es kein „Developer ID"-Zertifikat.)*

---

### Schritt 1 — „Developer ID Application"-Zertifikat erstellen

Das ist ein spezielles Zertifikat zum Signieren von Apps außerhalb des Stores.

1. **Xcode** öffnen → Menü **Xcode → Settings…** (⌘,)
2. Reiter **Accounts** → links deine Apple ID auswählen
   *(falls noch nicht da: „+" → Apple ID hinzufügen)*
3. Knopf **Manage Certificates…** (unten rechts)
4. Unten links auf **„+"** → **„Developer ID Application"** wählen
5. Das Zertifikat erscheint in der Liste → **Fertig.**

> Ist „Developer ID Application" **ausgegraut**, bist du noch nicht im bezahlten Programm (siehe Voraussetzung).

**Kontrolle im Terminal** (`!` davor führt es hier in der Sitzung aus):
```
! security find-identity -v -p codesigning
```
In der Liste muss eine Zeile **„Developer ID Application: Konrad von Bruchhausen (…)"** stehen.

---

### Schritt 2 — App-spezifisches Passwort anlegen

Damit darf das Notar-Tool sich in deinem Namen bei Apple anmelden, ohne dein echtes Passwort zu kennen.

1. https://appleid.apple.com öffnen → anmelden
2. **Anmeldung & Sicherheit → App-spezifische Passwörter**
3. **„Passwort erstellen"** → Name z. B. `INDD Notar` → Apple zeigt dir ein Passwort wie `abcd-efgh-ijkl-mnop`
4. Dieses Passwort **kopieren** (du brauchst es gleich einmal).

---

### Schritt 3 — Zugangsdaten in die Keychain legen

Einmalig speichern, danach läuft alles automatisch. Im Terminal (mit `!` davor):

```
! xcrun notarytool store-credentials INDD-Notary --apple-id kvbruchhausen@gmail.com --team-id YPTLHJD4XZ
```

- Es fragt nach dem **App-spezifischen Passwort** aus Schritt 2 → einfügen, Enter.
- `INDD-Notary` ist der Profilname (genau so lassen — das Skript erwartet ihn).

---

## Bei jedem Release: ein Befehl

Im Projektordner:

```
! ./notarize.sh
```

Das Skript macht automatisch:
1. App neu bauen und mit deiner **Developer ID** signieren (Hardened Runtime)
2. An Apples **Notar-Dienst** schicken und warten (meist 1–5 Min.)
3. Den **Notar-Stempel** an die App und die DMG anheften
4. Fertige Datei ablegen: **`dist/INDDConverter.dmg`**

Wenn am Ende `✅ Done. Notarized disk image:` steht, ist alles fertig.

---

## Prüfen, dass es geklappt hat

```
! spctl -a -vvv -t install /pfad/zur/INDDConverter.app
```
Antwort sollte enthalten: **`source=Notarized Developer ID`** und **`accepted`**.

---

## Die notarisierte DMG auf GitHub stellen

```
! gh release upload v1.0 dist/INDDConverter.dmg --clobber
```
*(ersetzt die bisherige DMG im Release durch die notarisierte Version)*

Ab jetzt: Andere laden die DMG, ziehen die App auf „Programme" und öffnen sie mit **normalem Doppelklick** — keine Warnung mehr.

---

## Häufige Stolpersteine

| Meldung | Ursache / Lösung |
|---------|------------------|
| „Developer ID Application" ausgegraut in Xcode | Bezahlte Developer-Mitgliedschaft fehlt |
| `notarytool` sagt „No Keychain item" | Schritt 3 nicht ausgeführt / falscher Profilname |
| Notarisierung „Invalid" | Meist fehlt Hardened Runtime oder eine Signatur an einer eingebetteten Datei — `notarize.sh` setzt das schon korrekt; bei Fehlern den Log mit `xcrun notarytool log <id> --keychain-profile INDD-Notary` ansehen |
| App startet, aber InDesign-Steuerung wird blockiert | Das `com.apple.security.automation.apple-events`-Entitlement ist gesetzt (Config/INDDConverter.entitlements) — beim ersten Mal fragt macOS einmal „darf INDDConverter InDesign steuern?" → erlauben |

---

## Was kostet das?

- **Apple Developer Program:** 99 $/Jahr (das ist alles)
- **Notarisierung selbst:** kostenlos, beliebig oft
