import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
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
    Locale('it'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'The Vault'**
  String get appName;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Your passwords, safe, everywhere.'**
  String get tagline;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get start;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @genericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong: {error}'**
  String genericError(String error);

  /// No description provided for @offlineError.
  ///
  /// In en, this message translates to:
  /// **'The server can\'t be reached right now.'**
  String get offlineError;

  /// No description provided for @serverTitle.
  ///
  /// In en, this message translates to:
  /// **'Your server'**
  String get serverTitle;

  /// No description provided for @serverSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the address shown at the end of the server setup on your Mac mini.'**
  String get serverSubtitle;

  /// No description provided for @serverHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. mac-mini.tail1234.ts.net'**
  String get serverHint;

  /// No description provided for @serverUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Server not reachable. Check the address and that the Mac mini is on.'**
  String get serverUnreachable;

  /// No description provided for @serverNotVault.
  ///
  /// In en, this message translates to:
  /// **'This is not a The Vault server.'**
  String get serverNotVault;

  /// No description provided for @serverInvalid.
  ///
  /// In en, this message translates to:
  /// **'This address is not valid.'**
  String get serverInvalid;

  /// No description provided for @emailTitle.
  ///
  /// In en, this message translates to:
  /// **'Your email'**
  String get emailTitle;

  /// No description provided for @emailSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send you a code to sign in. On this device you\'ll only do it once.'**
  String get emailSubtitle;

  /// No description provided for @emailHint.
  ///
  /// In en, this message translates to:
  /// **'name@example.com'**
  String get emailHint;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendCode;

  /// No description provided for @emailInvalid.
  ///
  /// In en, this message translates to:
  /// **'This email is not valid.'**
  String get emailInvalid;

  /// No description provided for @mailFailed.
  ///
  /// In en, this message translates to:
  /// **'The server could not send the email. Check its email settings.'**
  String get mailFailed;

  /// No description provided for @tooManyRequests.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in {seconds} s.'**
  String tooManyRequests(int seconds);

  /// No description provided for @codeTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get codeTitle;

  /// No description provided for @codeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code we sent to {email}.'**
  String codeSubtitle(String email);

  /// No description provided for @codeWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong code. Attempts left: {left}.'**
  String codeWrong(int left);

  /// No description provided for @codeExpired.
  ///
  /// In en, this message translates to:
  /// **'The code has expired. Request a new one.'**
  String get codeExpired;

  /// No description provided for @resendCode.
  ///
  /// In en, this message translates to:
  /// **'Send a new code'**
  String get resendCode;

  /// No description provided for @resendIn.
  ///
  /// In en, this message translates to:
  /// **'New code in {seconds} s'**
  String resendIn(int seconds);

  /// No description provided for @creatingVault.
  ///
  /// In en, this message translates to:
  /// **'Creating your vault…'**
  String get creatingVault;

  /// No description provided for @kitTitle.
  ///
  /// In en, this message translates to:
  /// **'Your emergency code'**
  String get kitTitle;

  /// No description provided for @kitSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep it somewhere safe: printed, or anywhere that isn\'t this computer. You\'ll need it only if you lose access to all your devices. Without it, and without a connected device, your data can\'t be recovered.'**
  String get kitSubtitle;

  /// No description provided for @kitSavePdf.
  ///
  /// In en, this message translates to:
  /// **'Save PDF'**
  String get kitSavePdf;

  /// No description provided for @kitConfirm.
  ///
  /// In en, this message translates to:
  /// **'I\'ve stored the code in a safe place'**
  String get kitConfirm;

  /// No description provided for @kitPdfTitle.
  ///
  /// In en, this message translates to:
  /// **'The Vault — Emergency kit'**
  String get kitPdfTitle;

  /// No description provided for @kitPdfAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get kitPdfAccount;

  /// No description provided for @kitPdfServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get kitPdfServer;

  /// No description provided for @kitPdfDate.
  ///
  /// In en, this message translates to:
  /// **'Created on'**
  String get kitPdfDate;

  /// No description provided for @kitPdfCode.
  ///
  /// In en, this message translates to:
  /// **'Emergency code'**
  String get kitPdfCode;

  /// No description provided for @kitPdfHowTo.
  ///
  /// In en, this message translates to:
  /// **'How to use it: on a new device, sign in with your email, then choose “I don\'t have other devices” and type this code.'**
  String get kitPdfHowTo;

  /// No description provided for @kitPdfWarning.
  ///
  /// In en, this message translates to:
  /// **'Anyone with this code and access to your email can open your vault. Keep it private.'**
  String get kitPdfWarning;

  /// No description provided for @kitSaved.
  ///
  /// In en, this message translates to:
  /// **'Emergency kit saved'**
  String get kitSaved;

  /// No description provided for @approvalTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm this device'**
  String get approvalTitle;

  /// No description provided for @approvalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open The Vault on a device you already use: it will ask you to approve this access.'**
  String get approvalSubtitle;

  /// No description provided for @approvalWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval…'**
  String get approvalWaiting;

  /// No description provided for @approvalCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Check that the other device shows the same code, then approve there.'**
  String get approvalCodeHint;

  /// No description provided for @verificationCode.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get verificationCode;

  /// No description provided for @noOtherDevice.
  ///
  /// In en, this message translates to:
  /// **'I don\'t have other devices'**
  String get noOtherDevice;

  /// No description provided for @approvalRejected.
  ///
  /// In en, this message translates to:
  /// **'Access was rejected.'**
  String get approvalRejected;

  /// No description provided for @approvalExpired.
  ///
  /// In en, this message translates to:
  /// **'The request has expired.'**
  String get approvalExpired;

  /// No description provided for @approvalPaused.
  ///
  /// In en, this message translates to:
  /// **'Too many rejected requests. Try again in an hour.'**
  String get approvalPaused;

  /// No description provided for @approvalInvalid.
  ///
  /// In en, this message translates to:
  /// **'Something doesn\'t add up: the approval was refused for safety.'**
  String get approvalInvalid;

  /// No description provided for @startOver.
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get startOver;

  /// No description provided for @recoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Emergency code'**
  String get recoveryTitle;

  /// No description provided for @recoverySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the emergency code you saved when you created your vault.'**
  String get recoverySubtitle;

  /// No description provided for @recoveryWrong.
  ///
  /// In en, this message translates to:
  /// **'This emergency code is not correct.'**
  String get recoveryWrong;

  /// No description provided for @recoveryFormat.
  ///
  /// In en, this message translates to:
  /// **'The code has 24 characters, in groups of four.'**
  String get recoveryFormat;

  /// No description provided for @openVault.
  ///
  /// In en, this message translates to:
  /// **'Open the vault'**
  String get openVault;

  /// No description provided for @pinTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a 6-digit PIN'**
  String get pinTitle;

  /// No description provided for @pinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ll use it to open The Vault when fingerprint or face recognition aren\'t available.'**
  String get pinSubtitle;

  /// No description provided for @pinRepeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat the PIN'**
  String get pinRepeat;

  /// No description provided for @pinMismatch.
  ///
  /// In en, this message translates to:
  /// **'The PINs don\'t match. Try again.'**
  String get pinMismatch;

  /// No description provided for @biometricsTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock with {method}?'**
  String biometricsTitle(String method);

  /// No description provided for @biometricsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Faster and just as safe. You can change it later in Settings.'**
  String get biometricsSubtitle;

  /// No description provided for @enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @lockedTitle.
  ///
  /// In en, this message translates to:
  /// **'The Vault is locked'**
  String get lockedTitle;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @usePin.
  ///
  /// In en, this message translates to:
  /// **'Use PIN'**
  String get usePin;

  /// No description provided for @useMethod.
  ///
  /// In en, this message translates to:
  /// **'Use {method}'**
  String useMethod(String method);

  /// No description provided for @pinWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN'**
  String get pinWrong;

  /// No description provided for @pinAttemptsLeft.
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN. Attempts left: {left}'**
  String pinAttemptsLeft(int left);

  /// No description provided for @pinWait.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait {seconds} s.'**
  String pinWait(int seconds);

  /// No description provided for @pinWiped.
  ///
  /// In en, this message translates to:
  /// **'Too many wrong PINs: this device was disconnected for safety. Your data is safe on the server.'**
  String get pinWiped;

  /// No description provided for @pendingRequests.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 access request waiting} other{{count} access requests waiting}}'**
  String pendingRequests(int count);

  /// No description provided for @biometricReason.
  ///
  /// In en, this message translates to:
  /// **'Unlock The Vault'**
  String get biometricReason;

  /// No description provided for @sectionAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get sectionAll;

  /// No description provided for @sectionFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get sectionFavorites;

  /// No description provided for @sectionTrash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get sectionTrash;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @newItem.
  ///
  /// In en, this message translates to:
  /// **'New entry'**
  String get newItem;

  /// No description provided for @syncOk.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get syncOk;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncing;

  /// No description provided for @syncOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get syncOffline;

  /// No description provided for @syncOfflineHint.
  ///
  /// In en, this message translates to:
  /// **'Changes will be sent as soon as the server is reachable.'**
  String get syncOfflineHint;

  /// No description provided for @syncError.
  ///
  /// In en, this message translates to:
  /// **'Sync problem'**
  String get syncError;

  /// No description provided for @pendingChanges.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change to send} other{{count} changes to send}}'**
  String pendingChanges(int count);

  /// No description provided for @emptyAll.
  ///
  /// In en, this message translates to:
  /// **'No passwords yet.\nCreate one with +'**
  String get emptyAll;

  /// No description provided for @emptyFavorites.
  ///
  /// In en, this message translates to:
  /// **'No favorites.\nUse the star to add one.'**
  String get emptyFavorites;

  /// No description provided for @emptyTrash.
  ///
  /// In en, this message translates to:
  /// **'The trash is empty'**
  String get emptyTrash;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results for “{query}”'**
  String noResults(String query);

  /// No description provided for @selectItem.
  ///
  /// In en, this message translates to:
  /// **'Select a password'**
  String get selectItem;

  /// No description provided for @deletedOn.
  ///
  /// In en, this message translates to:
  /// **'Deleted on {date}'**
  String deletedOn(String date);

  /// No description provided for @addFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get addFavorite;

  /// No description provided for @removeFavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get removeFavorite;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @moveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to trash'**
  String get moveToTrash;

  /// No description provided for @movedToTrash.
  ///
  /// In en, this message translates to:
  /// **'Moved to trash'**
  String get movedToTrash;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @inTrashBanner.
  ///
  /// In en, this message translates to:
  /// **'This entry is in the trash'**
  String get inTrashBanner;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @restored.
  ///
  /// In en, this message translates to:
  /// **'Restored'**
  String get restored;

  /// No description provided for @deleteForever.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get deleteForever;

  /// No description provided for @deleteForeverConfirm.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete “{title}”? It can\'t be recovered.'**
  String deleteForeverConfirm(String title);

  /// No description provided for @emptyTrashAction.
  ///
  /// In en, this message translates to:
  /// **'Empty trash'**
  String get emptyTrashAction;

  /// No description provided for @emptyTrashConfirm.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Permanently delete 1 entry? It can\'t be recovered.} other{Permanently delete {count} entries? They can\'t be recovered.}}'**
  String emptyTrashConfirm(int count);

  /// No description provided for @hideValue.
  ///
  /// In en, this message translates to:
  /// **'Hide value'**
  String get hideValue;

  /// No description provided for @showValue.
  ///
  /// In en, this message translates to:
  /// **'Show value'**
  String get showValue;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @copyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get copyText;

  /// No description provided for @openLink.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get openLink;

  /// No description provided for @clipboardCleared.
  ///
  /// In en, this message translates to:
  /// **'Clipboard cleared'**
  String get clipboardCleared;

  /// No description provided for @attachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachments;

  /// No description provided for @saveCopy.
  ///
  /// In en, this message translates to:
  /// **'Save a copy…'**
  String get saveCopy;

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get downloading;

  /// No description provided for @uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get uploading;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @fileSaved.
  ///
  /// In en, this message translates to:
  /// **'File saved'**
  String get fileSaved;

  /// No description provided for @cannotOpen.
  ///
  /// In en, this message translates to:
  /// **'The file could not be opened.'**
  String get cannotOpen;

  /// No description provided for @titleHint.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleHint;

  /// No description provided for @keyHint.
  ///
  /// In en, this message translates to:
  /// **'key'**
  String get keyHint;

  /// No description provided for @valueHint.
  ///
  /// In en, this message translates to:
  /// **'value'**
  String get valueHint;

  /// No description provided for @suggestionWebsite.
  ///
  /// In en, this message translates to:
  /// **'website'**
  String get suggestionWebsite;

  /// No description provided for @suggestionEmail.
  ///
  /// In en, this message translates to:
  /// **'email'**
  String get suggestionEmail;

  /// No description provided for @suggestionPassword.
  ///
  /// In en, this message translates to:
  /// **'password'**
  String get suggestionPassword;

  /// No description provided for @addRow.
  ///
  /// In en, this message translates to:
  /// **'Add row'**
  String get addRow;

  /// No description provided for @removeRow.
  ///
  /// In en, this message translates to:
  /// **'Remove row'**
  String get removeRow;

  /// No description provided for @dragRow.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get dragRow;

  /// No description provided for @descriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionHint;

  /// No description provided for @addLink.
  ///
  /// In en, this message translates to:
  /// **'Link to a web address'**
  String get addLink;

  /// No description provided for @editLink.
  ///
  /// In en, this message translates to:
  /// **'Edit link'**
  String get editLink;

  /// No description provided for @linkHint.
  ///
  /// In en, this message translates to:
  /// **'https://…'**
  String get linkHint;

  /// No description provided for @linkInvalid.
  ///
  /// In en, this message translates to:
  /// **'This is not a valid web address.'**
  String get linkInvalid;

  /// No description provided for @removeLink.
  ///
  /// In en, this message translates to:
  /// **'Remove link'**
  String get removeLink;

  /// No description provided for @generatePassword.
  ///
  /// In en, this message translates to:
  /// **'Generate password'**
  String get generatePassword;

  /// No description provided for @length.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get length;

  /// No description provided for @symbols.
  ///
  /// In en, this message translates to:
  /// **'Symbols'**
  String get symbols;

  /// No description provided for @regenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get regenerate;

  /// No description provided for @use.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get use;

  /// No description provided for @dropFiles.
  ///
  /// In en, this message translates to:
  /// **'Drop files here or'**
  String get dropFiles;

  /// No description provided for @chooseFiles.
  ///
  /// In en, this message translates to:
  /// **'choose…'**
  String get chooseFiles;

  /// No description provided for @fileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'“{name}” is larger than 200 MB.'**
  String fileTooLarge(String name);

  /// No description provided for @removeAttachment.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeAttachment;

  /// No description provided for @needsTitle.
  ///
  /// In en, this message translates to:
  /// **'Give this entry a title'**
  String get needsTitle;

  /// No description provided for @discardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard the changes?'**
  String get discardTitle;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @editConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Changed on another device'**
  String get editConflictTitle;

  /// No description provided for @editConflictBody.
  ///
  /// In en, this message translates to:
  /// **'This entry was changed on another device while you were editing it.'**
  String get editConflictBody;

  /// No description provided for @overwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get overwrite;

  /// No description provided for @keepBoth.
  ///
  /// In en, this message translates to:
  /// **'Keep both'**
  String get keepBoth;

  /// No description provided for @conflictCopyNotice.
  ///
  /// In en, this message translates to:
  /// **'An entry was changed on two devices: both versions were kept.'**
  String get conflictCopyNotice;

  /// No description provided for @conflictSuffix.
  ///
  /// In en, this message translates to:
  /// **' (conflict)'**
  String get conflictSuffix;

  /// No description provided for @newAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'New access'**
  String get newAccessTitle;

  /// No description provided for @newAccessBody.
  ///
  /// In en, this message translates to:
  /// **'“{name}” ({platform}) wants to access your The Vault.'**
  String newAccessBody(String name, String platform);

  /// No description provided for @newAccessCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Check that the new device shows the same code.'**
  String get newAccessCodeHint;

  /// No description provided for @newAccessWarning.
  ///
  /// In en, this message translates to:
  /// **'If the code is different, reject: someone may be trying to get in.'**
  String get newAccessWarning;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @deviceApproved.
  ///
  /// In en, this message translates to:
  /// **'Device approved'**
  String get deviceApproved;

  /// No description provided for @approvalHandledElsewhere.
  ///
  /// In en, this message translates to:
  /// **'The request was handled on another device.'**
  String get approvalHandledElsewhere;

  /// No description provided for @approvalTampered.
  ///
  /// In en, this message translates to:
  /// **'The request doesn\'t add up and was rejected for safety.'**
  String get approvalTampered;

  /// No description provided for @waitingForDevice.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the new device…'**
  String get waitingForDevice;

  /// No description provided for @settingsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneral;

  /// No description provided for @settingsSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurity;

  /// No description provided for @settingsDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get settingsDevices;

  /// No description provided for @settingsBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get settingsBackup;

  /// No description provided for @settingsAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccount;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @unlockWith.
  ///
  /// In en, this message translates to:
  /// **'Unlock with {method}'**
  String unlockWith(String method);

  /// No description provided for @biometricsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not available on this computer'**
  String get biometricsUnavailable;

  /// No description provided for @changePin.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get changePin;

  /// No description provided for @currentPin.
  ///
  /// In en, this message translates to:
  /// **'Current PIN'**
  String get currentPin;

  /// No description provided for @newPin.
  ///
  /// In en, this message translates to:
  /// **'New PIN'**
  String get newPin;

  /// No description provided for @pinChanged.
  ///
  /// In en, this message translates to:
  /// **'PIN changed'**
  String get pinChanged;

  /// No description provided for @autoLock.
  ///
  /// In en, this message translates to:
  /// **'Lock after'**
  String get autoLock;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String minutesShort(int count);

  /// No description provided for @secondsShort.
  ///
  /// In en, this message translates to:
  /// **'{count} s'**
  String secondsShort(int count);

  /// No description provided for @clipboardClear.
  ///
  /// In en, this message translates to:
  /// **'Clear clipboard after'**
  String get clipboardClear;

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// No description provided for @emergencyKit.
  ///
  /// In en, this message translates to:
  /// **'Emergency kit'**
  String get emergencyKit;

  /// No description provided for @newEmergencyCode.
  ///
  /// In en, this message translates to:
  /// **'Generate a new code'**
  String get newEmergencyCode;

  /// No description provided for @newEmergencyCodeConfirm.
  ///
  /// In en, this message translates to:
  /// **'The old code will stop working. Continue?'**
  String get newEmergencyCodeConfirm;

  /// No description provided for @thisDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get thisDevice;

  /// No description provided for @lastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen {date}'**
  String lastSeen(String date);

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @deviceName.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get deviceName;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @disconnectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Disconnect “{name}”? It will lose access immediately.'**
  String disconnectConfirm(String name);

  /// No description provided for @pendingDevice.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get pendingDevice;

  /// No description provided for @exportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export…'**
  String get exportTitle;

  /// No description provided for @exportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A file with all your entries and attachments, protected by a password.'**
  String get exportSubtitle;

  /// No description provided for @exportPassword.
  ///
  /// In en, this message translates to:
  /// **'Password for the file'**
  String get exportPassword;

  /// No description provided for @exportPasswordRepeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat the password'**
  String get exportPasswordRepeat;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Too short: use at least 10 characters.'**
  String get passwordTooShort;

  /// No description provided for @passwordsDontMatch.
  ///
  /// In en, this message translates to:
  /// **'The passwords don\'t match.'**
  String get passwordsDontMatch;

  /// No description provided for @exportDone.
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get exportDone;

  /// No description provided for @exporting.
  ///
  /// In en, this message translates to:
  /// **'Exporting…'**
  String get exporting;

  /// No description provided for @importTitle.
  ///
  /// In en, this message translates to:
  /// **'Import…'**
  String get importTitle;

  /// No description provided for @importSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Restore entries from a .thevault file.'**
  String get importSubtitle;

  /// No description provided for @importPassword.
  ///
  /// In en, this message translates to:
  /// **'File password'**
  String get importPassword;

  /// No description provided for @importWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong password or damaged file.'**
  String get importWrongPassword;

  /// No description provided for @importSummary.
  ///
  /// In en, this message translates to:
  /// **'{items} entries, {files} attachments'**
  String importSummary(int items, int files);

  /// No description provided for @importDone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entry imported} other{{count} entries imported}}'**
  String importDone(int count);

  /// No description provided for @importing.
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get importing;

  /// No description provided for @accountEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get accountEmail;

  /// No description provided for @accountServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get accountServer;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out of this device'**
  String get signOut;

  /// No description provided for @signOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'All data on this device will be deleted. Your passwords stay safe on the server and on your other devices.'**
  String get signOutConfirm;

  /// No description provided for @lockNow.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get lockNow;

  /// No description provided for @deviceRevoked.
  ///
  /// In en, this message translates to:
  /// **'This device was disconnected from your account.'**
  String get deviceRevoked;
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
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
