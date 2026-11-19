// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get appName => 'Oikoboard';

  @override
  String get commonCancel => 'Anuluj';

  @override
  String get commonSave => 'Zapisz';

  @override
  String get commonClose => 'Zamknij';

  @override
  String get commonDelete => 'Usuń';

  @override
  String get commonNext => 'Dalej';

  @override
  String get commonLogOut => 'Wyloguj';

  @override
  String get commonTryAgain => 'Spróbuj ponownie';

  @override
  String get commonCopy => 'Kopiuj';

  @override
  String get commonOpen => 'Otwórz';

  @override
  String get commonConnect => 'Połącz';

  @override
  String get commonNobody => 'Nikt';

  @override
  String get commonReadOnly => 'tylko odczyt';

  @override
  String get commonError => 'Błąd';

  @override
  String get commonNoServerConnection => 'Brak połączenia z serwerem';

  @override
  String commonDeleted(String name) {
    return 'Usunięto „$name”';
  }

  @override
  String get todoMarkDone => 'Oznacz jako zrobione';

  @override
  String get todoReopen => 'Oznacz jako niezrobione';

  @override
  String calendarsConfirmDisconnect(String account) {
    return 'Odłączyć $account?';
  }

  @override
  String get calendarsConfirmDisconnectBody =>
      'Jego kalendarze znikną z Oikoboard. Wydarzenia zostaną na koncie.';

  @override
  String get navWall => 'Ściana';

  @override
  String get dateToday => 'Dziś';

  @override
  String get dateTomorrow => 'Jutro';

  @override
  String get dateYesterday => 'Wczoraj';

  @override
  String get serverTitle => 'Serwer rodziny';

  @override
  String get serverIntro =>
      'Podaj adres serwera Oikoboard Twojej rodziny (np. oiko.example.com).';

  @override
  String get serverAddressLabel => 'Adres serwera';

  @override
  String get serverNotAnAddress => 'To nie wygląda na adres serwera.';

  @override
  String serverNotOikoboard(String url) {
    return 'Pod adresem $url nie odpowiada serwer Oikoboard.';
  }

  @override
  String get loginInviteBanner =>
      'Masz zaproszenie do rodziny — zaloguj się, żeby dołączyć.';

  @override
  String get loginTagline => 'Wspólna tablica rodziny.';

  @override
  String get loginServerUnreachable => 'Nie mogę połączyć się z serwerem.';

  @override
  String loginServerUnreachableAt(String url) {
    return 'Nie mogę połączyć się z serwerem ($url).';
  }

  @override
  String get loginWithGoogle => 'Zaloguj się przez Google';

  @override
  String get loginNoGoogle =>
      'Serwer nie ma skonfigurowanego logowania (OIKO_GOOGLE_CLIENT_ID).';

  @override
  String get loginDevMode => 'Tryb deweloperski';

  @override
  String get loginEmailField => 'E-mail (bez weryfikacji)';

  @override
  String get loginEnter => 'Wejdź';

  @override
  String loginServerChange(String host) {
    return 'Serwer: $host — zmień';
  }

  @override
  String get loginWhoAreYou => 'Kim jesteś? (tryb mock)';

  @override
  String get loginErrorStale =>
      'Logowanie zaczęło się w innym oknie — spróbuj ponownie.';

  @override
  String get loginErrorCancelled => 'Logowanie anulowane.';

  @override
  String get loginErrorFailed => 'Nie udało się zalogować przez Google.';

  @override
  String get onboardingHiNoName => 'Cześć!';

  @override
  String onboardingHiName(String name) {
    return 'Cześć, $name!';
  }

  @override
  String get onboardingCreateFamily => 'Załóż rodzinę';

  @override
  String get onboardingCreateFamilyHint =>
      'Potem zaprosisz resztę domowników linkiem.';

  @override
  String get onboardingFamilyName => 'Nazwa rodziny';

  @override
  String get onboardingFamilyNameHint => 'np. Kowalscy';

  @override
  String get onboardingMyName => 'Jak cię nazywać w rodzinie?';

  @override
  String get onboardingMyNameHint => 'np. Tata';

  @override
  String onboardingMyNameHintDefault(String name) {
    return 'np. Tata (domyślnie: $name)';
  }

  @override
  String get onboardingCreate => 'Załóż';

  @override
  String get onboardingHaveInvite => 'Masz zaproszenie?';

  @override
  String get onboardingInviteHint =>
      'Otwórz link od domownika albo wklej go tutaj.';

  @override
  String get onboardingInviteLink => 'Link z zaproszeniem';

  @override
  String get onboardingNotInviteLink => 'To nie wygląda na link z zaproszeniem';

  @override
  String onboardingBackTo(String family) {
    return 'Wróć do: $family';
  }

  @override
  String get onboardingDecline => 'Odrzuć';

  @override
  String get onboardingInvitation => 'Zaproszenie';

  @override
  String get onboardingInviteCheckFailed =>
      'Nie udało się sprawdzić zaproszenia.';

  @override
  String get onboardingFamilyInvitation => 'Zaproszenie do rodziny';

  @override
  String onboardingInvitedBy(String name) {
    return 'Zaprasza: $name';
  }

  @override
  String onboardingJoinAs(String name) {
    return 'Dołączysz jako: $name';
  }

  @override
  String get onboardingAlreadyMember => 'Już należysz do tej rodziny.';

  @override
  String get onboardingGoTo => 'Przejdź';

  @override
  String get onboardingJoin => 'Dołącz';

  @override
  String inviteTitle(String family) {
    return 'Zaproś do: $family';
  }

  @override
  String get inviteWhom => 'Kogo zapraszasz?';

  @override
  String get inviteNewPerson => 'Nową osobę';

  @override
  String get inviteNewPersonHint => 'Sama wybierze, jak ją nazywać';

  @override
  String get inviteMemberNoAccount => 'Jest w rodzinie, nie ma konta';

  @override
  String get inviteSendLink =>
      'Wyślij ten link domownikowi. Działa raz, przez 7 dni.';

  @override
  String get inviteCreateLink => 'Utwórz link';

  @override
  String get inviteLinkCopied => 'Skopiowano link';

  @override
  String get shellSimulatorStop => 'Zatrzymaj symulację rodziny';

  @override
  String get shellSimulatorStart => 'Symuluj zmiany od rodziny';

  @override
  String get shellAiChat => 'Czat AI (MCP)';

  @override
  String get shellInviteToFamily => 'Zaproś do rodziny';

  @override
  String get shellOffline => 'Brak połączenia — łączę ponownie…';

  @override
  String get wallGreetingMorning => 'Dzień dobry';

  @override
  String get wallGreetingDay => 'Cześć';

  @override
  String get wallGreetingEvening => 'Dobry wieczór';

  @override
  String wallGreeting(String greeting, String name) {
    return '$greeting, $name!';
  }

  @override
  String get aiTitle => 'ChatGPT, Claude i inne';

  @override
  String get aiDescription =>
      'Twoje zadania i kalendarz rodziny możesz podłączyć też do własnego czatu AI. Dodaj w nim konektor (MCP) z tym adresem — zalogujesz się kontem Oikoboard, a zmiany będą zapisywane jako Twoje.';

  @override
  String get aiCopyAddress => 'Kopiuj adres';

  @override
  String get aiAddressCopied => 'Skopiowano adres';

  @override
  String get aiNothingConnected => 'Nic nie jest podłączone.';

  @override
  String get aiNotUsedYet => 'Jeszcze nieużywane';

  @override
  String aiLastUsed(String when) {
    return 'Ostatnio: $when';
  }

  @override
  String get aiDisconnect => 'Odłącz';

  @override
  String get todoModuleTitle => 'Listy';

  @override
  String todoError(String error) {
    return 'Błąd: $error';
  }

  @override
  String get todoNoLists => 'Brak list — dodaj pierwszą.';

  @override
  String get todoNewList => 'Nowa lista';

  @override
  String get todoListChip => 'Lista';

  @override
  String get todoEditList => 'Edytuj listę';

  @override
  String todoMarkedDone(String title) {
    return 'Zrobione: „$title”';
  }

  @override
  String get commonUndo => 'Cofnij';

  @override
  String get todoCommentDeleted => 'Usunięto komentarz';

  @override
  String get todoWallFilter => 'Filtruj listy';

  @override
  String get todoWallFilterReset => 'Wyczyść';

  @override
  String get todoWallScopeAll => 'Wszystkie listy';

  @override
  String get todoWallScopeMyLists => 'Listy z moimi zadaniami';

  @override
  String get todoWallScopeMyTasks => 'Tylko moje zadania';

  @override
  String get todoWallFilterLists => 'Pokazuj listy';

  @override
  String get todoWallFilterEmpty => 'Nic nie pasuje do filtra';

  @override
  String get todoDescription => 'Opis';

  @override
  String get todoHasDescription => 'Ma opis';

  @override
  String get todoColor => 'Kolor';

  @override
  String get markdownEdit => 'Edycja';

  @override
  String get markdownPreview => 'Podgląd';

  @override
  String get markdownNothing => 'Nic do podglądu';

  @override
  String get todoDeleteList => 'Usuń listę';

  @override
  String get todoName => 'Nazwa';

  @override
  String todoAddTo(String list) {
    return 'Dodaj do „$list”…';
  }

  @override
  String get todoAllDone => 'Wszystko zrobione 🎉';

  @override
  String todoDoneSection(int count) {
    return 'Zrobione ($count)';
  }

  @override
  String todoOverdueSection(int count) {
    return 'Zaległe ($count)';
  }

  @override
  String todoTodaySection(int count) {
    return 'Dziś ($count)';
  }

  @override
  String get todoMineSection => 'Moje zadania';

  @override
  String todoOpenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count do zrobienia',
      many: '$count do zrobienia',
      few: '$count do zrobienia',
      one: '$count do zrobienia',
    );
    return '$_temp0';
  }

  @override
  String todoDue(String day) {
    return 'termin: $day';
  }

  @override
  String todoDueLabel(String day) {
    return 'Termin: $day';
  }

  @override
  String todoDayAt(String day, String time) {
    return '$day, $time';
  }

  @override
  String get todoSetTime => 'Dodaj godzinę';

  @override
  String get todoRemoveTime => 'Usuń godzinę';

  @override
  String get todoTask => 'Zadanie';

  @override
  String get todoWhoDoesIt => 'Kto się tym zajmie?';

  @override
  String get todoSetDue => 'Ustaw termin';

  @override
  String get todoRemoveDue => 'Usuń termin';

  @override
  String get todoComments => 'Komentarze';

  @override
  String get todoNoComments => 'Brak komentarzy';

  @override
  String todoCommentsOf(String title) {
    return 'Komentarze: $title';
  }

  @override
  String get todoCommentHint => 'Dodaj komentarz…';

  @override
  String get todoCommentSend => 'Wyślij';

  @override
  String get todoCommentDelete => 'Usuń komentarz';

  @override
  String get todoCommentFormerMember => 'Były członek';

  @override
  String get todoDayListDue => 'Termin listy';

  @override
  String get wallLayoutToday => 'Dziś';

  @override
  String get wallLayoutKanban => 'Tablica';

  @override
  String get calendarModuleTitle => 'Kalendarz';

  @override
  String get calendarViewDay => 'Dzień';

  @override
  String get calendarViewThreeDays => '3 dni';

  @override
  String get calendarViewWeek => 'Tydzień';

  @override
  String get calendarViewMonth => 'Miesiąc';

  @override
  String get calendarViewTooltip => 'Widok';

  @override
  String get calendarsTooltip => 'Kalendarze';

  @override
  String get calendarPrevDay => 'Poprzedni dzień';

  @override
  String get calendarPrevPeriod => 'Poprzedni okres';

  @override
  String get calendarPrevMonth => 'Poprzedni miesiąc';

  @override
  String get calendarNextDay => 'Następny dzień';

  @override
  String get calendarNextPeriod => 'Następny okres';

  @override
  String get calendarNextMonth => 'Następny miesiąc';

  @override
  String get calendarNewEvent => 'Nowe wydarzenie';

  @override
  String get calendarEvent => 'Wydarzenie';

  @override
  String get calendarConnectPrompt =>
      'Podłącz kalendarz Google — wydarzenia będą się synchronizować w obie strony.';

  @override
  String get calendarConnectAction => 'Podłącz kalendarz';

  @override
  String get calendarNoEvents => 'Brak wydarzeń';

  @override
  String get calendarSoon => 'Wkrótce';

  @override
  String get calendarWeekdayMon => 'Pn';

  @override
  String get calendarWeekdayTue => 'Wt';

  @override
  String get calendarWeekdayWed => 'Śr';

  @override
  String get calendarWeekdayThu => 'Cz';

  @override
  String get calendarWeekdayFri => 'Pt';

  @override
  String get calendarWeekdaySat => 'So';

  @override
  String get calendarWeekdaySun => 'Nd';

  @override
  String get calendarAllDay => 'Cały dzień';

  @override
  String calendarAllDaySpan(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Cały dzień · $days dni',
      many: 'Cały dzień · $days dni',
      few: 'Cały dzień · $days dni',
      one: 'Cały dzień · $days dzień',
    );
    return '$_temp0';
  }

  @override
  String calendarReadOnlyNotice(String name) {
    return 'Kalendarz „$name” jest tylko do odczytu.';
  }

  @override
  String get calendarTitleField => 'Tytuł';

  @override
  String get calendarLabel => 'Kalendarz';

  @override
  String get calendarRepeatField => 'Powtarzanie';

  @override
  String get calendarPlaceField => 'Miejsce';

  @override
  String get calendarDescriptionField => 'Opis';

  @override
  String get calendarWhoField => 'Kto';

  @override
  String get calendarRecurringChange => 'Zmień wydarzenie cykliczne';

  @override
  String get calendarRecurringDelete => 'Usuń wydarzenie cykliczne';

  @override
  String get calendarRecurringThisOnly => 'Tylko to wydarzenie';

  @override
  String get calendarRecurringSeries => 'Wszystkie wydarzenia z serii';

  @override
  String get calendarConnectCancelled => 'Anulowano podłączanie kalendarza.';

  @override
  String get calendarConnectFailed => 'Nie udało się podłączyć kalendarza.';

  @override
  String get repeatNone => 'Nie powtarza się';

  @override
  String get repeatDaily => 'Codziennie';

  @override
  String get repeatWeekdays => 'W dni robocze';

  @override
  String get repeatWeekly => 'Co tydzień';

  @override
  String get repeatMonthly => 'Co miesiąc';

  @override
  String get repeatYearly => 'Co rok';

  @override
  String get repeatCustom => 'Niestandardowo';

  @override
  String todoDaySheetTitle(String date) {
    return 'Zadania · $date';
  }

  @override
  String get todoDayEmpty => 'Brak zadań na ten dzień';

  @override
  String get calendarsTitle => 'Kalendarze rodziny';

  @override
  String get calendarsIntro =>
      'Wydarzenia są zapisywane w podłączonych kalendarzach (np. Google) — zmiany działają w obie strony. Zadania z terminem trafiają jako jeden wpis na dzień do kalendarza oznaczonego ✓.';

  @override
  String get calendarsNoneConnected =>
      'Żaden kalendarz nie jest jeszcze podłączony.';

  @override
  String get calendarsTodoTag => 'zadania z terminem';

  @override
  String get calendarsTodoTargetOn => 'Tu trafiają zadania z terminem';

  @override
  String get calendarsTodoTargetOff => 'Pokazuj tu zadania z terminem';

  @override
  String get calendarsSyncNow => 'Synchronizuj teraz';

  @override
  String get calendarsRemoveFromFamily => 'Odłącz od rodziny';

  @override
  String get calendarsYourAccounts => 'Twoje konta';

  @override
  String get calendarsConnectGoogle => 'Podłącz konto Google';

  @override
  String get calendarsAccessRevoked =>
      'Dostęp cofnięty — podłącz konto ponownie';

  @override
  String get calendarsTestAccount => 'konto testowe (mock)';

  @override
  String get calendarsLoadFailed => 'Nie udało się pobrać listy kalendarzy.';

  @override
  String get calendarsDisconnectAccount =>
      'Odłącz konto (usuwa jego kalendarze)';

  @override
  String syncPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Brak połączenia — $count zmiany czeka na wysłanie',
      many: 'Brak połączenia — $count zmian czeka na wysłanie',
      few: 'Brak połączenia — $count zmiany czekają na wysłanie',
      one: 'Brak połączenia — $count zmiana czeka na wysłanie',
    );
    return '$_temp0';
  }

  @override
  String syncFailedBadge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zmiany nie zostały zapisane',
      many: '$count zmian nie zostało zapisanych',
      few: '$count zmiany nie zostały zapisane',
      one: '$count zmiana nie została zapisana',
    );
    return '$_temp0';
  }

  @override
  String get syncUnsyncedTitle => 'Niezapisane zmiany';

  @override
  String get syncUnsyncedHint =>
      'Serwer odrzucił te zmiany. Spróbuj ponownie albo je odrzuć.';

  @override
  String syncFailedNotice(String what) {
    return 'Nie udało się zapisać: $what';
  }

  @override
  String get syncShow => 'Pokaż';

  @override
  String get syncRetry => 'Ponów';

  @override
  String get syncDiscard => 'Odrzuć';

  @override
  String syncAdd(String name) {
    return 'Dodanie „$name”';
  }

  @override
  String syncChange(String name) {
    return 'Zmiana „$name”';
  }

  @override
  String syncDelete(String name) {
    return 'Usunięcie „$name”';
  }

  @override
  String get syncUnnamed => 'bez nazwy';

  @override
  String syncServerSays(int status, String message) {
    return 'Serwer ($status): $message';
  }

  @override
  String syncDiffLine(String field, String before, String after) {
    return '$field: $before → $after';
  }

  @override
  String get todoInbox => 'Powiadomienia';

  @override
  String todoInboxUnread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Powiadomienia: $count nieprzeczytanego',
      many: 'Powiadomienia: $count nieprzeczytanych',
      few: 'Powiadomienia: $count nieprzeczytane',
      one: 'Powiadomienia: $count nieprzeczytane',
    );
    return '$_temp0';
  }

  @override
  String get todoInboxEmpty =>
      'Na razie pusto. Tu pojawią się wzmianki o Tobie, odpowiedzi w Twoich wątkach i przypisane Ci zadania.';

  @override
  String get todoInboxMarkAllRead => 'Oznacz wszystkie jako przeczytane';

  @override
  String todoInboxMention(String name, String title) {
    return '$name oznacza Cię w „$title”';
  }

  @override
  String todoInboxReply(String name, String title) {
    return '$name odpowiada w „$title”';
  }

  @override
  String todoInboxAssigned(String name, String title) {
    return '$name przypisuje Ci „$title”';
  }
}
