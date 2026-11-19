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
  String get todoColor => 'Color';

  @override
  String get markdownEdit => 'Edit';

  @override
  String get markdownPreview => 'Preview';

  @override
  String get markdownNothing => 'Nothing to preview';

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
  String get wallLayoutToday => 'Today';

  @override
  String get wallLayoutKanban => 'Board';

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
  String todoInboxAssigned(String name, String title) {
    return '$name assigned you “$title”';
  }
}
