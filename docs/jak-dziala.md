# Jak działa fabryka — opowieść

Ten tekst opowiada słowami dwa diagramy z [how-it-works.md](how-it-works.md): najpierw całą fabrykę, potem jedno zadanie prześledzone od issue do zmergowanego PR. Najlepiej czytać go z diagramami otwartymi obok.

Opowieść opisuje **tryb kolejki**. W **trybie ręcznym** (`"use_labels": false`, `"auto_merge": false`) zmieniają się tylko dwie rzeczy, opisane na końcu w części 3.

## Część 1. Cała fabryka

Wyobraź sobie małą manufakturę, która pracuje u Ciebie na komputerze. Ma trzech pracowników: **planistę**, **wykonawcę** i **recenzenta**. Ma kierownika zmiany, czyli Twoją sesję Claude Code po wpisaniu `/factory run`. Kierownik sam niczego nie produkuje: rozdziela pracę, pilnuje kolejności i odpowiada za kontakt z Tobą. Jest jeszcze **bramkarz**, czyli skrypt `factory/bin/job`. Ma przy sobie regulamin i nie przepuści nikogo dalej bez kompletu papierów.

### Zamówienie

Wszystko zaczyna się od issue na GitHubie, czyli kartki z opisem, co ma powstać, np. „Dodaj tryb ciemny”. Fabryka nie bierze każdej kartki. Bierze tylko te z etykietą `factory`, a taką etykietę może przykleić wyłącznie ktoś z prawem zapisu do repozytorium. Dlatego obca osoba nie może podrzucić fabryce pracy. Jeśli zadanie czeka na inne, jeszcze otwarte issue („zablokowane przez…”), fabryka je odkłada i wraca do niego, gdy blokada zniknie.

Każde zamówienie dostaje własny warsztat: osobną gałąź `factory/<zadanie>` i osobny folder `.worktrees/<zadanie>/`. Kilka zadań może iść równolegle, domyślnie trzy, i żadne nie wchodzi w drogę drugiemu ani Twojej własnej pracy.

### SPEC: planista myśli, zanim ktokolwiek zacznie pracę

Najpierw do zadania siada **planista**. Czyta issue, `CLAUDE.md` projektu, pliki kontekstu (słownik, decyzje architektoniczne) i sam kod. Potem odpowiada sobie na trzy pytania.

**Czy to w ogóle budować?** Jeśli zadanie nie pasuje do projektu albo już istnieje, kończy się na **REJECTED**. Uzasadnienie trafia jako komentarz pod issue, etykieta `factory` znika i nie powstaje ani linijka kodu.

**Jak bardzo jest ryzykowne?** Każde zadanie dostaje ocenę `low`, `medium` albo `high`. Ta ocena zdecyduje na samym końcu, czy fabryka może sama wpuścić zmianę do projektu. Za ryzyko wysokie uważa się zawsze migracje danych, kasowanie danych użytkownika i bezpieczeństwo, a do tego wszystko, co projekt wpisał do swojego `factory/risk.md`.

**Czego nie da się rozstrzygnąć bez Ciebie?** Planista nie może zadać Ci pytania w trakcie pracy, więc je zbiera. Wszystkie naraz, każde z rekomendowaną odpowiedzią. Na koniec pisze plan: etapy, pliki do zmiany w każdym etapie i kryteria odbioru, które da się sprawdzić jako „prawda albo fałsz”.

### BRAMKA 1: jedyna rozmowa przed startem

Jeśli planista ma pytania, zadanie zatrzymuje się w **clarify**. To pierwsze z trzech miejsc, w których potrzebny jesteś Ty. Kierownik zadaje Ci wszystkie pytania za jednym posiedzeniem. Zwykle wystarczy kliknąć rekomendowaną odpowiedź. Odpowiedzi trafiają jako komentarz pod issue, więc decyzja zostaje zapisana także na GitHubie. Planista dostaje je z powrotem i poprawia plan. Gdyby z odpowiedzi wynikły nowe wątpliwości, rozmowa się powtarza.

Od tej chwili obowiązuje najważniejsza zasada fabryki: **do samego końca nikt Cię o nic nie zapyta.**

### BUILD: wykonawca przy warsztacie

**Wykonawca** dostaje gotowy plan i pracuje w swoim folderze. Pisze kod i testy, sam uruchamia checki projektu, commituje, wypycha gałąź i otwiera pull request w wersji roboczej (draft). Opis PR zawiera `Closes #<issue>`, więc zmergowanie PR zamknie też issue.

Drobne niejasności rozstrzyga sam, w duchu planu, i zapisuje je w raporcie. Ale jeśli plan okaże się nie do wykonania albo wymagałby decyzji, na której Ci zależy, nie improwizuje. Zgłasza **BLOCKED** i zadanie idzie prosto do bramki 2, o której za chwilę.

### GATE: kontrola jakości, której nie da się oszukać

Gdy wykonawca melduje „gotowe”, bramkarz najpierw sprawdza papiery: czy nic nie zostało niezacommitowane, czy gałąź jest wypchnięta, czy PR istnieje. Dopiero wtedy wpuszcza zadanie na **bramkę**.

Bramka uruchamia `factory/checks.sh`, czyli testy, lint i build Twojego projektu. Uruchamia go z Twojego głównego checkoutu, nie z gałęzi zadania. To kluczowy szczegół: wykonawca nie ma jak poprawić egzaminu, który właśnie zdaje. Bramka sprawdza też, czy nie ruszono plików chronionych: samej fabryki, checków i ustawień. Ich zmiana od razu oblewa rundę.

Jeśli coś nie przechodzi, zadanie wraca do wykonawcy z dokładnym logiem błędu. Ta pętla „budowa → kontrola” to **runda**.

### REVIEW: recenzent, który zakłada najgorsze

Gdy checki są zielone, PR czyta **recenzent**. Działa jak adwokat diabła: zakłada, że zmiana nie robi tego, co obiecuje, dopóki kod nie udowodni, że robi. Patrzy z dwóch niezależnych stron, a z Ponytailem z trzech:

- **Spec**: czy zmiana robi to, co mówi plan i Twoje odpowiedzi z bramki 1?
- **Standards**: czy trzyma się zasad zapisanych w projekcie?
- **Simplicity**: czy nie ma w niej czegoś zbędnego?

Każde znalezisko sprawdza w kodzie, zanim je zgłosi. Werdykt może brzmieć **PASS** (przepuściłbym to sam), **CHANGES** (są rzeczy do poprawy, wracamy do wykonawcy) albo **HUMAN** (plan i wynik rozjechały się tak, że tylko Ty możesz to rozstrzygnąć).

Rund jest najwyżej trzy (`max_rounds`). Fabryka nie będzie się kręcić w kółko bez końca.

### FINISH: kto wciska przycisk „merge”

Gdy recenzent da PASS, bramkarz zadaje ostatnie pytanie: **czy ryzyko jest na tyle niskie, że fabryka może zmergować sama?** Domyślnie dotyczy to zadań `low` i `medium`, i tylko wtedy, gdy projekt ma prawdziwe checki (`checks_configured: true`).

**Tak** → etap **MERGING**. Fabryka dociąga najnowszy `main` do gałęzi, jeszcze raz uruchamia checki, bo w międzyczasie ktoś mógł coś zmienić, i merguje PR. Issue się zamyka, warsztat jest sprzątany, zadanie ląduje w **MERGED**. Jeśli przy dociąganiu wyjdzie konflikt albo checki padną, fabryka nie zgaduje i przekazuje sprawę Tobie.

**Nie** (np. ryzyko `high`) → **AWAITING MERGE**. To drugie miejsce, w którym jesteś potrzebny. PR dostaje etykietę `factory:awaiting-merge` i komentarz: co dokładnie jest ryzykowne i co sprawdzić ręcznie. Mergujesz Ty. Możesz też zamiast tego dać uwagi, a wtedy zadanie wraca do wykonawcy.

### BRAMKA 2: gdy coś utknie

Trzecie miejsce na Twoją uwagę to **NEEDS HUMAN FEEDBACK**. Trafia tu zadanie, któremu skończyły się rundy, którego wykonawca zgłosił blokadę, którego recenzent poprosił o Twoją decyzję albo którego nie dało się zmergować.

Ważne jest to, co się wtedy **nie** dzieje: fabryka nie przerywa Ci pracy i nie zatrzymuje pozostałych zadań. Utknięte zadanie dostaje etykietę `factory:needs-human-feedback` i komentarz z wyjaśnieniem, a potem po prostu czeka. Kiedy masz chwilę, piszesz `/factory <co o tym myślisz>`. Zadanie dostaje świeży zapas rund i wraca do wykonawcy, a jeśli nie miało jeszcze PR, to do planisty. Możesz je też porzucić, a wtedy kończy jako REJECTED.

### Morał

Fabryka prosi o Twoją uwagę dokładnie w trzech momentach: **przed** pracą (pytania), **przy** zmianach ryzykownych (merge) i **gdy** coś utknie (feedback). Wszystko pomiędzy dzieje się samo, a każdy krok pilnuje bramkarz, który nie przepuści zadania dalej bez dowodu, że poprzedni krok naprawdę się udał.

## Część 2. Jedno zadanie od początku do końca: „Add dark mode”

Teraz zostawiamy mapę i idziemy za jednym zamówieniem krok po kroku. Numery w nawiasach to numery strzałek na drugim diagramie.

### Wieczór, jedno issue

Zakładasz na GitHubie issue numer 4: *„Add dark mode”* — aplikacja ma mieć tryb ciemny. Doklejasz etykietę `factory` (1), otwierasz Claude Code w projekcie i wpisujesz `/factory run` (2). Tyle Twojej roboty na razie.

Kierownik zagląda na GitHuba i pyta, jakie issue z etykietą `factory` czekają (3). Znajduje czwórkę. Zakłada dla niej teczkę `factory/jobs/004-add-dark-mode/`, gałąź `factory/004-add-dark-mode` i osobny folder `.worktrees/004-add-dark-mode` (4). Nazwa zadania to numer issue plus skrót tytułu. Od teraz wszystko, co dotyczy trybu ciemnego, dzieje się w tym folderze, a Twój własny checkout zostaje nietknięty.

### Planista czyta i ma dwie wątpliwości

Kierownik woła planistę (5). Ten czyta treść issue, `CLAUDE.md`, pliki kontekstu i kod aplikacji (6): gdzie są kolory, jak działa ustawianie motywu, gdzie aplikacja przechowuje ustawienia. Treść issue traktuje przy tym jak cytat, a nie polecenie: dowiaduje się z niej, czego ktoś chce, ale nie wykonuje niczego, co ktoś mógłby tam wpisać.

Werdykt planisty: **budujemy, ryzyko średnie** — zmiana dotknie kilku plików, ale niczego nie da się nią nieodwracalnie zepsuć. Są jednak dwie rzeczy, których z kodu nie wyczyta (7):

- Czy tryb ma **podążać za ustawieniem systemu**, czy być **przełącznikiem w aplikacji**?
- Czy wybór ma być **zapamiętany po restarcie**?

### Bramka 1: dwa kliknięcia

Kierownik zadaje Ci oba pytania naraz (8, 9). Przy każdym jest odpowiedź rekomendowana: „ustawienie systemu” i „tak, zapamiętaj”. Klikasz obie (10). Fabryka wkleja Twoje odpowiedzi jako komentarz pod issue 4 (11), więc za pół roku każdy zobaczy, kto i co zdecydował.

Planista dostaje odpowiedzi i poprawia plan (12). Zapisuje go w `context/004-add-dark-mode/plan.md` na gałęzi zadania: etapy, pliki w każdym etapie i kryteria odbioru w stylu „test X przechodzi”, „po restarcie aplikacja zostaje w trybie ciemnym”. Melduje: **gotowe, bez pytań** (13).

Od tej chwili nikt Cię o nic nie zapyta.

### Runda 1: wykonawca buduje, kontrola przepuszcza

Wykonawca dostaje plan (14). W swoim folderze pisze kod trybu ciemnego i testy, po drodze sam uruchamia checki (15). Potem wypycha gałąź i otwiera na GitHubie roboczy PR numer 12 z dopiskiem „Closes #4” (16). Melduje: **READY** (17).

Bramkarz sprawdza papiery: commity są, gałąź wypchnięta, PR istnieje. Bramka uruchamia `checks.sh` z Twojego głównego checkoutu (18). Testy, lint i build są zielone, żaden chroniony plik nie został ruszony: **GATE PASS** (19).

### Recenzent znajduje dziurę

Recenzent bierze PR 12 i porównuje go z planem i z Twoimi odpowiedziami (20). Tryb ciemny działa, kod jest zgodny z zasadami projektu — ale odpowiedziałeś „tak, zapamiętaj”, a ustawienie **nie jest zapisywane przy zamknięciu aplikacji**. Recenzent sprawdza to w kodzie, zanim to zgłosi, i oznacza jako znalezisko **wymagane**: **CHANGES** (21).

Ta recenzja zostaje w teczce zadania, w `round-1/review.md`, i widać ją na dashboardzie (22). Na GitHub nie trafia. I znów: nikt Cię nie pyta. Fabryka po prostu odsyła zadanie do poprawki.

### Runda 2: poprawka

Wykonawca czyta recenzję i dopisuje zapisywanie ustawienia (23). Wypycha poprawkę do tej samej gałęzi, więc PR 12 sam się aktualizuje (24), i melduje **READY** (25). Bramka znów puszcza checki: **PASS** (26, 27). Recenzent patrzy drugi raz (28): **PASS** (29). To dopiero druga z trzech dozwolonych rund.

### Finał: fabryka merguje sama

Ryzyko było średnie, a `auto_merge_max_risk` w konfiguracji to też średnie, więc fabryka może zmergować bez Ciebie. Zanim to zrobi, dociąga do gałęzi najnowszy `main` i uruchamia checki jeszcze raz (30). Ktoś mógł w międzyczasie coś zmienić i dwie zmiany, każda poprawna osobno, mogłyby razem coś zepsuć.

Wszystko zielone. Fabryka zdejmuje z PR 12 status roboczy i go merguje (31). GitHub widzi „Closes #4” i zamyka issue (32). Fabryka usuwa folder roboczy, a zadanie trafia do **MERGED** (33). Na koniec kierownik pisze Ci jedną linijkę: `004-add-dark-mode #4 merged PR #12` (34).

Wpisałeś jedno issue i kliknąłeś dwie odpowiedzi. Resztę zrobiła fabryka.

### Co mogło potoczyć się inaczej

- **Ryzyko wysokie** — gdyby tryb ciemny wymagał np. zmiany formatu zapisanych danych. Po drugim PASS fabryka nie merguje. PR dostaje etykietę `factory:awaiting-merge` i komentarz: co jest ryzykowne i co sprawdzić ręcznie. Mergujesz Ty.
- **Trzy rundy bez sukcesu**, wykonawca **zablokowany** albo recenzent mówiący **HUMAN**. Zadanie staje z etykietą `factory:needs-human-feedback` i komentarzem, dlaczego. Gdy odpiszesz `/factory 004: <Twoje uwagi>`, rusza nowa runda ze świeżym zapasem rund.
- **Planista odrzuca zadanie**, bo tryb ciemny już istnieje albo nie pasuje do projektu. Pod issue pojawia się wyjaśnienie, etykieta `factory` znika i nie powstaje kod.
- **Projekt nie ma jeszcze skonfigurowanych checków** (`checks_configured: false`). Fabryka niczego nie merguje sama, niezależnie od ryzyka: każdy PR czeka na Ciebie.

Wszystko to można śledzić na żywo przez `/factory dashboard` albo zapytać `/factory status`.

## Część 3. Tryb ręczny

Tryb ręczny to ta sama manufaktura z dwiema zmianami w regulaminie. Jest dla sytuacji, w których nie możesz albo nie chcesz przyklejać etykiet w repozytorium, na przykład w pracy, i dla tych, w których każdą zmianę chcesz wpuścić do projektu własnoręcznie.

**Pierwsza zmiana: nie ma skrzynki na zamówienia.** Fabryka nie przegląda GitHuba w poszukiwaniu kartek z etykietą `factory`. Zadanie zaczyna się tylko wtedy, gdy je wskażesz:

- `/factory run 123` bierze dowolne otwarte issue nr 123, bez żadnej etykiety;
- `/factory run "Dodaj eksport do CSV"` bierze Twój własny tekst, bez issue. Zadanie dostaje nazwę `t01-dodaj-eksport-do-csv`, Twoje odpowiedzi i notatki zostają w jego teczce, a PR nie ma dopisku „Closes”, bo nie ma czego zamykać.

Samo `/factory run` wznawia już rozpoczęte zadania i niczego nowego nie bierze. Fabryka nie tworzy i nie przykleja żadnej etykiety. Gdy zadanie utknie, dowiesz się o tym od kierownika, z `/factory status` albo z dashboardu, a jeśli zadanie ma już PR, także z komentarza pod nim.

**Druga zmiana: przycisk „merge” należy zawsze do Ciebie.** Planista dalej ocenia ryzyko, a recenzent dalej musi dać PASS. Ale na końcu bramkarz nie pyta już, czy fabryka może zmergować sama: odpowiedź brzmi zawsze „nie”. Każdy PR trafia do **AWAITING MERGE**, oznaczony jako gotowy do przejrzenia. W komentarzu jest ocena ryzyka i to, co warto sprawdzić. Mergujesz Ty albo odpisujesz `/factory <uwagi>`, a wtedy zadanie wraca do wykonawcy.

Wszystko inne zostaje jak było: pytania zebrane naraz przed startem, osobny worktree dla każdego zadania, checki uruchamiane z Twojego checkoutu, rundy recenzji i dashboard.
