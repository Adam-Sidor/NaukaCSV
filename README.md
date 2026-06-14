# QuizApp – Tryb Nauki

Prosta aplikacja iOS do nauki z plików CSV. Pozwala wczytać zestawy pytań wielokrotnego wyboru i losowo je przeglądać z możliwością sprawdzania odpowiedzi.

---

## Wymagania

- Xcode 15+
- iOS 16+
- Pakiet [SwiftCSV](https://github.com/swiftcsv/SwiftCSV) (dodawany przez Swift Package Manager)

## Instalacja

1. Utwórz nowy projekt w Xcode: **File → New → Project → App (SwiftUI)**
2. Dodaj pakiet SwiftCSV: **File → Add Package Dependencies**
   - URL: `https://github.com/swiftcsv/SwiftCSV`
3. Zastąp zawartość domyślnego pliku `ContentView.swift` kodem z `QuizApp.swift` (lub wklej go jako nowy plik i usuń stary)
4. Jeśli Xcode wygenerował osobny plik `QuizLearningApp.swift`, usuń go — punkt wejścia `@main` znajduje się już w `QuizApp.swift`

---

## Format pliku CSV

Plik musi mieć 6 kolumn rozdzielonych przecinkami:

```
pytanie,odp1,odp2,odp3,odp4,poprawne
```

| Kolumna    | Opis                                                        |
|------------|-------------------------------------------------------------|
| `pytanie`  | Treść pytania                                               |
| `odp1–4`   | Cztery odpowiedzi (pusta lub `brak` jeśli opcja nie istnieje) |
| `poprawne` | Indeks poprawnej odpowiedzi (od 1); kilka: `"1,3"`          |

### Przykłady

```csv
pytanie,odp1,odp2,odp3,odp4,poprawne
Stolica Polski?,Kraków,Warszawa,Gdańsk,Łódź,2
Co to jest owoc?,Jabłko,Marchew,Gruszka,Ziemniak,"1,3"
Pytanie z 3 opcjami?,Opcja A,Opcja B,Opcja C,,3
```

> Pola zawierające przecinki powinny być objęte cudzysłowami.  
> Wiersz nagłówkowy (`pytanie,odp1,...`) jest opcjonalny — aplikacja go pomija automatycznie.

---

## Funkcje

### Ekran główny
- Lista wczytanych zestawów pytań z nazwą, liczbą pytań i datą dodania
- Przycisk **+** otwiera formularz dodawania nowego zestawu
- Swipe w lewo na zestawie → usunięcie go
- Zestawy są zapisywane lokalnie i dostępne po ponownym uruchomieniu aplikacji

### Dodawanie zestawu
- Wpisz nazwę zestawu (jeśli pole jest puste, zostanie wypełnione nazwą pliku)
- Wybierz plik CSV z dysku urządzenia
- Aplikacja pokazuje liczbę wczytanych pytań lub komunikat o błędzie

### Tryb nauki
- **Losuj** – losuje pytanie i wyświetla odpowiedzi w losowej kolejności (A, B, C lub A, B, C, D)
- **Pokaż odpowiedź** – zaznacza poprawne odpowiedzi na zielono
- **Ukryj odpowiedź** – chowa zaznaczenie (ten sam przycisk)
- Odpowiedzi oznaczone jako `brak` nie są wyświetlane
- Obsługa pytań z wieloma poprawnymi odpowiedziami

---

## Przygotowanie pliku CSV

Jeśli plik CSV zawiera błędy formatowania (przecinki w odpowiedziach bez cudzysłowów, zawijanie wierszy), można go naprawić dołączonym skryptem Python:

```bash
python3 fix_csv.py ios.csv ios_fixed.csv
```

Skrypt:
- scala fizycznie podzielone wiersze
- scala fragmenty odpowiedzi rozbitych przez przecinki
- zastępuje puste odpowiedzi tekstem `brak`
- zapisuje poprawny plik z cudzysłowami wokół każdego pola
