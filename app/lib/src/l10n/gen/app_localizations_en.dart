// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'The Vault';

  @override
  String get tagline => 'Your passwords, safe, everywhere.';

  @override
  String get start => 'Get started';

  @override
  String get continueLabel => 'Continue';

  @override
  String get back => 'Back';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get done => 'Done';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Try again';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get open => 'Open';

  @override
  String genericError(String error) {
    return 'Something went wrong: $error';
  }

  @override
  String get offlineError => 'The server can\'t be reached right now.';

  @override
  String get serverTitle => 'Your server';

  @override
  String get serverSubtitle =>
      'Enter the address shown at the end of the server setup on your Mac mini.';

  @override
  String get serverHint => 'e.g. mac-mini.tail1234.ts.net';

  @override
  String get serverUnreachable =>
      'Server not reachable. Check the address and that the Mac mini is on.';

  @override
  String get serverNotVault => 'This is not a The Vault server.';

  @override
  String get serverInvalid => 'This address is not valid.';

  @override
  String get emailTitle => 'Your email';

  @override
  String get emailSubtitle =>
      'We\'ll send you a code to sign in. On this device you\'ll only do it once.';

  @override
  String get emailHint => 'name@example.com';

  @override
  String get sendCode => 'Send code';

  @override
  String get emailInvalid => 'This email is not valid.';

  @override
  String get mailFailed =>
      'The server could not send the email. Check its email settings.';

  @override
  String tooManyRequests(int seconds) {
    return 'Too many attempts. Try again in $seconds s.';
  }

  @override
  String get codeTitle => 'Check your email';

  @override
  String codeSubtitle(String email) {
    return 'Enter the 6-digit code we sent to $email.';
  }

  @override
  String codeWrong(int left) {
    return 'Wrong code. Attempts left: $left.';
  }

  @override
  String get codeExpired => 'The code has expired. Request a new one.';

  @override
  String get resendCode => 'Send a new code';

  @override
  String resendIn(int seconds) {
    return 'New code in $seconds s';
  }

  @override
  String get creatingVault => 'Creating your vault…';

  @override
  String get kitTitle => 'Your emergency code';

  @override
  String get kitSubtitle =>
      'Keep it somewhere safe: printed, or anywhere that isn\'t this computer. You\'ll need it only if you lose access to all your devices. Without it, and without a connected device, your data can\'t be recovered.';

  @override
  String get kitSavePdf => 'Save PDF';

  @override
  String get kitConfirm => 'I\'ve stored the code in a safe place';

  @override
  String get kitPdfTitle => 'The Vault — Emergency kit';

  @override
  String get kitPdfAccount => 'Account';

  @override
  String get kitPdfServer => 'Server';

  @override
  String get kitPdfDate => 'Created on';

  @override
  String get kitPdfCode => 'Emergency code';

  @override
  String get kitPdfHowTo =>
      'How to use it: on a new device, sign in with your email, then choose “I don\'t have other devices” and type this code.';

  @override
  String get kitPdfWarning =>
      'Anyone with this code and access to your email can open your vault. Keep it private.';

  @override
  String get kitSaved => 'Emergency kit saved';

  @override
  String get approvalTitle => 'Confirm this device';

  @override
  String get approvalSubtitle =>
      'Open The Vault on a device you already use: it will ask you to approve this access.';

  @override
  String get approvalWaiting => 'Waiting for approval…';

  @override
  String get approvalCodeHint =>
      'Check that the other device shows the same code, then approve there.';

  @override
  String get verificationCode => 'Verification code';

  @override
  String get noOtherDevice => 'I don\'t have other devices';

  @override
  String get approvalRejected => 'Access was rejected.';

  @override
  String get approvalExpired => 'The request has expired.';

  @override
  String get approvalPaused =>
      'Too many rejected requests. Try again in an hour.';

  @override
  String get approvalInvalid =>
      'Something doesn\'t add up: the approval was refused for safety.';

  @override
  String get startOver => 'Start over';

  @override
  String get recoveryTitle => 'Emergency code';

  @override
  String get recoverySubtitle =>
      'Enter the emergency code you saved when you created your vault.';

  @override
  String get recoveryWrong => 'This emergency code is not correct.';

  @override
  String get recoveryFormat => 'The code has 24 characters, in groups of four.';

  @override
  String get openVault => 'Open the vault';

  @override
  String get pinTitle => 'Choose a 6-digit PIN';

  @override
  String get pinSubtitle =>
      'You\'ll use it to open The Vault when fingerprint or face recognition aren\'t available.';

  @override
  String get pinRepeat => 'Repeat the PIN';

  @override
  String get pinMismatch => 'The PINs don\'t match. Try again.';

  @override
  String biometricsTitle(String method) {
    return 'Unlock with $method?';
  }

  @override
  String get biometricsSubtitle =>
      'Faster and just as safe. You can change it later in Settings.';

  @override
  String get enable => 'Enable';

  @override
  String get notNow => 'Not now';

  @override
  String get lockedTitle => 'The Vault is locked';

  @override
  String get unlock => 'Unlock';

  @override
  String get usePin => 'Use PIN';

  @override
  String useMethod(String method) {
    return 'Use $method';
  }

  @override
  String get pinWrong => 'Wrong PIN';

  @override
  String pinAttemptsLeft(int left) {
    return 'Wrong PIN. Attempts left: $left';
  }

  @override
  String pinWait(int seconds) {
    return 'Too many attempts. Wait $seconds s.';
  }

  @override
  String get pinWiped =>
      'Too many wrong PINs: this device was disconnected for safety. Your data is safe on the server.';

  @override
  String pendingRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count access requests waiting',
      one: '1 access request waiting',
    );
    return '$_temp0';
  }

  @override
  String get biometricReason => 'Unlock The Vault';

  @override
  String get sectionAll => 'All';

  @override
  String get sectionFavorites => 'Favorites';

  @override
  String get sectionTrash => 'Trash';

  @override
  String get settings => 'Settings';

  @override
  String get search => 'Search';

  @override
  String get newItem => 'New entry';

  @override
  String get syncOk => 'Synced';

  @override
  String get syncing => 'Syncing…';

  @override
  String get syncOffline => 'Offline';

  @override
  String get syncOfflineHint =>
      'Changes will be sent as soon as the server is reachable.';

  @override
  String get syncError => 'Sync problem';

  @override
  String pendingChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes to send',
      one: '1 change to send',
    );
    return '$_temp0';
  }

  @override
  String get emptyAll => 'No passwords yet.\nCreate one with +';

  @override
  String get emptyFavorites => 'No favorites.\nUse the star to add one.';

  @override
  String get emptyTrash => 'The trash is empty';

  @override
  String noResults(String query) {
    return 'No results for “$query”';
  }

  @override
  String get selectItem => 'Select a password';

  @override
  String deletedOn(String date) {
    return 'Deleted on $date';
  }

  @override
  String get addFavorite => 'Add to favorites';

  @override
  String get removeFavorite => 'Remove from favorites';

  @override
  String get more => 'More';

  @override
  String get moveToTrash => 'Move to trash';

  @override
  String get movedToTrash => 'Moved to trash';

  @override
  String get undo => 'Undo';

  @override
  String get inTrashBanner => 'This entry is in the trash';

  @override
  String get restore => 'Restore';

  @override
  String get restored => 'Restored';

  @override
  String get deleteForever => 'Delete permanently';

  @override
  String deleteForeverConfirm(String title) {
    return 'Permanently delete “$title”? It can\'t be recovered.';
  }

  @override
  String get emptyTrashAction => 'Empty trash';

  @override
  String emptyTrashConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Permanently delete $count entries? They can\'t be recovered.',
      one: 'Permanently delete 1 entry? It can\'t be recovered.',
    );
    return '$_temp0';
  }

  @override
  String get hideValue => 'Hide value';

  @override
  String get showValue => 'Show value';

  @override
  String get copyLink => 'Copy link';

  @override
  String get copyText => 'Copy text';

  @override
  String get openLink => 'Open in browser';

  @override
  String get clipboardCleared => 'Clipboard cleared';

  @override
  String get attachments => 'Attachments';

  @override
  String get saveCopy => 'Save a copy…';

  @override
  String get downloading => 'Downloading…';

  @override
  String get uploading => 'Uploading…';

  @override
  String get saved => 'Saved';

  @override
  String get fileSaved => 'File saved';

  @override
  String get cannotOpen => 'The file could not be opened.';

  @override
  String get titleHint => 'Title';

  @override
  String get keyHint => 'key';

  @override
  String get valueHint => 'value';

  @override
  String get suggestionWebsite => 'website';

  @override
  String get suggestionEmail => 'email';

  @override
  String get suggestionPassword => 'password';

  @override
  String get addRow => 'Add row';

  @override
  String get removeRow => 'Remove row';

  @override
  String get dragRow => 'Drag to reorder';

  @override
  String get descriptionHint => 'Description';

  @override
  String get addLink => 'Link to a web address';

  @override
  String get editLink => 'Edit link';

  @override
  String get linkHint => 'https://…';

  @override
  String get linkInvalid => 'This is not a valid web address.';

  @override
  String get removeLink => 'Remove link';

  @override
  String get generatePassword => 'Generate password';

  @override
  String get length => 'Length';

  @override
  String get symbols => 'Symbols';

  @override
  String get regenerate => 'Regenerate';

  @override
  String get use => 'Use';

  @override
  String get dropFiles => 'Drop files here or';

  @override
  String get chooseFiles => 'choose…';

  @override
  String fileTooLarge(String name) {
    return '“$name” is larger than 200 MB.';
  }

  @override
  String get removeAttachment => 'Remove';

  @override
  String get needsTitle => 'Give this entry a title';

  @override
  String get discardTitle => 'Discard the changes?';

  @override
  String get discard => 'Discard';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get editConflictTitle => 'Changed on another device';

  @override
  String get editConflictBody =>
      'This entry was changed on another device while you were editing it.';

  @override
  String get overwrite => 'Overwrite';

  @override
  String get keepBoth => 'Keep both';

  @override
  String get conflictCopyNotice =>
      'An entry was changed on two devices: both versions were kept.';

  @override
  String get conflictSuffix => ' (conflict)';

  @override
  String get newAccessTitle => 'New access';

  @override
  String newAccessBody(String name, String platform) {
    return '“$name” ($platform) wants to access your The Vault.';
  }

  @override
  String get newAccessCodeHint =>
      'Check that the new device shows the same code.';

  @override
  String get newAccessWarning =>
      'If the code is different, reject: someone may be trying to get in.';

  @override
  String get approve => 'Approve';

  @override
  String get reject => 'Reject';

  @override
  String get deviceApproved => 'Device approved';

  @override
  String get approvalHandledElsewhere =>
      'The request was handled on another device.';

  @override
  String get approvalTampered =>
      'The request doesn\'t add up and was rejected for safety.';

  @override
  String get waitingForDevice => 'Waiting for the new device…';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsSecurity => 'Security';

  @override
  String get settingsDevices => 'Devices';

  @override
  String get settingsBackup => 'Backup';

  @override
  String get settingsAccount => 'Account';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String unlockWith(String method) {
    return 'Unlock with $method';
  }

  @override
  String get biometricsUnavailable => 'Not available on this computer';

  @override
  String get changePin => 'Change PIN';

  @override
  String get currentPin => 'Current PIN';

  @override
  String get newPin => 'New PIN';

  @override
  String get pinChanged => 'PIN changed';

  @override
  String get autoLock => 'Lock after';

  @override
  String minutesShort(int count) {
    return '$count min';
  }

  @override
  String secondsShort(int count) {
    return '$count s';
  }

  @override
  String get clipboardClear => 'Clear clipboard after';

  @override
  String get never => 'Never';

  @override
  String get emergencyKit => 'Emergency kit';

  @override
  String get newEmergencyCode => 'Generate a new code';

  @override
  String get newEmergencyCodeConfirm =>
      'The old code will stop working. Continue?';

  @override
  String get thisDevice => 'This device';

  @override
  String lastSeen(String date) {
    return 'Last seen $date';
  }

  @override
  String get rename => 'Rename';

  @override
  String get deviceName => 'Device name';

  @override
  String get disconnect => 'Disconnect';

  @override
  String disconnectConfirm(String name) {
    return 'Disconnect “$name”? It will lose access immediately.';
  }

  @override
  String get pendingDevice => 'Waiting for approval';

  @override
  String get exportTitle => 'Export…';

  @override
  String get exportSubtitle =>
      'A file with all your entries and attachments, protected by a password.';

  @override
  String get exportPassword => 'Password for the file';

  @override
  String get exportPasswordRepeat => 'Repeat the password';

  @override
  String get passwordTooShort => 'Too short: use at least 10 characters.';

  @override
  String get passwordsDontMatch => 'The passwords don\'t match.';

  @override
  String get exportDone => 'Backup saved';

  @override
  String get exporting => 'Exporting…';

  @override
  String get importTitle => 'Import…';

  @override
  String get importSubtitle => 'Restore entries from a .thevault file.';

  @override
  String get importPassword => 'File password';

  @override
  String get importWrongPassword => 'Wrong password or damaged file.';

  @override
  String importSummary(int items, int files) {
    return '$items entries, $files attachments';
  }

  @override
  String importDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries imported',
      one: '1 entry imported',
    );
    return '$_temp0';
  }

  @override
  String get importing => 'Importing…';

  @override
  String get accountEmail => 'Email';

  @override
  String get accountServer => 'Server';

  @override
  String get version => 'Version';

  @override
  String get signOut => 'Sign out of this device';

  @override
  String get signOutConfirm =>
      'All data on this device will be deleted. Your passwords stay safe on the server and on your other devices.';

  @override
  String get lockNow => 'Lock';

  @override
  String get deviceRevoked => 'This device was disconnected from your account.';
}
