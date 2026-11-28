import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pl'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Oikoboard'**
  String get appName;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @commonLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get commonLogOut;

  /// No description provided for @commonTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// No description provided for @commonCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// No description provided for @commonOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get commonOpen;

  /// No description provided for @commonConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get commonConnect;

  /// No description provided for @commonNobody.
  ///
  /// In en, this message translates to:
  /// **'Nobody'**
  String get commonNobody;

  /// No description provided for @commonReadOnly.
  ///
  /// In en, this message translates to:
  /// **'read-only'**
  String get commonReadOnly;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get commonError;

  /// No description provided for @commonNoServerConnection.
  ///
  /// In en, this message translates to:
  /// **'No connection to the server'**
  String get commonNoServerConnection;

  /// No description provided for @commonDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted “{name}”'**
  String commonDeleted(String name);

  /// No description provided for @todoMarkDone.
  ///
  /// In en, this message translates to:
  /// **'Mark done'**
  String get todoMarkDone;

  /// No description provided for @todoReopen.
  ///
  /// In en, this message translates to:
  /// **'Mark not done'**
  String get todoReopen;

  /// No description provided for @calendarsConfirmDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect {account}?'**
  String calendarsConfirmDisconnect(String account);

  /// No description provided for @calendarsConfirmDisconnectBody.
  ///
  /// In en, this message translates to:
  /// **'Its calendars will disappear from Oikoboard. Events stay in the account.'**
  String get calendarsConfirmDisconnectBody;

  /// No description provided for @navWall.
  ///
  /// In en, this message translates to:
  /// **'Wall'**
  String get navWall;

  /// No description provided for @dateToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dateToday;

  /// No description provided for @dateTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get dateTomorrow;

  /// No description provided for @dateYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get dateYesterday;

  /// No description provided for @serverTitle.
  ///
  /// In en, this message translates to:
  /// **'Family server'**
  String get serverTitle;

  /// No description provided for @serverIntro.
  ///
  /// In en, this message translates to:
  /// **'Enter the address of your family’s Oikoboard server (e.g. oiko.example.com).'**
  String get serverIntro;

  /// No description provided for @serverAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverAddressLabel;

  /// No description provided for @serverNotAnAddress.
  ///
  /// In en, this message translates to:
  /// **'That doesn’t look like a server address.'**
  String get serverNotAnAddress;

  /// url: the address the user entered, as a string
  ///
  /// In en, this message translates to:
  /// **'No Oikoboard server responds at {url}.'**
  String serverNotOikoboard(String url);

  /// No description provided for @loginInviteBanner.
  ///
  /// In en, this message translates to:
  /// **'You have a family invitation — log in to join.'**
  String get loginInviteBanner;

  /// No description provided for @loginTagline.
  ///
  /// In en, this message translates to:
  /// **'The family’s shared board.'**
  String get loginTagline;

  /// No description provided for @loginServerUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Can’t connect to the server.'**
  String get loginServerUnreachable;

  /// No description provided for @loginServerUnreachableAt.
  ///
  /// In en, this message translates to:
  /// **'Can’t connect to the server ({url}).'**
  String loginServerUnreachableAt(String url);

  /// No description provided for @loginWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Log in with Google'**
  String get loginWithGoogle;

  /// No description provided for @loginNoGoogle.
  ///
  /// In en, this message translates to:
  /// **'The server has no login configured (OIKO_GOOGLE_CLIENT_ID).'**
  String get loginNoGoogle;

  /// No description provided for @loginDevMode.
  ///
  /// In en, this message translates to:
  /// **'Developer mode'**
  String get loginDevMode;

  /// No description provided for @loginEmailField.
  ///
  /// In en, this message translates to:
  /// **'Email (unverified)'**
  String get loginEmailField;

  /// No description provided for @loginEnter.
  ///
  /// In en, this message translates to:
  /// **'Enter'**
  String get loginEnter;

  /// No description provided for @loginServerChange.
  ///
  /// In en, this message translates to:
  /// **'Server: {host} — change'**
  String loginServerChange(String host);

  /// No description provided for @loginWhoAreYou.
  ///
  /// In en, this message translates to:
  /// **'Who are you? (mock mode)'**
  String get loginWhoAreYou;

  /// No description provided for @loginErrorStale.
  ///
  /// In en, this message translates to:
  /// **'The login started in another window — try again.'**
  String get loginErrorStale;

  /// No description provided for @loginErrorCancelled.
  ///
  /// In en, this message translates to:
  /// **'Login cancelled.'**
  String get loginErrorCancelled;

  /// No description provided for @loginErrorFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t log in with Google.'**
  String get loginErrorFailed;

  /// No description provided for @onboardingHiNoName.
  ///
  /// In en, this message translates to:
  /// **'Hi!'**
  String get onboardingHiNoName;

  /// No description provided for @onboardingHiName.
  ///
  /// In en, this message translates to:
  /// **'Hi, {name}!'**
  String onboardingHiName(String name);

  /// No description provided for @onboardingCreateFamily.
  ///
  /// In en, this message translates to:
  /// **'Create a family'**
  String get onboardingCreateFamily;

  /// No description provided for @onboardingCreateFamilyHint.
  ///
  /// In en, this message translates to:
  /// **'You’ll invite the rest of the household with a link later.'**
  String get onboardingCreateFamilyHint;

  /// No description provided for @onboardingFamilyName.
  ///
  /// In en, this message translates to:
  /// **'Family name'**
  String get onboardingFamilyName;

  /// No description provided for @onboardingFamilyNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Smiths'**
  String get onboardingFamilyNameHint;

  /// No description provided for @onboardingMyName.
  ///
  /// In en, this message translates to:
  /// **'What should we call you in the family?'**
  String get onboardingMyName;

  /// No description provided for @onboardingMyNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Dad'**
  String get onboardingMyNameHint;

  /// No description provided for @onboardingMyNameHintDefault.
  ///
  /// In en, this message translates to:
  /// **'e.g. Dad (default: {name})'**
  String onboardingMyNameHintDefault(String name);

  /// No description provided for @onboardingCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get onboardingCreate;

  /// No description provided for @onboardingHaveInvite.
  ///
  /// In en, this message translates to:
  /// **'Have an invitation?'**
  String get onboardingHaveInvite;

  /// No description provided for @onboardingInviteHint.
  ///
  /// In en, this message translates to:
  /// **'Open the link from a household member or paste it here.'**
  String get onboardingInviteHint;

  /// No description provided for @onboardingInviteLink.
  ///
  /// In en, this message translates to:
  /// **'Invitation link'**
  String get onboardingInviteLink;

  /// No description provided for @onboardingNotInviteLink.
  ///
  /// In en, this message translates to:
  /// **'This doesn’t look like an invitation link.'**
  String get onboardingNotInviteLink;

  /// No description provided for @onboardingBackTo.
  ///
  /// In en, this message translates to:
  /// **'Back to: {family}'**
  String onboardingBackTo(String family);

  /// No description provided for @onboardingDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get onboardingDecline;

  /// No description provided for @onboardingInvitation.
  ///
  /// In en, this message translates to:
  /// **'Invitation'**
  String get onboardingInvitation;

  /// No description provided for @onboardingInviteCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t check the invitation.'**
  String get onboardingInviteCheckFailed;

  /// No description provided for @onboardingFamilyInvitation.
  ///
  /// In en, this message translates to:
  /// **'Family invitation'**
  String get onboardingFamilyInvitation;

  /// No description provided for @onboardingInvitedBy.
  ///
  /// In en, this message translates to:
  /// **'Invited by: {name}'**
  String onboardingInvitedBy(String name);

  /// No description provided for @onboardingJoinAs.
  ///
  /// In en, this message translates to:
  /// **'You’ll join as: {name}'**
  String onboardingJoinAs(String name);

  /// No description provided for @onboardingAlreadyMember.
  ///
  /// In en, this message translates to:
  /// **'You already belong to this family.'**
  String get onboardingAlreadyMember;

  /// No description provided for @onboardingGoTo.
  ///
  /// In en, this message translates to:
  /// **'Go to family'**
  String get onboardingGoTo;

  /// No description provided for @onboardingJoin.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get onboardingJoin;

  /// No description provided for @inviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite to: {family}'**
  String inviteTitle(String family);

  /// No description provided for @inviteWhom.
  ///
  /// In en, this message translates to:
  /// **'Who are you inviting?'**
  String get inviteWhom;

  /// No description provided for @inviteNewPerson.
  ///
  /// In en, this message translates to:
  /// **'A new person'**
  String get inviteNewPerson;

  /// No description provided for @inviteNewPersonHint.
  ///
  /// In en, this message translates to:
  /// **'They’ll choose their own name'**
  String get inviteNewPersonHint;

  /// No description provided for @inviteMemberNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Already in the family, no account'**
  String get inviteMemberNoAccount;

  /// No description provided for @inviteSendLink.
  ///
  /// In en, this message translates to:
  /// **'Send this link to the household member. It works once, for 7 days.'**
  String get inviteSendLink;

  /// No description provided for @inviteCreateLink.
  ///
  /// In en, this message translates to:
  /// **'Create link'**
  String get inviteCreateLink;

  /// No description provided for @inviteLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get inviteLinkCopied;

  /// No description provided for @shellSimulatorStop.
  ///
  /// In en, this message translates to:
  /// **'Stop family simulation'**
  String get shellSimulatorStop;

  /// No description provided for @shellSimulatorStart.
  ///
  /// In en, this message translates to:
  /// **'Simulate changes from the family'**
  String get shellSimulatorStart;

  /// No description provided for @shellAiChat.
  ///
  /// In en, this message translates to:
  /// **'AI chat (MCP)'**
  String get shellAiChat;

  /// No description provided for @shellInviteToFamily.
  ///
  /// In en, this message translates to:
  /// **'Invite to family'**
  String get shellInviteToFamily;

  /// No description provided for @shellOffline.
  ///
  /// In en, this message translates to:
  /// **'No connection — reconnecting…'**
  String get shellOffline;

  /// No description provided for @wallGreetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get wallGreetingMorning;

  /// No description provided for @wallGreetingDay.
  ///
  /// In en, this message translates to:
  /// **'Hi'**
  String get wallGreetingDay;

  /// No description provided for @wallGreetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get wallGreetingEvening;

  /// No description provided for @wallGreeting.
  ///
  /// In en, this message translates to:
  /// **'{greeting}, {name}!'**
  String wallGreeting(String greeting, String name);

  /// No description provided for @aiTitle.
  ///
  /// In en, this message translates to:
  /// **'ChatGPT, Claude and others'**
  String get aiTitle;

  /// No description provided for @aiDescription.
  ///
  /// In en, this message translates to:
  /// **'You can also connect your family’s tasks and calendar to your own AI chat. Add a connector (MCP) with this address there — you’ll log in with your Oikoboard account, and changes will be saved as yours.'**
  String get aiDescription;

  /// No description provided for @aiCopyAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy address'**
  String get aiCopyAddress;

  /// No description provided for @aiAddressCopied.
  ///
  /// In en, this message translates to:
  /// **'Address copied'**
  String get aiAddressCopied;

  /// No description provided for @aiNothingConnected.
  ///
  /// In en, this message translates to:
  /// **'Nothing is connected.'**
  String get aiNothingConnected;

  /// No description provided for @aiNotUsedYet.
  ///
  /// In en, this message translates to:
  /// **'Not used yet'**
  String get aiNotUsedYet;

  /// No description provided for @aiLastUsed.
  ///
  /// In en, this message translates to:
  /// **'Last used: {when}'**
  String aiLastUsed(String when);

  /// No description provided for @aiDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get aiDisconnect;

  /// No description provided for @todoModuleTitle.
  ///
  /// In en, this message translates to:
  /// **'Lists'**
  String get todoModuleTitle;

  /// No description provided for @todoError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String todoError(String error);

  /// No description provided for @todoNoLists.
  ///
  /// In en, this message translates to:
  /// **'No lists — add the first one.'**
  String get todoNoLists;

  /// No description provided for @todoNewList.
  ///
  /// In en, this message translates to:
  /// **'New list'**
  String get todoNewList;

  /// No description provided for @todoListChip.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get todoListChip;

  /// No description provided for @todoEditList.
  ///
  /// In en, this message translates to:
  /// **'Edit list'**
  String get todoEditList;

  /// No description provided for @todoMarkedDone.
  ///
  /// In en, this message translates to:
  /// **'Done: “{title}”'**
  String todoMarkedDone(String title);

  /// No description provided for @commonUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// No description provided for @todoCommentDeleted.
  ///
  /// In en, this message translates to:
  /// **'Comment deleted'**
  String get todoCommentDeleted;

  /// No description provided for @todoWallFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter lists'**
  String get todoWallFilter;

  /// No description provided for @todoWallFilterReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get todoWallFilterReset;

  /// No description provided for @todoWallScopeAll.
  ///
  /// In en, this message translates to:
  /// **'All lists'**
  String get todoWallScopeAll;

  /// No description provided for @todoWallScopeMyLists.
  ///
  /// In en, this message translates to:
  /// **'Lists with my tasks'**
  String get todoWallScopeMyLists;

  /// No description provided for @todoWallScopeMyTasks.
  ///
  /// In en, this message translates to:
  /// **'Only my tasks'**
  String get todoWallScopeMyTasks;

  /// No description provided for @todoWallFilterLists.
  ///
  /// In en, this message translates to:
  /// **'Show lists'**
  String get todoWallFilterLists;

  /// No description provided for @todoWallFilterEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches the filter'**
  String get todoWallFilterEmpty;

  /// No description provided for @todoDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get todoDescription;

  /// No description provided for @todoHasDescription.
  ///
  /// In en, this message translates to:
  /// **'Has a description'**
  String get todoHasDescription;

  /// No description provided for @todoFromRecurring.
  ///
  /// In en, this message translates to:
  /// **'Created from a recurring task'**
  String get todoFromRecurring;

  /// No description provided for @todoHasComments.
  ///
  /// In en, this message translates to:
  /// **'Has comments'**
  String get todoHasComments;

  /// No description provided for @todoColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get todoColor;

  /// No description provided for @markdownEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get markdownEdit;

  /// No description provided for @markdownPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get markdownPreview;

  /// No description provided for @markdownNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to preview'**
  String get markdownNothing;

  /// No description provided for @linkOpen.
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get linkOpen;

  /// No description provided for @linkCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get linkCopy;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get linkCopied;

  /// No description provided for @todoDeleteList.
  ///
  /// In en, this message translates to:
  /// **'Delete list'**
  String get todoDeleteList;

  /// No description provided for @todoName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get todoName;

  /// No description provided for @todoAddTo.
  ///
  /// In en, this message translates to:
  /// **'Add to “{list}”…'**
  String todoAddTo(String list);

  /// No description provided for @todoAllDone.
  ///
  /// In en, this message translates to:
  /// **'All done 🎉'**
  String get todoAllDone;

  /// No description provided for @todoDoneSection.
  ///
  /// In en, this message translates to:
  /// **'Done ({count})'**
  String todoDoneSection(int count);

  /// No description provided for @todoOverdueSection.
  ///
  /// In en, this message translates to:
  /// **'Overdue ({count})'**
  String todoOverdueSection(int count);

  /// No description provided for @todoTodaySection.
  ///
  /// In en, this message translates to:
  /// **'Today ({count})'**
  String todoTodaySection(int count);

  /// No description provided for @todoMineSection.
  ///
  /// In en, this message translates to:
  /// **'My tasks'**
  String get todoMineSection;

  /// Number of open tasks in a list
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} to do} other{{count} to do}}'**
  String todoOpenCount(int count);

  /// No description provided for @todoDue.
  ///
  /// In en, this message translates to:
  /// **'due: {day}'**
  String todoDue(String day);

  /// No description provided for @todoDueLabel.
  ///
  /// In en, this message translates to:
  /// **'Due: {day}'**
  String todoDueLabel(String day);

  /// A due date with a time, e.g. 'Today, 17:30'
  ///
  /// In en, this message translates to:
  /// **'{day}, {time}'**
  String todoDayAt(String day, String time);

  /// No description provided for @todoSetTime.
  ///
  /// In en, this message translates to:
  /// **'Add time'**
  String get todoSetTime;

  /// No description provided for @todoRemoveTime.
  ///
  /// In en, this message translates to:
  /// **'Remove time'**
  String get todoRemoveTime;

  /// No description provided for @todoTask.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get todoTask;

  /// No description provided for @todoAssignee.
  ///
  /// In en, this message translates to:
  /// **'Assignee'**
  String get todoAssignee;

  /// No description provided for @todoMoreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get todoMoreOptions;

  /// No description provided for @todoWhoDoesIt.
  ///
  /// In en, this message translates to:
  /// **'Who will do it?'**
  String get todoWhoDoesIt;

  /// No description provided for @todoSetDue.
  ///
  /// In en, this message translates to:
  /// **'Set due date'**
  String get todoSetDue;

  /// No description provided for @todoRemoveDue.
  ///
  /// In en, this message translates to:
  /// **'Remove due date'**
  String get todoRemoveDue;

  /// No description provided for @todoComments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get todoComments;

  /// No description provided for @todoNoComments.
  ///
  /// In en, this message translates to:
  /// **'No comments yet'**
  String get todoNoComments;

  /// No description provided for @todoCommentsOf.
  ///
  /// In en, this message translates to:
  /// **'Comments: {title}'**
  String todoCommentsOf(String title);

  /// No description provided for @todoCommentHint.
  ///
  /// In en, this message translates to:
  /// **'Add a comment…'**
  String get todoCommentHint;

  /// No description provided for @todoCommentSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get todoCommentSend;

  /// No description provided for @todoCommentDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete comment'**
  String get todoCommentDelete;

  /// No description provided for @memberRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed member'**
  String get memberRemoved;

  /// No description provided for @memberOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get memberOnline;

  /// No description provided for @todoDayListDue.
  ///
  /// In en, this message translates to:
  /// **'List due'**
  String get todoDayListDue;

  /// No description provided for @calendarModuleTitle.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendarModuleTitle;

  /// No description provided for @calendarViewDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get calendarViewDay;

  /// No description provided for @calendarViewThreeDays.
  ///
  /// In en, this message translates to:
  /// **'3 days'**
  String get calendarViewThreeDays;

  /// No description provided for @calendarViewWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get calendarViewWeek;

  /// No description provided for @calendarViewMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get calendarViewMonth;

  /// No description provided for @calendarViewTooltip.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get calendarViewTooltip;

  /// No description provided for @calendarsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Calendars'**
  String get calendarsTooltip;

  /// No description provided for @calendarPrevDay.
  ///
  /// In en, this message translates to:
  /// **'Previous day'**
  String get calendarPrevDay;

  /// No description provided for @calendarPrevPeriod.
  ///
  /// In en, this message translates to:
  /// **'Previous period'**
  String get calendarPrevPeriod;

  /// No description provided for @calendarPrevMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get calendarPrevMonth;

  /// No description provided for @calendarNextDay.
  ///
  /// In en, this message translates to:
  /// **'Next day'**
  String get calendarNextDay;

  /// No description provided for @calendarNextPeriod.
  ///
  /// In en, this message translates to:
  /// **'Next period'**
  String get calendarNextPeriod;

  /// No description provided for @calendarNextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get calendarNextMonth;

  /// No description provided for @calendarNewEvent.
  ///
  /// In en, this message translates to:
  /// **'New event'**
  String get calendarNewEvent;

  /// No description provided for @calendarEvent.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get calendarEvent;

  /// No description provided for @calendarConnectPrompt.
  ///
  /// In en, this message translates to:
  /// **'Connect a Google calendar — events will sync both ways.'**
  String get calendarConnectPrompt;

  /// No description provided for @calendarConnectAction.
  ///
  /// In en, this message translates to:
  /// **'Connect calendar'**
  String get calendarConnectAction;

  /// No description provided for @calendarNoEvents.
  ///
  /// In en, this message translates to:
  /// **'No events'**
  String get calendarNoEvents;

  /// No description provided for @calendarSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming up'**
  String get calendarSoon;

  /// No description provided for @calendarWeekdayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get calendarWeekdayMon;

  /// No description provided for @calendarWeekdayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get calendarWeekdayTue;

  /// No description provided for @calendarWeekdayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get calendarWeekdayWed;

  /// No description provided for @calendarWeekdayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get calendarWeekdayThu;

  /// No description provided for @calendarWeekdayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get calendarWeekdayFri;

  /// No description provided for @calendarWeekdaySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get calendarWeekdaySat;

  /// No description provided for @calendarWeekdaySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get calendarWeekdaySun;

  /// No description provided for @calendarAllDay.
  ///
  /// In en, this message translates to:
  /// **'All day'**
  String get calendarAllDay;

  /// days > 1
  ///
  /// In en, this message translates to:
  /// **'{days, plural, one{All day · {days} day} other{All day · {days} days}}'**
  String calendarAllDaySpan(int days);

  /// No description provided for @calendarReadOnlyNotice.
  ///
  /// In en, this message translates to:
  /// **'Calendar “{name}” is read-only.'**
  String calendarReadOnlyNotice(String name);

  /// No description provided for @calendarTitleField.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get calendarTitleField;

  /// No description provided for @calendarLabel.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendarLabel;

  /// No description provided for @calendarRepeatField.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get calendarRepeatField;

  /// No description provided for @calendarPlaceField.
  ///
  /// In en, this message translates to:
  /// **'Place'**
  String get calendarPlaceField;

  /// No description provided for @calendarDescriptionField.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get calendarDescriptionField;

  /// No description provided for @calendarWhoField.
  ///
  /// In en, this message translates to:
  /// **'Who'**
  String get calendarWhoField;

  /// No description provided for @calendarRecurringChange.
  ///
  /// In en, this message translates to:
  /// **'Change recurring event'**
  String get calendarRecurringChange;

  /// No description provided for @calendarRecurringDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete recurring event'**
  String get calendarRecurringDelete;

  /// No description provided for @calendarRecurringThisOnly.
  ///
  /// In en, this message translates to:
  /// **'This event only'**
  String get calendarRecurringThisOnly;

  /// No description provided for @calendarRecurringSeries.
  ///
  /// In en, this message translates to:
  /// **'All events in the series'**
  String get calendarRecurringSeries;

  /// No description provided for @calendarConnectCancelled.
  ///
  /// In en, this message translates to:
  /// **'Calendar connection cancelled.'**
  String get calendarConnectCancelled;

  /// No description provided for @calendarConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t connect the calendar.'**
  String get calendarConnectFailed;

  /// No description provided for @repeatNone.
  ///
  /// In en, this message translates to:
  /// **'Doesn’t repeat'**
  String get repeatNone;

  /// No description provided for @repeatDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get repeatDaily;

  /// No description provided for @repeatWeekdays.
  ///
  /// In en, this message translates to:
  /// **'Weekdays'**
  String get repeatWeekdays;

  /// No description provided for @repeatWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get repeatWeekly;

  /// No description provided for @repeatMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get repeatMonthly;

  /// No description provided for @repeatYearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get repeatYearly;

  /// No description provided for @repeatCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get repeatCustom;

  /// No description provided for @todoDaySheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Tasks · {date}'**
  String todoDaySheetTitle(String date);

  /// No description provided for @todoDayEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tasks for this day'**
  String get todoDayEmpty;

  /// No description provided for @calendarsTitle.
  ///
  /// In en, this message translates to:
  /// **'Family calendars'**
  String get calendarsTitle;

  /// No description provided for @calendarsIntro.
  ///
  /// In en, this message translates to:
  /// **'Events are saved to the connected calendars (e.g. Google) — changes work both ways. Tasks with a due date go into the calendar marked ✓ as one entry per day.'**
  String get calendarsIntro;

  /// No description provided for @calendarsNoneConnected.
  ///
  /// In en, this message translates to:
  /// **'No calendar is connected yet.'**
  String get calendarsNoneConnected;

  /// No description provided for @calendarsTodoTag.
  ///
  /// In en, this message translates to:
  /// **'tasks with a due date'**
  String get calendarsTodoTag;

  /// No description provided for @calendarsTodoTargetOn.
  ///
  /// In en, this message translates to:
  /// **'Tasks with a due date go here'**
  String get calendarsTodoTargetOn;

  /// No description provided for @calendarsTodoTargetOff.
  ///
  /// In en, this message translates to:
  /// **'Show tasks with a due date here'**
  String get calendarsTodoTargetOff;

  /// No description provided for @calendarsSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get calendarsSyncNow;

  /// No description provided for @calendarsRemoveFromFamily.
  ///
  /// In en, this message translates to:
  /// **'Remove from family'**
  String get calendarsRemoveFromFamily;

  /// No description provided for @calendarsYourAccounts.
  ///
  /// In en, this message translates to:
  /// **'Your accounts'**
  String get calendarsYourAccounts;

  /// No description provided for @calendarsConnectGoogle.
  ///
  /// In en, this message translates to:
  /// **'Connect Google account'**
  String get calendarsConnectGoogle;

  /// No description provided for @calendarsAccessRevoked.
  ///
  /// In en, this message translates to:
  /// **'Access revoked — connect the account again'**
  String get calendarsAccessRevoked;

  /// No description provided for @calendarsTestAccount.
  ///
  /// In en, this message translates to:
  /// **'test account (mock)'**
  String get calendarsTestAccount;

  /// No description provided for @calendarsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t fetch the list of calendars.'**
  String get calendarsLoadFailed;

  /// No description provided for @calendarsDisconnectAccount.
  ///
  /// In en, this message translates to:
  /// **'Disconnect account (removes its calendars)'**
  String get calendarsDisconnectAccount;

  /// Offline badge tooltip with queued changes
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{No connection — {count} change waiting to be sent} other{No connection — {count} changes waiting to be sent}}'**
  String syncPending(int count);

  /// Tooltip of the button opening unsynced changes
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} change wasn’t saved} other{{count} changes weren’t saved}}'**
  String syncFailedBadge(int count);

  /// No description provided for @syncUnsyncedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsynced changes'**
  String get syncUnsyncedTitle;

  /// No description provided for @syncUnsyncedHint.
  ///
  /// In en, this message translates to:
  /// **'The server rejected these changes. Retry them or discard them.'**
  String get syncUnsyncedHint;

  /// Snackbar; what: e.g. Change “Milk”
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save: {what}'**
  String syncFailedNotice(String what);

  /// No description provided for @syncShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get syncShow;

  /// No description provided for @syncRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get syncRetry;

  /// No description provided for @syncDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get syncDiscard;

  /// A rejected create
  ///
  /// In en, this message translates to:
  /// **'Add “{name}”'**
  String syncAdd(String name);

  /// A rejected edit
  ///
  /// In en, this message translates to:
  /// **'Change “{name}”'**
  String syncChange(String name);

  /// A rejected delete
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”'**
  String syncDelete(String name);

  /// No description provided for @syncUnnamed.
  ///
  /// In en, this message translates to:
  /// **'untitled'**
  String get syncUnnamed;

  /// Why the server rejected a change
  ///
  /// In en, this message translates to:
  /// **'Server ({status}): {message}'**
  String syncServerSays(int status, String message);

  /// One field of a rejected change: current server value → attempted value
  ///
  /// In en, this message translates to:
  /// **'{field}: {before} → {after}'**
  String syncDiffLine(String field, String before, String after);

  /// No description provided for @todoInbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get todoInbox;

  /// No description provided for @todoInboxUnread.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Inbox: {count} unread} other{Inbox: {count} unread}}'**
  String todoInboxUnread(int count);

  /// No description provided for @todoInboxEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet. Mentions, replies in your threads and tasks assigned to you show up here.'**
  String get todoInboxEmpty;

  /// No description provided for @todoInboxMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get todoInboxMarkAllRead;

  /// No description provided for @todoInboxMention.
  ///
  /// In en, this message translates to:
  /// **'{name} mentioned you in “{title}”'**
  String todoInboxMention(String name, String title);

  /// No description provided for @todoInboxReply.
  ///
  /// In en, this message translates to:
  /// **'{name} replied in “{title}”'**
  String todoInboxReply(String name, String title);

  /// No description provided for @todoInboxRecurring.
  ///
  /// In en, this message translates to:
  /// **'Recurring task for you: “{title}”'**
  String todoInboxRecurring(String title);

  /// No description provided for @todoInboxAssigned.
  ///
  /// In en, this message translates to:
  /// **'{name} assigned you “{title}”'**
  String todoInboxAssigned(String name, String title);

  /// No description provided for @searchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTooltip;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search tasks, lists and events'**
  String get searchHint;

  /// No description provided for @searchNothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get searchNothingFound;

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search needs a connection to the server'**
  String get searchFailed;

  /// No description provided for @todoSearchList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get todoSearchList;

  /// No description provided for @todoSearchDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get todoSearchDone;

  /// No description provided for @todoNewTask.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get todoNewTask;

  /// No description provided for @attachAction.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get attachAction;

  /// No description provided for @attachTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get attachTakePhoto;

  /// No description provided for @attachPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get attachPhotos;

  /// No description provided for @attachFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get attachFiles;

  /// No description provided for @attachStorage.
  ///
  /// In en, this message translates to:
  /// **'Family storage: {used} of {quota} used'**
  String attachStorage(String used, String quota);

  /// No description provided for @attachTooLarge.
  ///
  /// In en, this message translates to:
  /// **'“{name}” is larger than {max}'**
  String attachTooLarge(String name, String max);

  /// No description provided for @attachStorageFull.
  ///
  /// In en, this message translates to:
  /// **'The family storage is full — “{name}” wasn’t uploaded'**
  String attachStorageFull(String name);

  /// No description provided for @attachUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t upload “{name}”'**
  String attachUploadFailed(String name);

  /// No description provided for @attachRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get attachRemove;

  /// No description provided for @attachDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get attachDownload;

  /// No description provided for @attachOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t open the file'**
  String get attachOpenFailed;

  /// No description provided for @attachUnavailableInDemo.
  ///
  /// In en, this message translates to:
  /// **'Files can’t be opened in the demo'**
  String get attachUnavailableInDemo;

  /// No description provided for @attachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachments;

  /// No description provided for @todoMovedTo.
  ///
  /// In en, this message translates to:
  /// **'Moved to “{list}”'**
  String todoMovedTo(String list);

  /// No description provided for @recurringTitle.
  ///
  /// In en, this message translates to:
  /// **'Recurring tasks'**
  String get recurringTitle;

  /// No description provided for @recurringEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recurring tasks yet. They add a new task to this list on a schedule — for example every Monday and Friday.'**
  String get recurringEmpty;

  /// No description provided for @recurringNew.
  ///
  /// In en, this message translates to:
  /// **'New recurring task'**
  String get recurringNew;

  /// No description provided for @recurringEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit recurring task'**
  String get recurringEdit;

  /// No description provided for @recurringNext.
  ///
  /// In en, this message translates to:
  /// **'Next: {date}'**
  String recurringNext(String date);

  /// No description provided for @recurringNoNext.
  ///
  /// In en, this message translates to:
  /// **'No upcoming occurrences'**
  String get recurringNoNext;

  /// No description provided for @recurringPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get recurringPaused;

  /// No description provided for @recurringActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get recurringActive;

  /// No description provided for @recurringRepeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get recurringRepeat;

  /// No description provided for @recurDailyChip.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get recurDailyChip;

  /// No description provided for @recurWeeklyChip.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get recurWeeklyChip;

  /// No description provided for @recurMonthlyChip.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get recurMonthlyChip;

  /// No description provided for @recurYearlyChip.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get recurYearlyChip;

  /// No description provided for @recurEvery.
  ///
  /// In en, this message translates to:
  /// **'Every'**
  String get recurEvery;

  /// No description provided for @recurUnitDay.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{day} other{days}}'**
  String recurUnitDay(int n);

  /// No description provided for @recurUnitWeek.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{week} other{weeks}}'**
  String recurUnitWeek(int n);

  /// No description provided for @recurUnitMonth.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{month} other{months}}'**
  String recurUnitMonth(int n);

  /// No description provided for @recurUnitYear.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{year} other{years}}'**
  String recurUnitYear(int n);

  /// No description provided for @recurOnDay.
  ///
  /// In en, this message translates to:
  /// **'On day {day}'**
  String recurOnDay(int day);

  /// No description provided for @recurLastDay.
  ///
  /// In en, this message translates to:
  /// **'Last day of the month'**
  String get recurLastDay;

  /// No description provided for @recurDaily.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{Every day} other{Every {n} days}}'**
  String recurDaily(int n);

  /// No description provided for @recurWeekly.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{Every week on {days}} other{Every {n} weeks on {days}}}'**
  String recurWeekly(int n, String days);

  /// No description provided for @recurMonthlyDay.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{Every month on day {day}} other{Every {n} months on day {day}}}'**
  String recurMonthlyDay(int n, int day);

  /// No description provided for @recurMonthlyLast.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{Every month on the last day} other{Every {n} months on the last day}}'**
  String recurMonthlyLast(int n);

  /// No description provided for @recurYearly.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{Every year on {date}} other{Every {n} years on {date}}}'**
  String recurYearly(int n, String date);

  /// No description provided for @recurCustomRule.
  ///
  /// In en, this message translates to:
  /// **'Custom schedule ({rrule})'**
  String recurCustomRule(String rrule);

  /// No description provided for @recurNoEnd.
  ///
  /// In en, this message translates to:
  /// **'Remove end date'**
  String get recurNoEnd;

  /// No description provided for @recurDue.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get recurDue;

  /// No description provided for @recurDueNone.
  ///
  /// In en, this message translates to:
  /// **'No due date'**
  String get recurDueNone;

  /// No description provided for @recurDueSameDay.
  ///
  /// In en, this message translates to:
  /// **'Same day'**
  String get recurDueSameDay;

  /// No description provided for @recurDueAfter.
  ///
  /// In en, this message translates to:
  /// **'After some days'**
  String get recurDueAfter;

  /// No description provided for @recurDueDays.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 day after creation} other{{n} days after creation}}'**
  String recurDueDays(int n);

  /// No description provided for @recurDueDaysField.
  ///
  /// In en, this message translates to:
  /// **'Days after creation'**
  String get recurDueDaysField;

  /// No description provided for @recurNextOccurrences.
  ///
  /// In en, this message translates to:
  /// **'Next occurrences'**
  String get recurNextOccurrences;

  /// No description provided for @recurFirstDue.
  ///
  /// In en, this message translates to:
  /// **'The first task will be due {date}'**
  String recurFirstDue(String date);

  /// No description provided for @recurPreviewFailed.
  ///
  /// In en, this message translates to:
  /// **'Can\'t compute the preview right now'**
  String get recurPreviewFailed;

  /// No description provided for @recurNoOccurrences.
  ///
  /// In en, this message translates to:
  /// **'This schedule has no occurrences'**
  String get recurNoOccurrences;

  /// No description provided for @recurWeekdays.
  ///
  /// In en, this message translates to:
  /// **'Weekdays'**
  String get recurWeekdays;

  /// No description provided for @recurDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”?'**
  String recurDeleteTitle(String name);

  /// No description provided for @recurDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Tasks it already created stay.'**
  String get recurDeleteMessage;

  /// No description provided for @recurStartsOn.
  ///
  /// In en, this message translates to:
  /// **'Starts: {date}'**
  String recurStartsOn(String date);

  /// No description provided for @recurEndsOn.
  ///
  /// In en, this message translates to:
  /// **'Ends: {date}'**
  String recurEndsOn(String date);

  /// No description provided for @recurEndsNever.
  ///
  /// In en, this message translates to:
  /// **'Ends: never'**
  String get recurEndsNever;

  /// No description provided for @recurCreatesAtTime.
  ///
  /// In en, this message translates to:
  /// **'Creates at {time}'**
  String recurCreatesAtTime(String time);

  /// No description provided for @todoKeepForever.
  ///
  /// In en, this message translates to:
  /// **'Keep forever'**
  String get todoKeepForever;

  /// No description provided for @todoKeepForeverHint.
  ///
  /// In en, this message translates to:
  /// **'Never deleted automatically, even when completed'**
  String get todoKeepForeverHint;

  /// No description provided for @fitnessModuleTitle.
  ///
  /// In en, this message translates to:
  /// **'Fitness'**
  String get fitnessModuleTitle;

  /// No description provided for @fitnessMeasurementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Measurements'**
  String get fitnessMeasurementsTitle;

  /// No description provided for @fitnessLatest.
  ///
  /// In en, this message translates to:
  /// **'Latest: {weight} kg'**
  String fitnessLatest(String weight);

  /// No description provided for @fitnessNoMeasurements.
  ///
  /// In en, this message translates to:
  /// **'No measurements yet'**
  String get fitnessNoMeasurements;

  /// No description provided for @fitnessNoMeasurementsHint.
  ///
  /// In en, this message translates to:
  /// **'Add a weight by hand to start tracking.'**
  String get fitnessNoMeasurementsHint;

  /// No description provided for @fitnessAddMeasurement.
  ///
  /// In en, this message translates to:
  /// **'Add measurement'**
  String get fitnessAddMeasurement;

  /// No description provided for @fitnessWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight (kg)'**
  String get fitnessWeight;

  /// No description provided for @fitnessWeightInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a weight between 10 and 500 kg'**
  String get fitnessWeightInvalid;

  /// No description provided for @fitnessWho.
  ///
  /// In en, this message translates to:
  /// **'Who'**
  String get fitnessWho;

  /// No description provided for @fitnessWhen.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get fitnessWhen;

  /// No description provided for @fitnessFatPct.
  ///
  /// In en, this message translates to:
  /// **'Fat {value}%'**
  String fitnessFatPct(String value);

  /// No description provided for @fitnessWaterPct.
  ///
  /// In en, this message translates to:
  /// **'Water {value}%'**
  String fitnessWaterPct(String value);

  /// No description provided for @fitnessMusclePct.
  ///
  /// In en, this message translates to:
  /// **'Muscle {value} kg'**
  String fitnessMusclePct(String value);

  /// No description provided for @fitnessBmi.
  ///
  /// In en, this message translates to:
  /// **'BMI {value}'**
  String fitnessBmi(String value);

  /// No description provided for @fitnessWallTitle.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get fitnessWallTitle;

  /// No description provided for @fitnessWallNone.
  ///
  /// In en, this message translates to:
  /// **'No weight yet'**
  String get fitnessWallNone;

  /// No description provided for @fitnessProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Fitness profile'**
  String get fitnessProfileTitle;

  /// No description provided for @fitnessProfileAction.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get fitnessProfileAction;

  /// No description provided for @fitnessProfileHintTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile'**
  String get fitnessProfileHintTitle;

  /// No description provided for @fitnessProfileHintBody.
  ///
  /// In en, this message translates to:
  /// **'Add your sex, birth date and height to get body composition from the scale.'**
  String get fitnessProfileHintBody;

  /// No description provided for @fitnessSex.
  ///
  /// In en, this message translates to:
  /// **'Sex'**
  String get fitnessSex;

  /// No description provided for @fitnessSexMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get fitnessSexMale;

  /// No description provided for @fitnessSexFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get fitnessSexFemale;

  /// No description provided for @fitnessBirthDate.
  ///
  /// In en, this message translates to:
  /// **'Birth date'**
  String get fitnessBirthDate;

  /// No description provided for @fitnessBirthDateInvalid.
  ///
  /// In en, this message translates to:
  /// **'Pick a birth date in the past'**
  String get fitnessBirthDateInvalid;

  /// No description provided for @fitnessHeight.
  ///
  /// In en, this message translates to:
  /// **'Height (cm)'**
  String get fitnessHeight;

  /// No description provided for @fitnessHeightInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a height between 50 and 250 cm'**
  String get fitnessHeightInvalid;

  /// No description provided for @fitnessWeighIn.
  ///
  /// In en, this message translates to:
  /// **'Weigh in'**
  String get fitnessWeighIn;

  /// No description provided for @fitnessWeighInScanning.
  ///
  /// In en, this message translates to:
  /// **'Looking for your scale… Step on it to wake it up.'**
  String get fitnessWeighInScanning;

  /// No description provided for @fitnessWeighInConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected to {scale}'**
  String fitnessWeighInConnected(String scale);

  /// No description provided for @fitnessWeighInDone.
  ///
  /// In en, this message translates to:
  /// **'{scale}: all readings received'**
  String fitnessWeighInDone(String scale);

  /// No description provided for @fitnessWeighInNone.
  ///
  /// In en, this message translates to:
  /// **'No new readings'**
  String get fitnessWeighInNone;

  /// No description provided for @fitnessWeighInNoneHint.
  ///
  /// In en, this message translates to:
  /// **'Step on the scale, then scan again.'**
  String get fitnessWeighInNoneHint;

  /// No description provided for @fitnessWeighInScanAgain.
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get fitnessWeighInScanAgain;

  /// No description provided for @fitnessWeighInBluetoothOff.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is off. Turn it on and try again.'**
  String get fitnessWeighInBluetoothOff;

  /// No description provided for @fitnessWeighInPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission was denied. Allow it in the system settings and try again.'**
  String get fitnessWeighInPermissionDenied;

  /// No description provided for @fitnessWeighInNotFound.
  ///
  /// In en, this message translates to:
  /// **'No supported scale found nearby. Step on the scale to wake it up and try again.'**
  String get fitnessWeighInNotFound;

  /// No description provided for @fitnessWeighInFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not talk to the scale. Try again.'**
  String get fitnessWeighInFailed;

  /// No description provided for @fitnessWeighInImpedance.
  ///
  /// In en, this message translates to:
  /// **'{value} Ω'**
  String fitnessWeighInImpedance(int value);

  /// No description provided for @fitnessWeighInDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get fitnessWeighInDiscard;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pl':
      return AppLocalizationsPl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
