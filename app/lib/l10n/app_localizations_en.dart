// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Oikoboard';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonClose => 'Close';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonNext => 'Next';

  @override
  String get commonLogOut => 'Log out';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonOpen => 'Open';

  @override
  String get commonConnect => 'Connect';

  @override
  String get commonNobody => 'Nobody';

  @override
  String get commonReadOnly => 'read-only';

  @override
  String get commonError => 'Error';

  @override
  String get commonNoServerConnection => 'No connection to the server';

  @override
  String commonDeleted(String name) {
    return 'Deleted “$name”';
  }

  @override
  String get todoMarkDone => 'Mark done';

  @override
  String get todoReopen => 'Mark not done';

  @override
  String calendarsConfirmDisconnect(String account) {
    return 'Disconnect $account?';
  }

  @override
  String get calendarsConfirmDisconnectBody =>
      'Its calendars will disappear from Oikoboard. Events stay in the account.';

  @override
  String get navWall => 'Wall';

  @override
  String get dateToday => 'Today';

  @override
  String get dateTomorrow => 'Tomorrow';

  @override
  String get dateYesterday => 'Yesterday';

  @override
  String get serverTitle => 'Family server';

  @override
  String get serverIntro =>
      'Enter the address of your family’s Oikoboard server (e.g. oiko.example.com).';

  @override
  String get serverAddressLabel => 'Server address';

  @override
  String get serverNotAnAddress => 'That doesn’t look like a server address.';

  @override
  String serverNotOikoboard(String url) {
    return 'No Oikoboard server responds at $url.';
  }

  @override
  String get loginInviteBanner =>
      'You have a family invitation — log in to join.';

  @override
  String get loginTagline => 'The family’s shared board.';

  @override
  String get loginServerUnreachable => 'Can’t connect to the server.';

  @override
  String loginServerUnreachableAt(String url) {
    return 'Can’t connect to the server ($url).';
  }

  @override
  String get loginWithGoogle => 'Log in with Google';

  @override
  String get loginNoGoogle =>
      'The server has no login configured (OIKO_GOOGLE_CLIENT_ID).';

  @override
  String get loginDevMode => 'Developer mode';

  @override
  String get loginEmailField => 'Email (unverified)';

  @override
  String get loginEnter => 'Enter';

  @override
  String loginServerChange(String host) {
    return 'Server: $host — change';
  }

  @override
  String get loginWhoAreYou => 'Who are you? (mock mode)';

  @override
  String get loginErrorStale =>
      'The login started in another window — try again.';

  @override
  String get loginErrorCancelled => 'Login cancelled.';

  @override
  String get loginErrorFailed => 'Couldn’t log in with Google.';

  @override
  String get onboardingHiNoName => 'Hi!';

  @override
  String onboardingHiName(String name) {
    return 'Hi, $name!';
  }

  @override
  String get onboardingCreateFamily => 'Create a family';

  @override
  String get onboardingCreateFamilyHint =>
      'You’ll invite the rest of the household with a link later.';

  @override
  String get onboardingFamilyName => 'Family name';

  @override
  String get onboardingFamilyNameHint => 'e.g. Smiths';

  @override
  String get onboardingMyName => 'What should we call you in the family?';

  @override
  String get onboardingMyNameHint => 'e.g. Dad';

  @override
  String onboardingMyNameHintDefault(String name) {
    return 'e.g. Dad (default: $name)';
  }

  @override
  String get onboardingCreate => 'Create';

  @override
  String get onboardingHaveInvite => 'Have an invitation?';

  @override
  String get onboardingInviteHint =>
      'Open the link from a household member or paste it here.';

  @override
  String get onboardingInviteLink => 'Invitation link';

  @override
  String get onboardingNotInviteLink =>
      'This doesn’t look like an invitation link.';

  @override
  String onboardingBackTo(String family) {
    return 'Back to: $family';
  }

  @override
  String get onboardingDecline => 'Decline';

  @override
  String get onboardingInvitation => 'Invitation';

  @override
  String get onboardingInviteCheckFailed => 'Couldn’t check the invitation.';

  @override
  String get onboardingFamilyInvitation => 'Family invitation';

  @override
  String onboardingInvitedBy(String name) {
    return 'Invited by: $name';
  }

  @override
  String onboardingJoinAs(String name) {
    return 'You’ll join as: $name';
  }

  @override
  String get onboardingAlreadyMember => 'You already belong to this family.';

  @override
  String get onboardingGoTo => 'Go to family';

  @override
  String get onboardingJoin => 'Join';

  @override
  String inviteTitle(String family) {
    return 'Invite to: $family';
  }

  @override
  String get inviteWhom => 'Who are you inviting?';

  @override
  String get inviteNewPerson => 'A new person';

  @override
  String get inviteNewPersonHint => 'They’ll choose their own name';

  @override
  String get inviteMemberNoAccount => 'Already in the family, no account';

  @override
  String get inviteSendLink =>
      'Send this link to the household member. It works once, for 7 days.';

  @override
  String get inviteCreateLink => 'Create link';

  @override
  String get inviteLinkCopied => 'Link copied';

  @override
  String get shellSimulatorStop => 'Stop family simulation';

  @override
  String get shellSimulatorStart => 'Simulate changes from the family';

  @override
  String get shellAiChat => 'AI chat (MCP)';

  @override
  String get shellInviteToFamily => 'Invite to family';

  @override
  String get shellOffline => 'No connection — reconnecting…';

  @override
  String get wallGreetingMorning => 'Good morning';

  @override
  String get wallGreetingDay => 'Hi';

  @override
  String get wallGreetingEvening => 'Good evening';

  @override
  String wallGreeting(String greeting, String name) {
    return '$greeting, $name!';
  }

  @override
  String get aiTitle => 'ChatGPT, Claude and others';

  @override
  String get aiDescription =>
      'You can also connect your family’s tasks and calendar to your own AI chat. Add a connector (MCP) with this address there — you’ll log in with your Oikoboard account, and changes will be saved as yours.';

  @override
  String get aiCopyAddress => 'Copy address';

  @override
  String get aiAddressCopied => 'Address copied';

  @override
  String get aiNothingConnected => 'Nothing is connected.';

  @override
  String get aiNotUsedYet => 'Not used yet';

  @override
  String aiLastUsed(String when) {
    return 'Last used: $when';
  }

  @override
  String get aiDisconnect => 'Disconnect';

  @override
  String get todoModuleTitle => 'Lists';

  @override
  String todoError(String error) {
    return 'Error: $error';
  }

  @override
  String get todoNoLists => 'No lists — add the first one.';

  @override
  String get todoNewList => 'New list';

  @override
  String get todoListChip => 'List';

  @override
  String get todoEditList => 'Edit list';

  @override
  String todoMarkedDone(String title) {
    return 'Done: “$title”';
  }

  @override
  String get commonUndo => 'Undo';

  @override
  String get todoCommentDeleted => 'Comment deleted';

  @override
  String get todoWallFilter => 'Filter lists';

  @override
  String get todoWallFilterReset => 'Reset';

  @override
  String get todoWallScopeAll => 'All lists';

  @override
  String get todoWallScopeMyLists => 'Lists with my tasks';

  @override
  String get todoWallScopeMyTasks => 'Only my tasks';

  @override
  String get todoWallFilterLists => 'Show lists';

  @override
  String get todoWallFilterEmpty => 'Nothing matches the filter';

  @override
  String get todoDescription => 'Description';

  @override
  String get todoHasDescription => 'Has a description';

  @override
  String get todoFromRecurring => 'Created from a recurring task';

  @override
  String get todoHasComments => 'Has comments';

  @override
  String get todoColor => 'Color';

  @override
  String get markdownEdit => 'Edit';

  @override
  String get markdownPreview => 'Preview';

  @override
  String get markdownNothing => 'Nothing to preview';

  @override
  String get linkOpen => 'Open link';

  @override
  String get linkCopy => 'Copy link';

  @override
  String get linkCopied => 'Link copied';

  @override
  String get todoDeleteList => 'Delete list';

  @override
  String get todoName => 'Name';

  @override
  String todoAddTo(String list) {
    return 'Add to “$list”…';
  }

  @override
  String get todoAllDone => 'All done 🎉';

  @override
  String todoDoneSection(int count) {
    return 'Done ($count)';
  }

  @override
  String todoOverdueSection(int count) {
    return 'Overdue ($count)';
  }

  @override
  String todoTodaySection(int count) {
    return 'Today ($count)';
  }

  @override
  String get todoMineSection => 'My tasks';

  @override
  String todoOpenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count to do',
      one: '$count to do',
    );
    return '$_temp0';
  }

  @override
  String todoDue(String day) {
    return 'due: $day';
  }

  @override
  String todoDueLabel(String day) {
    return 'Due: $day';
  }

  @override
  String todoDayAt(String day, String time) {
    return '$day, $time';
  }

  @override
  String get todoSetTime => 'Add time';

  @override
  String get todoRemoveTime => 'Remove time';

  @override
  String get todoTask => 'Task';

  @override
  String get todoWhoDoesIt => 'Who will do it?';

  @override
  String get todoSetDue => 'Set due date';

  @override
  String get todoRemoveDue => 'Remove due date';

  @override
  String get todoComments => 'Comments';

  @override
  String get todoNoComments => 'No comments yet';

  @override
  String todoCommentsOf(String title) {
    return 'Comments: $title';
  }

  @override
  String get todoCommentHint => 'Add a comment…';

  @override
  String get todoCommentSend => 'Send';

  @override
  String get todoCommentDelete => 'Delete comment';

  @override
  String get todoCommentFormerMember => 'Former member';

  @override
  String get todoDayListDue => 'List due';

  @override
  String get calendarModuleTitle => 'Calendar';

  @override
  String get calendarViewDay => 'Day';

  @override
  String get calendarViewThreeDays => '3 days';

  @override
  String get calendarViewWeek => 'Week';

  @override
  String get calendarViewMonth => 'Month';

  @override
  String get calendarViewTooltip => 'View';

  @override
  String get calendarsTooltip => 'Calendars';

  @override
  String get calendarPrevDay => 'Previous day';

  @override
  String get calendarPrevPeriod => 'Previous period';

  @override
  String get calendarPrevMonth => 'Previous month';

  @override
  String get calendarNextDay => 'Next day';

  @override
  String get calendarNextPeriod => 'Next period';

  @override
  String get calendarNextMonth => 'Next month';

  @override
  String get calendarNewEvent => 'New event';

  @override
  String get calendarEvent => 'Event';

  @override
  String get calendarConnectPrompt =>
      'Connect a Google calendar — events will sync both ways.';

  @override
  String get calendarConnectAction => 'Connect calendar';

  @override
  String get calendarNoEvents => 'No events';

  @override
  String get calendarSoon => 'Coming up';

  @override
  String get calendarWeekdayMon => 'Mon';

  @override
  String get calendarWeekdayTue => 'Tue';

  @override
  String get calendarWeekdayWed => 'Wed';

  @override
  String get calendarWeekdayThu => 'Thu';

  @override
  String get calendarWeekdayFri => 'Fri';

  @override
  String get calendarWeekdaySat => 'Sat';

  @override
  String get calendarWeekdaySun => 'Sun';

  @override
  String get calendarAllDay => 'All day';

  @override
  String calendarAllDaySpan(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'All day · $days days',
      one: 'All day · $days day',
    );
    return '$_temp0';
  }

  @override
  String calendarReadOnlyNotice(String name) {
    return 'Calendar “$name” is read-only.';
  }

  @override
  String get calendarTitleField => 'Title';

  @override
  String get calendarLabel => 'Calendar';

  @override
  String get calendarRepeatField => 'Repeat';

  @override
  String get calendarPlaceField => 'Place';

  @override
  String get calendarDescriptionField => 'Description';

  @override
  String get calendarWhoField => 'Who';

  @override
  String get calendarRecurringChange => 'Change recurring event';

  @override
  String get calendarRecurringDelete => 'Delete recurring event';

  @override
  String get calendarRecurringThisOnly => 'This event only';

  @override
  String get calendarRecurringSeries => 'All events in the series';

  @override
  String get calendarConnectCancelled => 'Calendar connection cancelled.';

  @override
  String get calendarConnectFailed => 'Couldn’t connect the calendar.';

  @override
  String get repeatNone => 'Doesn’t repeat';

  @override
  String get repeatDaily => 'Daily';

  @override
  String get repeatWeekdays => 'Weekdays';

  @override
  String get repeatWeekly => 'Weekly';

  @override
  String get repeatMonthly => 'Monthly';

  @override
  String get repeatYearly => 'Yearly';

  @override
  String get repeatCustom => 'Custom';

  @override
  String todoDaySheetTitle(String date) {
    return 'Tasks · $date';
  }

  @override
  String get todoDayEmpty => 'No tasks for this day';

  @override
  String get calendarsTitle => 'Family calendars';

  @override
  String get calendarsIntro =>
      'Events are saved to the connected calendars (e.g. Google) — changes work both ways. Tasks with a due date go into the calendar marked ✓ as one entry per day.';

  @override
  String get calendarsNoneConnected => 'No calendar is connected yet.';

  @override
  String get calendarsTodoTag => 'tasks with a due date';

  @override
  String get calendarsTodoTargetOn => 'Tasks with a due date go here';

  @override
  String get calendarsTodoTargetOff => 'Show tasks with a due date here';

  @override
  String get calendarsSyncNow => 'Sync now';

  @override
  String get calendarsRemoveFromFamily => 'Remove from family';

  @override
  String get calendarsYourAccounts => 'Your accounts';

  @override
  String get calendarsConnectGoogle => 'Connect Google account';

  @override
  String get calendarsAccessRevoked =>
      'Access revoked — connect the account again';

  @override
  String get calendarsTestAccount => 'test account (mock)';

  @override
  String get calendarsLoadFailed => 'Couldn’t fetch the list of calendars.';

  @override
  String get calendarsDisconnectAccount =>
      'Disconnect account (removes its calendars)';

  @override
  String syncPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'No connection — $count changes waiting to be sent',
      one: 'No connection — $count change waiting to be sent',
    );
    return '$_temp0';
  }

  @override
  String syncFailedBadge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes weren’t saved',
      one: '$count change wasn’t saved',
    );
    return '$_temp0';
  }

  @override
  String get syncUnsyncedTitle => 'Unsynced changes';

  @override
  String get syncUnsyncedHint =>
      'The server rejected these changes. Retry them or discard them.';

  @override
  String syncFailedNotice(String what) {
    return 'Couldn’t save: $what';
  }

  @override
  String get syncShow => 'Show';

  @override
  String get syncRetry => 'Retry';

  @override
  String get syncDiscard => 'Discard';

  @override
  String syncAdd(String name) {
    return 'Add “$name”';
  }

  @override
  String syncChange(String name) {
    return 'Change “$name”';
  }

  @override
  String syncDelete(String name) {
    return 'Delete “$name”';
  }

  @override
  String get syncUnnamed => 'untitled';

  @override
  String syncServerSays(int status, String message) {
    return 'Server ($status): $message';
  }

  @override
  String syncDiffLine(String field, String before, String after) {
    return '$field: $before → $after';
  }

  @override
  String get todoInbox => 'Inbox';

  @override
  String todoInboxUnread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Inbox: $count unread',
      one: 'Inbox: $count unread',
    );
    return '$_temp0';
  }

  @override
  String get todoInboxEmpty =>
      'Nothing here yet. Mentions, replies in your threads and tasks assigned to you show up here.';

  @override
  String get todoInboxMarkAllRead => 'Mark all as read';

  @override
  String todoInboxMention(String name, String title) {
    return '$name mentioned you in “$title”';
  }

  @override
  String todoInboxReply(String name, String title) {
    return '$name replied in “$title”';
  }

  @override
  String todoInboxRecurring(String title) {
    return 'Recurring task for you: “$title”';
  }

  @override
  String todoInboxAssigned(String name, String title) {
    return '$name assigned you “$title”';
  }

  @override
  String get searchTooltip => 'Search';

  @override
  String get searchHint => 'Search tasks, lists and events';

  @override
  String get searchNothingFound => 'Nothing found';

  @override
  String get searchFailed => 'Search needs a connection to the server';

  @override
  String get todoSearchList => 'List';

  @override
  String get todoSearchDone => 'Done';

  @override
  String get todoNewTask => 'New task';

  @override
  String get attachAction => 'Attach';

  @override
  String get attachTakePhoto => 'Take a photo';

  @override
  String get attachPhotos => 'Photos';

  @override
  String get attachFiles => 'Files';

  @override
  String attachStorage(String used, String quota) {
    return 'Family storage: $used of $quota used';
  }

  @override
  String attachTooLarge(String name, String max) {
    return '“$name” is larger than $max';
  }

  @override
  String attachStorageFull(String name) {
    return 'The family storage is full — “$name” wasn’t uploaded';
  }

  @override
  String attachUploadFailed(String name) {
    return 'Couldn’t upload “$name”';
  }

  @override
  String get attachRemove => 'Remove';

  @override
  String get attachDownload => 'Download';

  @override
  String get attachOpenFailed => 'Couldn’t open the file';

  @override
  String get attachUnavailableInDemo => 'Files can’t be opened in the demo';

  @override
  String get attachments => 'Attachments';

  @override
  String todoMovedTo(String list) {
    return 'Moved to “$list”';
  }

  @override
  String get recurringTitle => 'Recurring tasks';

  @override
  String get recurringEmpty =>
      'No recurring tasks yet. They add a new task to this list on a schedule — for example every Monday and Friday.';

  @override
  String get recurringNew => 'New recurring task';

  @override
  String get recurringEdit => 'Edit recurring task';

  @override
  String recurringNext(String date) {
    return 'Next: $date';
  }

  @override
  String get recurringNoNext => 'No upcoming occurrences';

  @override
  String get recurringPaused => 'Paused';

  @override
  String get recurringActive => 'Active';

  @override
  String get recurringRepeat => 'Repeat';

  @override
  String get recurDailyChip => 'Daily';

  @override
  String get recurWeeklyChip => 'Weekly';

  @override
  String get recurMonthlyChip => 'Monthly';

  @override
  String get recurYearlyChip => 'Yearly';

  @override
  String get recurEvery => 'Every';

  @override
  String recurUnitDay(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return '$_temp0';
  }

  @override
  String recurUnitWeek(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'weeks',
      one: 'week',
    );
    return '$_temp0';
  }

  @override
  String recurUnitMonth(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'months',
      one: 'month',
    );
    return '$_temp0';
  }

  @override
  String recurUnitYear(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'years',
      one: 'year',
    );
    return '$_temp0';
  }

  @override
  String recurOnDay(int day) {
    return 'On day $day';
  }

  @override
  String get recurLastDay => 'Last day of the month';

  @override
  String recurDaily(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Every $n days',
      one: 'Every day',
    );
    return '$_temp0';
  }

  @override
  String recurWeekly(int n, String days) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Every $n weeks on $days',
      one: 'Every week on $days',
    );
    return '$_temp0';
  }

  @override
  String recurMonthlyDay(int n, int day) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Every $n months on day $day',
      one: 'Every month on day $day',
    );
    return '$_temp0';
  }

  @override
  String recurMonthlyLast(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Every $n months on the last day',
      one: 'Every month on the last day',
    );
    return '$_temp0';
  }

  @override
  String recurYearly(int n, String date) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Every $n years on $date',
      one: 'Every year on $date',
    );
    return '$_temp0';
  }

  @override
  String recurCustomRule(String rrule) {
    return 'Custom schedule ($rrule)';
  }

  @override
  String get recurNoEnd => 'Remove end date';

  @override
  String get recurDue => 'Due';

  @override
  String get recurDueNone => 'No due date';

  @override
  String get recurDueSameDay => 'Same day';

  @override
  String get recurDueAfter => 'After some days';

  @override
  String recurDueDays(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n days after creation',
      one: '1 day after creation',
    );
    return '$_temp0';
  }

  @override
  String get recurDueDaysField => 'Days after creation';

  @override
  String get recurNextOccurrences => 'Next occurrences';

  @override
  String recurFirstDue(String date) {
    return 'The first task will be due $date';
  }

  @override
  String get recurPreviewFailed => 'Can\'t compute the preview right now';

  @override
  String get recurNoOccurrences => 'This schedule has no occurrences';

  @override
  String get recurWeekdays => 'Weekdays';

  @override
  String recurDeleteTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get recurDeleteMessage => 'Tasks it already created stay.';

  @override
  String recurStartsOn(String date) {
    return 'Starts: $date';
  }

  @override
  String recurEndsOn(String date) {
    return 'Ends: $date';
  }

  @override
  String get recurEndsNever => 'Ends: never';

  @override
  String recurCreatesAtTime(String time) {
    return 'Creates at $time';
  }

  @override
  String get todoKeepForever => 'Keep forever';

  @override
  String get todoKeepForeverHint =>
      'Never deleted automatically, even when completed';

  @override
  String get fitnessModuleTitle => 'Fitness';

  @override
  String get fitnessMeasurementsTitle => 'Measurements';

  @override
  String fitnessLatest(String weight) {
    return 'Latest: $weight kg';
  }

  @override
  String get fitnessNoMeasurements => 'No measurements yet';

  @override
  String get fitnessNoMeasurementsHint =>
      'Add a weight by hand to start tracking.';

  @override
  String get fitnessAddMeasurement => 'Add measurement';

  @override
  String get fitnessWeight => 'Weight (kg)';

  @override
  String get fitnessWeightInvalid => 'Enter a weight between 10 and 500 kg';

  @override
  String get fitnessWho => 'Who';

  @override
  String get fitnessWhen => 'When';

  @override
  String fitnessFatPct(String value) {
    return 'Fat $value%';
  }

  @override
  String fitnessWaterPct(String value) {
    return 'Water $value%';
  }

  @override
  String fitnessMusclePct(String value) {
    return 'Muscle $value kg';
  }

  @override
  String fitnessBmi(String value) {
    return 'BMI $value';
  }

  @override
  String get fitnessWallTitle => 'Weight';

  @override
  String get fitnessWallNone => 'No weight yet';

  @override
  String get fitnessProfileTitle => 'Fitness profile';

  @override
  String get fitnessProfileAction => 'Edit profile';

  @override
  String get fitnessProfileHintTitle => 'Complete your profile';

  @override
  String get fitnessProfileHintBody =>
      'Add your sex, birth date and height to get body composition from the scale.';

  @override
  String get fitnessSex => 'Sex';

  @override
  String get fitnessSexMale => 'Male';

  @override
  String get fitnessSexFemale => 'Female';

  @override
  String get fitnessBirthDate => 'Birth date';

  @override
  String get fitnessBirthDateInvalid => 'Pick a birth date in the past';

  @override
  String get fitnessHeight => 'Height (cm)';

  @override
  String get fitnessHeightInvalid => 'Enter a height between 50 and 250 cm';
}
