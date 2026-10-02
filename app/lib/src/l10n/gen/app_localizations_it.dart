// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appName => 'The Vault';

  @override
  String get tagline => 'Le tue password, al sicuro, ovunque.';

  @override
  String get start => 'Inizia';

  @override
  String get continueLabel => 'Continua';

  @override
  String get back => 'Indietro';

  @override
  String get cancel => 'Annulla';

  @override
  String get save => 'Salva';

  @override
  String get edit => 'Modifica';

  @override
  String get delete => 'Elimina';

  @override
  String get done => 'Fatto';

  @override
  String get close => 'Chiudi';

  @override
  String get retry => 'Riprova';

  @override
  String get copy => 'Copia';

  @override
  String get copied => 'Copiato';

  @override
  String get open => 'Apri';

  @override
  String genericError(String error) {
    return 'Qualcosa è andato storto: $error';
  }

  @override
  String get offlineError => 'Al momento il server non è raggiungibile.';

  @override
  String get serverTitle => 'Il tuo server';

  @override
  String get serverSubtitle =>
      'Inserisci l\'indirizzo mostrato alla fine della configurazione del server sul Mac mini.';

  @override
  String get serverHint => 'es. mac-mini.tail1234.ts.net';

  @override
  String get serverUnreachable =>
      'Server non raggiungibile. Controlla l\'indirizzo e che il Mac mini sia acceso.';

  @override
  String get serverNotVault => 'Questo non è un server The Vault.';

  @override
  String get serverInvalid => 'Indirizzo non valido.';

  @override
  String get emailTitle => 'La tua email';

  @override
  String get emailSubtitle =>
      'Ti mandiamo un codice per accedere. Su questo dispositivo lo farai una volta sola.';

  @override
  String get emailHint => 'nome@esempio.it';

  @override
  String get sendCode => 'Invia codice';

  @override
  String get emailInvalid => 'Email non valida.';

  @override
  String get mailFailed =>
      'Il server non è riuscito a inviare l\'email. Controlla le impostazioni email del server.';

  @override
  String tooManyRequests(int seconds) {
    return 'Troppi tentativi. Riprova tra $seconds s.';
  }

  @override
  String get codeTitle => 'Controlla la posta';

  @override
  String codeSubtitle(String email) {
    return 'Inserisci il codice di 6 cifre che abbiamo inviato a $email.';
  }

  @override
  String codeWrong(int left) {
    return 'Codice errato. Tentativi rimasti: $left.';
  }

  @override
  String get codeExpired => 'Il codice è scaduto. Richiedine uno nuovo.';

  @override
  String get resendCode => 'Invia un nuovo codice';

  @override
  String resendIn(int seconds) {
    return 'Nuovo codice tra $seconds s';
  }

  @override
  String get creatingVault => 'Creo la tua cassaforte…';

  @override
  String get kitTitle => 'Il tuo codice di emergenza';

  @override
  String get kitSubtitle =>
      'Conservalo in un posto sicuro: stampato, o in un luogo che non sia questo computer. Ti servirà solo se perdi l\'accesso a tutti i tuoi dispositivi. Senza questo codice e senza un dispositivo collegato, i dati non sono recuperabili.';

  @override
  String get kitSavePdf => 'Salva PDF';

  @override
  String get kitConfirm => 'Ho conservato il codice in un posto sicuro';

  @override
  String get kitPdfTitle => 'The Vault — Kit di emergenza';

  @override
  String get kitPdfAccount => 'Account';

  @override
  String get kitPdfServer => 'Server';

  @override
  String get kitPdfDate => 'Creato il';

  @override
  String get kitPdfCode => 'Codice di emergenza';

  @override
  String get kitPdfHowTo =>
      'Come si usa: su un nuovo dispositivo accedi con la tua email, poi scegli «Non ho altri dispositivi» e scrivi questo codice.';

  @override
  String get kitPdfWarning =>
      'Chi ha questo codice e accesso alla tua email può aprire la tua cassaforte. Tienilo riservato.';

  @override
  String get kitSaved => 'Kit di emergenza salvato';

  @override
  String get approvalTitle => 'Conferma questo dispositivo';

  @override
  String get approvalSubtitle =>
      'Apri The Vault su un dispositivo che usi già: ti chiederà di approvare questo accesso.';

  @override
  String get approvalWaiting => 'In attesa di approvazione…';

  @override
  String get approvalCodeHint =>
      'Controlla che sull\'altro dispositivo compaia lo stesso codice, poi approva da lì.';

  @override
  String get verificationCode => 'Codice di verifica';

  @override
  String get noOtherDevice => 'Non ho altri dispositivi';

  @override
  String get approvalRejected => 'Accesso rifiutato.';

  @override
  String get approvalExpired => 'La richiesta è scaduta.';

  @override
  String get approvalPaused =>
      'Troppe richieste rifiutate. Riprova tra un\'ora.';

  @override
  String get approvalInvalid =>
      'Qualcosa non torna: per sicurezza l\'approvazione è stata rifiutata.';

  @override
  String get startOver => 'Ricomincia';

  @override
  String get recoveryTitle => 'Codice di emergenza';

  @override
  String get recoverySubtitle =>
      'Inserisci il codice di emergenza che hai conservato quando hai creato la cassaforte.';

  @override
  String get recoveryWrong => 'Questo codice di emergenza non è corretto.';

  @override
  String get recoveryFormat =>
      'Il codice ha 24 caratteri, in gruppi di quattro.';

  @override
  String get openVault => 'Apri la cassaforte';

  @override
  String get pinTitle => 'Scegli un PIN di 6 cifre';

  @override
  String get pinSubtitle =>
      'Ti servirà per aprire The Vault quando impronta o volto non sono disponibili.';

  @override
  String get pinRepeat => 'Ripeti il PIN';

  @override
  String get pinMismatch => 'I PIN non coincidono. Riprova.';

  @override
  String biometricsTitle(String method) {
    return 'Vuoi sbloccare The Vault con $method?';
  }

  @override
  String get biometricsSubtitle =>
      'Più veloce e altrettanto sicuro. Puoi cambiarlo in Impostazioni.';

  @override
  String get enable => 'Attiva';

  @override
  String get notNow => 'Non ora';

  @override
  String get lockedTitle => 'The Vault è bloccato';

  @override
  String get unlock => 'Sblocca';

  @override
  String get usePin => 'Usa il PIN';

  @override
  String useMethod(String method) {
    return 'Usa $method';
  }

  @override
  String get pinWrong => 'PIN errato';

  @override
  String pinAttemptsLeft(int left) {
    return 'PIN errato. Tentativi rimasti: $left';
  }

  @override
  String pinWait(int seconds) {
    return 'Troppi tentativi. Attendi $seconds s.';
  }

  @override
  String get pinWiped =>
      'Troppi PIN errati: per sicurezza questo dispositivo è stato scollegato. I dati sono al sicuro sul server.';

  @override
  String pendingRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count richieste di accesso in attesa',
      one: '1 richiesta di accesso in attesa',
    );
    return '$_temp0';
  }

  @override
  String get biometricReason => 'Sblocca The Vault';

  @override
  String get sectionAll => 'Tutte';

  @override
  String get sectionFavorites => 'Preferiti';

  @override
  String get sectionTrash => 'Cestino';

  @override
  String get settings => 'Impostazioni';

  @override
  String get search => 'Cerca';

  @override
  String get newItem => 'Nuova voce';

  @override
  String get syncOk => 'Sincronizzato';

  @override
  String get syncing => 'Sincronizzazione…';

  @override
  String get syncOffline => 'Offline';

  @override
  String get syncOfflineHint =>
      'Le modifiche partiranno appena il server sarà raggiungibile.';

  @override
  String get syncError => 'Problema di sincronizzazione';

  @override
  String pendingChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count modifiche da inviare',
      one: '1 modifica da inviare',
    );
    return '$_temp0';
  }

  @override
  String get emptyAll => 'Ancora nessuna password.\nCreane una con +';

  @override
  String get emptyFavorites =>
      'Nessun preferito.\nUsa la stella per aggiungerne.';

  @override
  String get emptyTrash => 'Il cestino è vuoto';

  @override
  String noResults(String query) {
    return 'Nessun risultato per «$query»';
  }

  @override
  String get selectItem => 'Seleziona una password';

  @override
  String deletedOn(String date) {
    return 'Eliminata il $date';
  }

  @override
  String get addFavorite => 'Aggiungi ai preferiti';

  @override
  String get removeFavorite => 'Togli dai preferiti';

  @override
  String get more => 'Altro';

  @override
  String get moveToTrash => 'Sposta nel cestino';

  @override
  String get movedToTrash => 'Spostata nel cestino';

  @override
  String get undo => 'Annulla';

  @override
  String get inTrashBanner => 'Questa voce è nel cestino';

  @override
  String get restore => 'Ripristina';

  @override
  String get restored => 'Ripristinata';

  @override
  String get deleteForever => 'Elimina definitivamente';

  @override
  String deleteForeverConfirm(String title) {
    return 'Eliminare definitivamente «$title»? Non si potrà recuperare.';
  }

  @override
  String get emptyTrashAction => 'Svuota cestino';

  @override
  String emptyTrashConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Eliminare definitivamente $count voci? Non si potranno recuperare.',
      one: 'Eliminare definitivamente 1 voce? Non si potrà recuperare.',
    );
    return '$_temp0';
  }

  @override
  String get hideValue => 'Nascondi valore';

  @override
  String get showValue => 'Mostra valore';

  @override
  String get copyLink => 'Copia link';

  @override
  String get copyText => 'Copia testo';

  @override
  String get openLink => 'Apri nel browser';

  @override
  String get clipboardCleared => 'Appunti svuotati';

  @override
  String get attachments => 'Allegati';

  @override
  String get saveCopy => 'Salva una copia…';

  @override
  String get downloading => 'Download in corso…';

  @override
  String get uploading => 'Caricamento…';

  @override
  String get saved => 'Salvata';

  @override
  String get fileSaved => 'File salvato';

  @override
  String get cannotOpen => 'Non è stato possibile aprire il file.';

  @override
  String get titleHint => 'Titolo';

  @override
  String get keyHint => 'chiave';

  @override
  String get valueHint => 'valore';

  @override
  String get suggestionWebsite => 'sito web';

  @override
  String get suggestionEmail => 'email';

  @override
  String get suggestionPassword => 'password';

  @override
  String get addRow => 'Aggiungi riga';

  @override
  String get removeRow => 'Rimuovi riga';

  @override
  String get dragRow => 'Trascina per riordinare';

  @override
  String get descriptionHint => 'Descrizione';

  @override
  String get addLink => 'Collega a un indirizzo web';

  @override
  String get editLink => 'Modifica link';

  @override
  String get linkHint => 'https://…';

  @override
  String get linkInvalid => 'Questo non è un indirizzo web valido.';

  @override
  String get removeLink => 'Rimuovi link';

  @override
  String get generatePassword => 'Genera password';

  @override
  String get length => 'Lunghezza';

  @override
  String get symbols => 'Simboli';

  @override
  String get regenerate => 'Rigenera';

  @override
  String get use => 'Usa';

  @override
  String get dropFiles => 'Trascina qui i file o';

  @override
  String get chooseFiles => 'scegli…';

  @override
  String fileTooLarge(String name) {
    return '«$name» supera i 200 MB.';
  }

  @override
  String get removeAttachment => 'Rimuovi';

  @override
  String get needsTitle => 'Dai un titolo a questa voce';

  @override
  String get discardTitle => 'Vuoi scartare le modifiche?';

  @override
  String get discard => 'Scarta';

  @override
  String get keepEditing => 'Continua a modificare';

  @override
  String get editConflictTitle => 'Modificata su un altro dispositivo';

  @override
  String get editConflictBody =>
      'Questa voce è stata modificata su un altro dispositivo mentre la stavi modificando.';

  @override
  String get overwrite => 'Sovrascrivi';

  @override
  String get keepBoth => 'Tieni entrambe';

  @override
  String get conflictCopyNotice =>
      'Una voce è stata modificata su due dispositivi: ho tenuto entrambe le versioni.';

  @override
  String get conflictSuffix => ' (conflitto)';

  @override
  String get newAccessTitle => 'Nuovo accesso';

  @override
  String newAccessBody(String name, String platform) {
    return '«$name» ($platform) vuole accedere al tuo The Vault.';
  }

  @override
  String get newAccessCodeHint =>
      'Controlla che sul nuovo dispositivo compaia lo stesso codice.';

  @override
  String get newAccessWarning =>
      'Se il codice è diverso, rifiuta: qualcuno potrebbe tentare di intromettersi.';

  @override
  String get approve => 'Approva';

  @override
  String get reject => 'Rifiuta';

  @override
  String get deviceApproved => 'Dispositivo approvato';

  @override
  String get approvalHandledElsewhere =>
      'La richiesta è stata gestita da un altro dispositivo.';

  @override
  String get approvalTampered =>
      'La richiesta non torna ed è stata rifiutata per sicurezza.';

  @override
  String get waitingForDevice => 'In attesa del nuovo dispositivo…';

  @override
  String get settingsGeneral => 'Generale';

  @override
  String get settingsSecurity => 'Sicurezza';

  @override
  String get settingsDevices => 'Dispositivi';

  @override
  String get settingsBackup => 'Backup';

  @override
  String get settingsAccount => 'Account';

  @override
  String get appearance => 'Aspetto';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Chiaro';

  @override
  String get themeDark => 'Scuro';

  @override
  String get language => 'Lingua';

  @override
  String get languageSystem => 'Sistema';

  @override
  String unlockWith(String method) {
    return 'Sblocca con $method';
  }

  @override
  String get biometricsUnavailable => 'Non disponibile su questo computer';

  @override
  String get changePin => 'Cambia PIN';

  @override
  String get currentPin => 'PIN attuale';

  @override
  String get newPin => 'Nuovo PIN';

  @override
  String get pinChanged => 'PIN cambiato';

  @override
  String get autoLock => 'Blocca dopo';

  @override
  String minutesShort(int count) {
    return '$count min';
  }

  @override
  String secondsShort(int count) {
    return '$count s';
  }

  @override
  String get clipboardClear => 'Svuota appunti dopo';

  @override
  String get never => 'Mai';

  @override
  String get emergencyKit => 'Kit di emergenza';

  @override
  String get newEmergencyCode => 'Genera un nuovo codice';

  @override
  String get newEmergencyCodeConfirm =>
      'Il vecchio codice smetterà di funzionare. Continuare?';

  @override
  String get thisDevice => 'Questo dispositivo';

  @override
  String lastSeen(String date) {
    return 'Ultimo accesso $date';
  }

  @override
  String get rename => 'Rinomina';

  @override
  String get deviceName => 'Nome del dispositivo';

  @override
  String get disconnect => 'Disconnetti';

  @override
  String disconnectConfirm(String name) {
    return 'Disconnettere «$name»? Perderà subito l\'accesso.';
  }

  @override
  String get pendingDevice => 'In attesa di approvazione';

  @override
  String get exportTitle => 'Esporta…';

  @override
  String get exportSubtitle =>
      'Un file con tutte le voci e gli allegati, protetto da una password.';

  @override
  String get exportPassword => 'Password del file';

  @override
  String get exportPasswordRepeat => 'Ripeti la password';

  @override
  String get passwordTooShort => 'Troppo corta: usa almeno 10 caratteri.';

  @override
  String get passwordsDontMatch => 'Le password non coincidono.';

  @override
  String get exportDone => 'Backup salvato';

  @override
  String get exporting => 'Esportazione…';

  @override
  String get importTitle => 'Importa…';

  @override
  String get importSubtitle => 'Ripristina le voci da un file .thevault.';

  @override
  String get importPassword => 'Password del file';

  @override
  String get importWrongPassword => 'Password errata o file danneggiato.';

  @override
  String importSummary(int items, int files) {
    return '$items voci, $files allegati';
  }

  @override
  String importDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count voci importate',
      one: '1 voce importata',
    );
    return '$_temp0';
  }

  @override
  String get importing => 'Importazione…';

  @override
  String get accountEmail => 'Email';

  @override
  String get accountServer => 'Server';

  @override
  String get version => 'Versione';

  @override
  String get signOut => 'Esci da questo dispositivo';

  @override
  String get signOutConfirm =>
      'Tutti i dati di questo dispositivo verranno cancellati. Le password restano al sicuro sul server e sugli altri dispositivi.';

  @override
  String get lockNow => 'Blocca';

  @override
  String get deviceRevoked =>
      'Questo dispositivo è stato scollegato dal tuo account.';
}
