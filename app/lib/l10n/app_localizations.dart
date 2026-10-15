import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

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
    Locale('es'),
  ];

  /// No description provided for @aboutVersion.
  ///
  /// In es, this message translates to:
  /// **'OpenWard {version}'**
  String aboutVersion(String version);

  /// No description provided for @accessibility.
  ///
  /// In es, this message translates to:
  /// **'Accesibilidad'**
  String get accessibility;

  /// No description provided for @add.
  ///
  /// In es, this message translates to:
  /// **'Añadir'**
  String get add;

  /// No description provided for @addSavedHost.
  ///
  /// In es, this message translates to:
  /// **'Añadir un host guardado'**
  String get addSavedHost;

  /// No description provided for @addTag.
  ///
  /// In es, this message translates to:
  /// **'Añadir'**
  String get addTag;

  /// No description provided for @address.
  ///
  /// In es, this message translates to:
  /// **'Dirección'**
  String get address;

  /// No description provided for @addressHint.
  ///
  /// In es, this message translates to:
  /// **'servidor.example.com o 10.0.0.5'**
  String get addressHint;

  /// No description provided for @agent.
  ///
  /// In es, this message translates to:
  /// **'Agente SSH'**
  String get agent;

  /// No description provided for @agentNone.
  ///
  /// In es, this message translates to:
  /// **'Ninguno'**
  String get agentNone;

  /// No description provided for @agentSocket.
  ///
  /// In es, this message translates to:
  /// **'Otro socket…'**
  String get agentSocket;

  /// No description provided for @agentSystem.
  ///
  /// In es, this message translates to:
  /// **'El del sistema'**
  String get agentSystem;

  /// No description provided for @alreadyImported.
  ///
  /// In es, this message translates to:
  /// **'ya importado'**
  String get alreadyImported;

  /// No description provided for @appearanceStepBody.
  ///
  /// In es, this message translates to:
  /// **'Puedes cambiarlo cuando quieras en Ajustes.'**
  String get appearanceStepBody;

  /// No description provided for @appearanceStepTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Cómo la quieres ver?'**
  String get appearanceStepTitle;

  /// No description provided for @apply.
  ///
  /// In es, this message translates to:
  /// **'Aplicar'**
  String get apply;

  /// No description provided for @asSystem.
  ///
  /// In es, this message translates to:
  /// **'Como el sistema'**
  String get asSystem;

  /// No description provided for @back.
  ///
  /// In es, this message translates to:
  /// **'Atrás'**
  String get back;

  /// No description provided for @bellFlash.
  ///
  /// In es, this message translates to:
  /// **'Destello con la campana'**
  String get bellFlash;

  /// No description provided for @bellFlashHelp.
  ///
  /// In es, this message translates to:
  /// **'Cuando un programa hace sonar la campana. Si la pestaña no está delante, se marca igualmente.'**
  String get bellFlashHelp;

  /// No description provided for @bellRang.
  ///
  /// In es, this message translates to:
  /// **'Ha sonado la campana'**
  String get bellRang;

  /// No description provided for @broadcastBanner.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Broadcast: lo que escribas va a 1 de {total} paneles ({names}).} other{Broadcast: lo que escribas va a {count} de {total} paneles ({names}).}}'**
  String broadcastBanner(int count, int total, String names);

  /// No description provided for @broadcastExit.
  ///
  /// In es, this message translates to:
  /// **'Salir {keys}'**
  String broadcastExit(String keys);

  /// No description provided for @broadcastOff.
  ///
  /// In es, this message translates to:
  /// **'Apagar el broadcast'**
  String get broadcastOff;

  /// No description provided for @broadcastOn.
  ///
  /// In es, this message translates to:
  /// **'Broadcast en esta pestaña'**
  String get broadcastOn;

  /// No description provided for @broadcastPasteAlways.
  ///
  /// In es, this message translates to:
  /// **'Con broadcast, pegar siempre lo pregunta, aunque sea una línea.'**
  String get broadcastPasteAlways;

  /// No description provided for @broadcastPasteBody.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Va a {names}. Es 1 línea.} other{Va a {names}. Son {count} líneas, y cada una puede ejecutarse al llegar.}}'**
  String broadcastPasteBody(int count, String names);

  /// No description provided for @broadcastPasteTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Pegar en {total} paneles a la vez?'**
  String broadcastPasteTitle(int total);

  /// No description provided for @broadcastStatus.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Broadcast · 1 panel} other{Broadcast · {count} paneles}}'**
  String broadcastStatus(int count);

  /// No description provided for @cancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get cancel;

  /// No description provided for @cancelThese.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{No copiar este} other{No copiar estos {count}}}'**
  String cancelThese(int count);

  /// No description provided for @cancelled.
  ///
  /// In es, this message translates to:
  /// **'Cancelado.'**
  String get cancelled;

  /// No description provided for @cannotConnect.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido conectar con {label}'**
  String cannotConnect(String label);

  /// No description provided for @change.
  ///
  /// In es, this message translates to:
  /// **'Cambiar'**
  String get change;

  /// No description provided for @changedMeanwhile.
  ///
  /// In es, this message translates to:
  /// **'Otro cambio ha llegado antes: cierra y vuelve a abrir el editor.'**
  String get changedMeanwhile;

  /// No description provided for @checkedFingerprint.
  ///
  /// In es, this message translates to:
  /// **'He comprobado la huella nueva'**
  String get checkedFingerprint;

  /// No description provided for @choiceKeepBoth.
  ///
  /// In es, this message translates to:
  /// **'Mantener los dos'**
  String get choiceKeepBoth;

  /// No description provided for @choiceNewer.
  ///
  /// In es, this message translates to:
  /// **'Solo si el mío es más nuevo'**
  String get choiceNewer;

  /// No description provided for @choiceReplace.
  ///
  /// In es, this message translates to:
  /// **'Reemplazar'**
  String get choiceReplace;

  /// No description provided for @choiceSkip.
  ///
  /// In es, this message translates to:
  /// **'Saltar'**
  String get choiceSkip;

  /// No description provided for @cipher.
  ///
  /// In es, this message translates to:
  /// **'Cifrado'**
  String get cipher;

  /// No description provided for @clear.
  ///
  /// In es, this message translates to:
  /// **'Quitar'**
  String get clear;

  /// No description provided for @clearFinished.
  ///
  /// In es, this message translates to:
  /// **'Quitar las terminadas'**
  String get clearFinished;

  /// No description provided for @clearSelection.
  ///
  /// In es, this message translates to:
  /// **'Quitar la selección'**
  String get clearSelection;

  /// No description provided for @close.
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get close;

  /// No description provided for @closePane.
  ///
  /// In es, this message translates to:
  /// **'Cerrar el panel'**
  String get closePane;

  /// No description provided for @closeTab.
  ///
  /// In es, this message translates to:
  /// **'Cerrar la pestaña'**
  String get closeTab;

  /// No description provided for @closeTheTab.
  ///
  /// In es, this message translates to:
  /// **'Cerrar la pestaña'**
  String get closeTheTab;

  /// No description provided for @colModified.
  ///
  /// In es, this message translates to:
  /// **'Modificado'**
  String get colModified;

  /// No description provided for @colName.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get colName;

  /// No description provided for @colPermissions.
  ///
  /// In es, this message translates to:
  /// **'Permisos'**
  String get colPermissions;

  /// No description provided for @colSize.
  ///
  /// In es, this message translates to:
  /// **'Tamaño'**
  String get colSize;

  /// No description provided for @conflictChoose.
  ///
  /// In es, this message translates to:
  /// **'. Elige qué hacer con cada uno:'**
  String get conflictChoose;

  /// No description provided for @conflictFile.
  ///
  /// In es, this message translates to:
  /// **'Fichero'**
  String get conflictFile;

  /// No description provided for @conflictFolder.
  ///
  /// In es, this message translates to:
  /// **'carpeta'**
  String get conflictFolder;

  /// No description provided for @conflictIn.
  ///
  /// In es, this message translates to:
  /// **'En '**
  String get conflictIn;

  /// No description provided for @conflictMerge.
  ///
  /// In es, this message translates to:
  /// **'las dos carpetas se juntan'**
  String get conflictMerge;

  /// No description provided for @conflictRest.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{. El otro se copia ya. Elige qué hacer con cada uno:} other{. Los otros {count} se copian ya. Elige qué hacer con cada uno:}}'**
  String conflictRest(int count);

  /// No description provided for @conflictSame.
  ///
  /// In es, this message translates to:
  /// **'igual tamaño y fecha'**
  String get conflictSame;

  /// No description provided for @conflictTheirs.
  ///
  /// In es, this message translates to:
  /// **'En {where}'**
  String conflictTheirs(String where);

  /// No description provided for @conflictTheirsNewer.
  ///
  /// In es, this message translates to:
  /// **'el de {where} es más nuevo'**
  String conflictTheirsNewer(String where);

  /// No description provided for @conflictTitle.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 de los {total} ya existe en {where}} other{{count} de los {total} ya existen en {where}}}'**
  String conflictTitle(int count, int total, String where);

  /// No description provided for @conflictTitleOne.
  ///
  /// In es, this message translates to:
  /// **'Ya existe en {where}'**
  String conflictTitleOne(String where);

  /// No description provided for @conflictWhat.
  ///
  /// In es, this message translates to:
  /// **'Qué hacer'**
  String get conflictWhat;

  /// No description provided for @conflictYours.
  ///
  /// In es, this message translates to:
  /// **'El tuyo'**
  String get conflictYours;

  /// No description provided for @conflictYoursNewer.
  ///
  /// In es, this message translates to:
  /// **'el tuyo es más nuevo'**
  String get conflictYoursNewer;

  /// No description provided for @connect.
  ///
  /// In es, this message translates to:
  /// **'Conectar'**
  String get connect;

  /// No description provided for @connectingEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Conectando…'**
  String get connectingEllipsis;

  /// No description provided for @connectingTo.
  ///
  /// In es, this message translates to:
  /// **'Conectando con {label}'**
  String connectingTo(String label);

  /// No description provided for @connectionDetails.
  ///
  /// In es, this message translates to:
  /// **'Detalles de la conexión'**
  String get connectionDetails;

  /// No description provided for @connectionHint.
  ///
  /// In es, this message translates to:
  /// **'Lo que no cambies aquí se hereda. Debajo de cada valor ves de dónde viene; los heredados llevan el borde discontinuo.'**
  String get connectionHint;

  /// No description provided for @connectionLost.
  ///
  /// In es, this message translates to:
  /// **'Se perdió la conexión con {label}{why}.'**
  String connectionLost(String label, String why);

  /// No description provided for @continueAction.
  ///
  /// In es, this message translates to:
  /// **'Seguir'**
  String get continueAction;

  /// No description provided for @continueLabel.
  ///
  /// In es, this message translates to:
  /// **'Continuar'**
  String get continueLabel;

  /// No description provided for @contrastFails.
  ///
  /// In es, this message translates to:
  /// **'Contraste del texto {ratio}:1. No llega a AA (4,5:1).'**
  String contrastFails(String ratio);

  /// No description provided for @contrastPasses.
  ///
  /// In es, this message translates to:
  /// **'Contraste del texto {ratio}:1. Cumple AA.'**
  String contrastPasses(String ratio);

  /// No description provided for @contrastWarning.
  ///
  /// In es, this message translates to:
  /// **'Con esta combinación, parte del texto no llega al contraste recomendado (queda en {ratio}:1).'**
  String contrastWarning(String ratio);

  /// No description provided for @copy.
  ///
  /// In es, this message translates to:
  /// **'Copiar'**
  String get copy;

  /// No description provided for @copyFingerprint.
  ///
  /// In es, this message translates to:
  /// **'Copiar la huella'**
  String get copyFingerprint;

  /// No description provided for @copyPath.
  ///
  /// In es, this message translates to:
  /// **'Copiar la ruta'**
  String get copyPath;

  /// No description provided for @create.
  ///
  /// In es, this message translates to:
  /// **'Crear'**
  String get create;

  /// No description provided for @ctrlShiftPrefix.
  ///
  /// In es, this message translates to:
  /// **'Ctrl+Mayús+'**
  String get ctrlShiftPrefix;

  /// No description provided for @cursor.
  ///
  /// In es, this message translates to:
  /// **'Cursor'**
  String get cursor;

  /// No description provided for @cursorBar.
  ///
  /// In es, this message translates to:
  /// **'Barra'**
  String get cursorBar;

  /// No description provided for @cursorBlink.
  ///
  /// In es, this message translates to:
  /// **'Cursor parpadeante'**
  String get cursorBlink;

  /// No description provided for @cursorBlock.
  ///
  /// In es, this message translates to:
  /// **'Bloque'**
  String get cursorBlock;

  /// No description provided for @cursorHelp.
  ///
  /// In es, this message translates to:
  /// **'Mientras el programa no pida otro.'**
  String get cursorHelp;

  /// No description provided for @cursorUnderline.
  ///
  /// In es, this message translates to:
  /// **'Línea'**
  String get cursorUnderline;

  /// No description provided for @customize.
  ///
  /// In es, this message translates to:
  /// **'Personalizar {name}'**
  String customize(String name);

  /// No description provided for @customizeHint.
  ///
  /// In es, this message translates to:
  /// **'Cambia una capa y el resto se queda igual. Los cambios son solo de este tema.'**
  String get customizeHint;

  /// No description provided for @defaultKeys.
  ///
  /// In es, this message translates to:
  /// **'~/.ssh/id_ed25519, id_ecdsa, id_rsa (las habituales)'**
  String get defaultKeys;

  /// No description provided for @delete.
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get delete;

  /// No description provided for @deleteEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Eliminar…'**
  String get deleteEllipsis;

  /// No description provided for @deleteFailed.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido eliminar: {error}'**
  String deleteFailed(String error);

  /// No description provided for @deleteGroup.
  ///
  /// In es, this message translates to:
  /// **'Eliminar grupo'**
  String get deleteGroup;

  /// No description provided for @deleteGroupBody.
  ///
  /// In es, this message translates to:
  /// **'Lo que contiene pasa a su grupo padre.'**
  String get deleteGroupBody;

  /// No description provided for @deleteGroupTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar el grupo «{name}»?'**
  String deleteGroupTitle(String name);

  /// No description provided for @deleteHostBody.
  ///
  /// In es, this message translates to:
  /// **'Desaparece de la lista. Esto no se puede deshacer.'**
  String get deleteHostBody;

  /// No description provided for @deleteHostTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar el host «{name}»?'**
  String deleteHostTitle(String name);

  /// No description provided for @deleteLocalBody.
  ///
  /// In es, this message translates to:
  /// **'Se eliminan de este equipo sin pasar por la papelera: no se puede deshacer.'**
  String get deleteLocalBody;

  /// No description provided for @deleteMany.
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar {count} elementos?'**
  String deleteMany(int count);

  /// No description provided for @deleteOne.
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar {name}?'**
  String deleteOne(String name);

  /// No description provided for @deleteRemoteBody.
  ///
  /// In es, this message translates to:
  /// **'Se eliminan en {host}. En el servidor no hay papelera: no se puede deshacer.'**
  String deleteRemoteBody(String host);

  /// No description provided for @deletedHost.
  ///
  /// In es, this message translates to:
  /// **'(host eliminado)'**
  String get deletedHost;

  /// No description provided for @destination.
  ///
  /// In es, this message translates to:
  /// **'Destino'**
  String get destination;

  /// No description provided for @dontTrust.
  ///
  /// In es, this message translates to:
  /// **'No confiar'**
  String get dontTrust;

  /// No description provided for @download.
  ///
  /// In es, this message translates to:
  /// **'Descarga'**
  String get download;

  /// No description provided for @downloadArrow.
  ///
  /// In es, this message translates to:
  /// **'← Descargar'**
  String get downloadArrow;

  /// No description provided for @downloadTo.
  ///
  /// In es, this message translates to:
  /// **'Descargar a {path}'**
  String downloadTo(String path);

  /// No description provided for @dropAskFirst.
  ///
  /// In es, this message translates to:
  /// **'Si alguno ya existe, te preguntamos antes de tocarlo.'**
  String get dropAskFirst;

  /// No description provided for @dropToDownload.
  ///
  /// In es, this message translates to:
  /// **'Suelta para descargar aquí'**
  String get dropToDownload;

  /// No description provided for @dropToUpload.
  ///
  /// In es, this message translates to:
  /// **'Suelta para subir aquí'**
  String get dropToUpload;

  /// No description provided for @editEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Editar…'**
  String get editEllipsis;

  /// No description provided for @editGroup.
  ///
  /// In es, this message translates to:
  /// **'Editar grupo…'**
  String get editGroup;

  /// No description provided for @editGroupTitle.
  ///
  /// In es, this message translates to:
  /// **'Editar grupo'**
  String get editGroupTitle;

  /// No description provided for @editHostTitle.
  ///
  /// In es, this message translates to:
  /// **'Editar host'**
  String get editHostTitle;

  /// No description provided for @emptyFolder.
  ///
  /// In es, this message translates to:
  /// **'Esta carpeta está vacía'**
  String get emptyFolder;

  /// No description provided for @failureAuth.
  ///
  /// In es, this message translates to:
  /// **'{user}@{label} no ha podido autenticarse.'**
  String failureAuth(String user, String label);

  /// No description provided for @failureAuthMethods.
  ///
  /// In es, this message translates to:
  /// **'{user}@{label} no ha podido autenticarse (el servidor acepta: {methods}).'**
  String failureAuthMethods(String user, String label, String methods);

  /// No description provided for @failureBadCertificate.
  ///
  /// In es, this message translates to:
  /// **'El certificado de {label} no es válido: {reason}.'**
  String failureBadCertificate(String label, String reason);

  /// No description provided for @failureHostKeyChanged.
  ///
  /// In es, this message translates to:
  /// **'La clave de {label} ha cambiado (ahora {fingerprint}). Puede ser un ataque: no se ha conectado.'**
  String failureHostKeyChanged(String label, String fingerprint);

  /// No description provided for @failureHostKeyRejected.
  ///
  /// In es, this message translates to:
  /// **'No se ha confiado en la clave de {label}.'**
  String failureHostKeyRejected(String label);

  /// No description provided for @failureNoSftp.
  ///
  /// In es, this message translates to:
  /// **'{label} no tiene SFTP: al servidor le falta sftp-server.'**
  String failureNoSftp(String label);

  /// No description provided for @fileChanged.
  ///
  /// In es, this message translates to:
  /// **'{path} cambió mientras se copiaba.'**
  String fileChanged(String path);

  /// No description provided for @fileDenied.
  ///
  /// In es, this message translates to:
  /// **'Sin permiso: {path}'**
  String fileDenied(String path);

  /// No description provided for @fileExists.
  ///
  /// In es, this message translates to:
  /// **'Ya existe: {path}'**
  String fileExists(String path);

  /// No description provided for @fileLost.
  ///
  /// In es, this message translates to:
  /// **'Se perdió la conexión.'**
  String get fileLost;

  /// No description provided for @fileNotFound.
  ///
  /// In es, this message translates to:
  /// **'No existe: {path}'**
  String fileNotFound(String path);

  /// No description provided for @filterFolder.
  ///
  /// In es, this message translates to:
  /// **'Filtrar en esta carpeta'**
  String get filterFolder;

  /// No description provided for @findClose.
  ///
  /// In es, this message translates to:
  /// **'Cerrar la búsqueda (Esc)'**
  String get findClose;

  /// No description provided for @findCount.
  ///
  /// In es, this message translates to:
  /// **'{selected} de {total}'**
  String findCount(int selected, int total);

  /// No description provided for @findHint.
  ///
  /// In es, this message translates to:
  /// **'Buscar en el terminal'**
  String get findHint;

  /// No description provided for @findNewer.
  ///
  /// In es, this message translates to:
  /// **'Siguiente, más abajo (Mayús+Intro)'**
  String get findNewer;

  /// No description provided for @findOlder.
  ///
  /// In es, this message translates to:
  /// **'Anterior, más arriba (Intro)'**
  String get findOlder;

  /// No description provided for @findTotal.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0{Sin resultados} =1{1 resultado} other{{count} resultados}}'**
  String findTotal(int count);

  /// No description provided for @fingerprint.
  ///
  /// In es, this message translates to:
  /// **'Huella'**
  String get fingerprint;

  /// No description provided for @firstConnectionTo.
  ///
  /// In es, this message translates to:
  /// **'Primera conexión con {label}'**
  String firstConnectionTo(String label);

  /// No description provided for @fontFromTheme.
  ///
  /// In es, this message translates to:
  /// **'La del tema'**
  String get fontFromTheme;

  /// No description provided for @fontOther.
  ///
  /// In es, this message translates to:
  /// **'Otra fuente instalada…'**
  String get fontOther;

  /// No description provided for @fontOtherHint.
  ///
  /// In es, this message translates to:
  /// **'Su nombre exacto, como «Fira Code»'**
  String get fontOtherHint;

  /// No description provided for @fontOtherTitle.
  ///
  /// In es, this message translates to:
  /// **'Otra fuente instalada'**
  String get fontOtherTitle;

  /// No description provided for @fontSize.
  ///
  /// In es, this message translates to:
  /// **'Tamaño de letra'**
  String get fontSize;

  /// No description provided for @fontSystem.
  ///
  /// In es, this message translates to:
  /// **'La del sistema'**
  String get fontSystem;

  /// No description provided for @forAll.
  ///
  /// In es, this message translates to:
  /// **'A todos:'**
  String get forAll;

  /// No description provided for @fromDefault.
  ///
  /// In es, this message translates to:
  /// **'Valor por defecto'**
  String get fromDefault;

  /// No description provided for @fromGroup.
  ///
  /// In es, this message translates to:
  /// **'Del grupo {name}'**
  String fromGroup(String name);

  /// No description provided for @fromNowhere.
  ///
  /// In es, this message translates to:
  /// **'Sin valor: lo decide la conexión'**
  String get fromNowhere;

  /// No description provided for @group.
  ///
  /// In es, this message translates to:
  /// **'Grupo'**
  String get group;

  /// No description provided for @groupInsideItself.
  ///
  /// In es, this message translates to:
  /// **'Un grupo no puede estar dentro de sí mismo.'**
  String get groupInsideItself;

  /// No description provided for @groupNeedsName.
  ///
  /// In es, this message translates to:
  /// **'El grupo necesita un nombre.'**
  String get groupNeedsName;

  /// No description provided for @groupSettingsSection.
  ///
  /// In es, this message translates to:
  /// **'Ajustes para todo lo que contiene'**
  String get groupSettingsSection;

  /// No description provided for @hideHiddenFiles.
  ///
  /// In es, this message translates to:
  /// **'No mostrar los ocultos'**
  String get hideHiddenFiles;

  /// No description provided for @hideQueue.
  ///
  /// In es, this message translates to:
  /// **'Ocultar'**
  String get hideQueue;

  /// No description provided for @hostInUse.
  ///
  /// In es, this message translates to:
  /// **'Otros hosts saltan por «{name}»: cámbialos antes de eliminarlo.'**
  String hostInUse(String name);

  /// No description provided for @hostKey.
  ///
  /// In es, this message translates to:
  /// **'Clave del host'**
  String get hostKey;

  /// No description provided for @hostKeyUnknownBody.
  ///
  /// In es, this message translates to:
  /// **'OpenWard aún no conoce la clave de {where}. Compara la huella con la que te dé quien administra el servidor antes de confiar en ella.'**
  String hostKeyUnknownBody(String where);

  /// No description provided for @hostKeys.
  ///
  /// In es, this message translates to:
  /// **'Claves de host nuevas'**
  String get hostKeys;

  /// No description provided for @hostNeedsName.
  ///
  /// In es, this message translates to:
  /// **'El host necesita un nombre.'**
  String get hostNeedsName;

  /// No description provided for @importEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Importar…'**
  String get importEllipsis;

  /// No description provided for @importFailed.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido importar: {error}'**
  String importFailed(String error);

  /// No description provided for @importFound.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Hemos encontrado 1 host en tu ~/.ssh/config.} other{Hemos encontrado {count} hosts en tu ~/.ssh/config.}}'**
  String importFound(int count);

  /// No description provided for @importFrom.
  ///
  /// In es, this message translates to:
  /// **'Importar de ~/.ssh/config'**
  String get importFrom;

  /// No description provided for @importIntoGroup.
  ///
  /// In es, this message translates to:
  /// **'Se guardan en el grupo «~/.ssh/config». Un host trae consigo los hosts por los que salta.'**
  String get importIntoGroup;

  /// No description provided for @importKeepsFile.
  ///
  /// In es, this message translates to:
  /// **'El fichero no se toca, y las claves se quedan donde están: OpenWard guarda la ruta, nunca la clave.'**
  String get importKeepsFile;

  /// No description provided for @importLater.
  ///
  /// In es, this message translates to:
  /// **'Puedes importar más tarde desde la barra lateral.'**
  String get importLater;

  /// No description provided for @importN.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0{Importar} =1{Importar 1 host} other{Importar {count} hosts}}'**
  String importN(int count);

  /// No description provided for @importNothing.
  ///
  /// In es, this message translates to:
  /// **'No hay hosts nuevos en ~/.ssh/config (o no existe).'**
  String get importNothing;

  /// No description provided for @importScheme.
  ///
  /// In es, this message translates to:
  /// **'Importar de iTerm2 o Ghostty…'**
  String get importScheme;

  /// No description provided for @importSchemeDone.
  ///
  /// In es, this message translates to:
  /// **'«{name}» importado y puesto en el terminal.'**
  String importSchemeDone(String name);

  /// No description provided for @importSchemeFailed.
  ///
  /// In es, this message translates to:
  /// **'Ese fichero no es un tema de iTerm2 (.itermcolors) ni de Ghostty.'**
  String get importSchemeFailed;

  /// No description provided for @importSshConfigMenu.
  ///
  /// In es, this message translates to:
  /// **'Importar de ~/.ssh/config…'**
  String get importSshConfigMenu;

  /// No description provided for @importTitle.
  ///
  /// In es, this message translates to:
  /// **'Importar ~/.ssh/config'**
  String get importTitle;

  /// No description provided for @inDark.
  ///
  /// In es, this message translates to:
  /// **'En oscuro'**
  String get inDark;

  /// No description provided for @inGroup.
  ///
  /// In es, this message translates to:
  /// **'en el grupo {name}'**
  String inGroup(String name);

  /// No description provided for @inLight.
  ///
  /// In es, this message translates to:
  /// **'En claro'**
  String get inLight;

  /// No description provided for @inputNotSent.
  ///
  /// In es, this message translates to:
  /// **'Lo que escribas ahora no se envía.'**
  String get inputNotSent;

  /// No description provided for @inside.
  ///
  /// In es, this message translates to:
  /// **'Dentro de'**
  String get inside;

  /// No description provided for @itemCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 elemento} other{{count} elementos}}'**
  String itemCount(int count);

  /// No description provided for @jobCancelled.
  ///
  /// In es, this message translates to:
  /// **'Cancelada'**
  String get jobCancelled;

  /// No description provided for @jobCounting.
  ///
  /// In es, this message translates to:
  /// **'Contando…'**
  String get jobCounting;

  /// No description provided for @jobDone.
  ///
  /// In es, this message translates to:
  /// **'Hecho · {size}'**
  String jobDone(String size);

  /// No description provided for @jobFailed.
  ///
  /// In es, this message translates to:
  /// **'Ha fallado'**
  String get jobFailed;

  /// No description provided for @jobFolder.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{carpeta, 1 fichero} other{carpeta, {count} ficheros}}'**
  String jobFolder(int count);

  /// No description provided for @jobLost.
  ///
  /// In es, this message translates to:
  /// **'Se cortó la conexión con {done} de {total} copiados'**
  String jobLost(String done, String total);

  /// No description provided for @jobPaused.
  ///
  /// In es, this message translates to:
  /// **'En pausa · {done} de {total}'**
  String jobPaused(String done, String total);

  /// No description provided for @jobProgress.
  ///
  /// In es, this message translates to:
  /// **'{done} de {total}'**
  String jobProgress(String done, String total);

  /// No description provided for @jobQueued.
  ///
  /// In es, this message translates to:
  /// **'En cola · {size}'**
  String jobQueued(String size);

  /// No description provided for @jobQueuedNoSize.
  ///
  /// In es, this message translates to:
  /// **'En cola'**
  String get jobQueuedNoSize;

  /// No description provided for @jobSkipped.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 ya estaba} other{{count} ya estaban}}'**
  String jobSkipped(int count);

  /// No description provided for @jumpThrough.
  ///
  /// In es, this message translates to:
  /// **'Saltar por, en orden'**
  String get jumpThrough;

  /// No description provided for @jumpVia.
  ///
  /// In es, this message translates to:
  /// **'Saltando por {hosts}'**
  String jumpVia(String hosts);

  /// No description provided for @jumpsVia.
  ///
  /// In es, this message translates to:
  /// **'salta por {hosts}'**
  String jumpsVia(String hosts);

  /// No description provided for @keyBefore.
  ///
  /// In es, this message translates to:
  /// **'Antes'**
  String get keyBefore;

  /// No description provided for @keyChangedBody.
  ///
  /// In es, this message translates to:
  /// **'Puede ser una reinstalación del servidor o alguien interceptando la conexión. No se ha enviado ninguna contraseña ni clave.'**
  String get keyChangedBody;

  /// No description provided for @keyChangedDialogBody.
  ///
  /// In es, this message translates to:
  /// **'{where} se presenta con una clave distinta de la que tenías como buena. Puede que el servidor se haya reinstalado o haya cambiado de clave, pero también que alguien esté interceptando la conexión. No sigas sin comprobar la huella nueva con quien administra el servidor.'**
  String keyChangedDialogBody(String where);

  /// No description provided for @keyChangedTitle.
  ///
  /// In es, this message translates to:
  /// **'La clave de {label} ha cambiado'**
  String keyChangedTitle(String label);

  /// No description provided for @keyExchange.
  ///
  /// In es, this message translates to:
  /// **'Intercambio'**
  String get keyExchange;

  /// No description provided for @keyInKnownHosts.
  ///
  /// In es, this message translates to:
  /// **'en ~/.ssh/known_hosts'**
  String get keyInKnownHosts;

  /// No description provided for @keyInOpenWard.
  ///
  /// In es, this message translates to:
  /// **'guardada en OpenWard'**
  String get keyInOpenWard;

  /// No description provided for @keyNow.
  ///
  /// In es, this message translates to:
  /// **'Ahora ({algorithm})'**
  String keyNow(String algorithm);

  /// No description provided for @keyProtected.
  ///
  /// In es, this message translates to:
  /// **'La clave {key} está protegida.'**
  String keyProtected(String key);

  /// No description provided for @keyReceived.
  ///
  /// In es, this message translates to:
  /// **'Recibida'**
  String get keyReceived;

  /// No description provided for @keySaved.
  ///
  /// In es, this message translates to:
  /// **'Guardada'**
  String get keySaved;

  /// No description provided for @keys.
  ///
  /// In es, this message translates to:
  /// **'Claves'**
  String get keys;

  /// No description provided for @keysHelp.
  ///
  /// In es, this message translates to:
  /// **'Una ruta por línea. OpenWard guarda la ruta, nunca la clave.'**
  String get keysHelp;

  /// No description provided for @language.
  ///
  /// In es, this message translates to:
  /// **'Idioma'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In es, this message translates to:
  /// **'Como el sistema'**
  String get languageSystem;

  /// No description provided for @licenses.
  ///
  /// In es, this message translates to:
  /// **'Licencias'**
  String get licenses;

  /// No description provided for @lightAndDark.
  ///
  /// In es, this message translates to:
  /// **'Claro y oscuro'**
  String get lightAndDark;

  /// No description provided for @lineHeight.
  ///
  /// In es, this message translates to:
  /// **'Interlineado del terminal'**
  String get lineHeight;

  /// No description provided for @linkNotOpened.
  ///
  /// In es, this message translates to:
  /// **'Los enlaces «{scheme}:» no se abren desde el terminal.'**
  String linkNotOpened(String scheme);

  /// No description provided for @localTerminal.
  ///
  /// In es, this message translates to:
  /// **'Terminal local'**
  String get localTerminal;

  /// No description provided for @localUser.
  ///
  /// In es, this message translates to:
  /// **'tu usuario local'**
  String get localUser;

  /// No description provided for @maximizePane.
  ///
  /// In es, this message translates to:
  /// **'Maximizar el panel'**
  String get maximizePane;

  /// No description provided for @milliseconds.
  ///
  /// In es, this message translates to:
  /// **'{ms} ms'**
  String milliseconds(int ms);

  /// No description provided for @minimumContrast.
  ///
  /// In es, this message translates to:
  /// **'Contraste mínimo'**
  String get minimumContrast;

  /// No description provided for @minimumContrastHelp.
  ///
  /// In es, this message translates to:
  /// **'Aclara u oscurece el texto del terminal que no se lee sobre su fondo.'**
  String get minimumContrastHelp;

  /// No description provided for @missingAddress.
  ///
  /// In es, this message translates to:
  /// **'Falta la dirección.'**
  String get missingAddress;

  /// No description provided for @missingJump.
  ///
  /// In es, this message translates to:
  /// **'Añade al menos un host por el que saltar.'**
  String get missingJump;

  /// No description provided for @missingProxyCommand.
  ///
  /// In es, this message translates to:
  /// **'Falta el ProxyCommand.'**
  String get missingProxyCommand;

  /// No description provided for @missingSocket.
  ///
  /// In es, this message translates to:
  /// **'Falta la ruta del socket del agente.'**
  String get missingSocket;

  /// No description provided for @moreActions.
  ///
  /// In es, this message translates to:
  /// **'Más acciones'**
  String get moreActions;

  /// No description provided for @moreOptions.
  ///
  /// In es, this message translates to:
  /// **'Más opciones'**
  String get moreOptions;

  /// No description provided for @name.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get name;

  /// No description provided for @nameNoSlash.
  ///
  /// In es, this message translates to:
  /// **'Un nombre no puede llevar «/».'**
  String get nameNoSlash;

  /// No description provided for @netLost.
  ///
  /// In es, this message translates to:
  /// **'se ha perdido la conexión.'**
  String get netLost;

  /// No description provided for @netNotFound.
  ///
  /// In es, this message translates to:
  /// **'no se encuentra el host.'**
  String get netNotFound;

  /// No description provided for @netRefused.
  ///
  /// In es, this message translates to:
  /// **'conexión rechazada.'**
  String get netRefused;

  /// No description provided for @netTimeout.
  ///
  /// In es, this message translates to:
  /// **'tiempo de espera agotado.'**
  String get netTimeout;

  /// No description provided for @newFolder.
  ///
  /// In es, this message translates to:
  /// **'Nueva carpeta'**
  String get newFolder;

  /// No description provided for @newGroup.
  ///
  /// In es, this message translates to:
  /// **'Nuevo grupo'**
  String get newGroup;

  /// No description provided for @newGroupTitle.
  ///
  /// In es, this message translates to:
  /// **'Nuevo grupo'**
  String get newGroupTitle;

  /// No description provided for @newHost.
  ///
  /// In es, this message translates to:
  /// **'Nuevo host'**
  String get newHost;

  /// No description provided for @newHostHere.
  ///
  /// In es, this message translates to:
  /// **'Nuevo host aquí'**
  String get newHostHere;

  /// No description provided for @newHostTitle.
  ///
  /// In es, this message translates to:
  /// **'Nuevo host'**
  String get newHostTitle;

  /// No description provided for @newLocalTerminal.
  ///
  /// In es, this message translates to:
  /// **'Terminal local nuevo'**
  String get newLocalTerminal;

  /// No description provided for @newPane.
  ///
  /// In es, this message translates to:
  /// **'Panel nuevo'**
  String get newPane;

  /// No description provided for @newSubgroup.
  ///
  /// In es, this message translates to:
  /// **'Nuevo subgrupo'**
  String get newSubgroup;

  /// No description provided for @next.
  ///
  /// In es, this message translates to:
  /// **'Siguiente'**
  String get next;

  /// No description provided for @no.
  ///
  /// In es, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @noGroup.
  ///
  /// In es, this message translates to:
  /// **'Sin grupo'**
  String get noGroup;

  /// No description provided for @noHostsBody.
  ///
  /// In es, this message translates to:
  /// **'Añade uno o tráelos de tu ~/⁠.ssh/⁠config.'**
  String get noHostsBody;

  /// No description provided for @noHostsTitle.
  ///
  /// In es, this message translates to:
  /// **'Aún no tienes hosts'**
  String get noHostsTitle;

  /// No description provided for @noJumpsYet.
  ///
  /// In es, this message translates to:
  /// **'Ninguno todavía.'**
  String get noJumpsYet;

  /// No description provided for @noMatches.
  ///
  /// In es, this message translates to:
  /// **'Nada coincide con «{filter}»'**
  String noMatches(String filter);

  /// No description provided for @noParent.
  ///
  /// In es, this message translates to:
  /// **'Ningún grupo'**
  String get noParent;

  /// No description provided for @noPostQuantumNote.
  ///
  /// In es, this message translates to:
  /// **'El servidor no ofrece un intercambio poscuántico (mlkem768x25519; OpenSSH lo trae desde la 10.0).'**
  String get noPostQuantumNote;

  /// No description provided for @noResults.
  ///
  /// In es, this message translates to:
  /// **'Ningún host coincide.'**
  String get noResults;

  /// No description provided for @notNow.
  ///
  /// In es, this message translates to:
  /// **'Ahora no'**
  String get notNow;

  /// No description provided for @notes.
  ///
  /// In es, this message translates to:
  /// **'Notas'**
  String get notes;

  /// No description provided for @ok.
  ///
  /// In es, this message translates to:
  /// **'Aceptar'**
  String get ok;

  /// No description provided for @openLocal.
  ///
  /// In es, this message translates to:
  /// **'Abrir un terminal local'**
  String get openLocal;

  /// No description provided for @openSftp.
  ///
  /// In es, this message translates to:
  /// **'Abrir SFTP'**
  String get openSftp;

  /// No description provided for @openSshStillWarns.
  ///
  /// In es, this message translates to:
  /// **'OpenWard no modifica ~/.ssh/known_hosts: ssh seguirá avisando hasta que quites la clave vieja de allí ({command}).'**
  String openSshStillWarns(String command);

  /// No description provided for @optionAsAlt.
  ///
  /// In es, this message translates to:
  /// **'Opción como Alt'**
  String get optionAsAlt;

  /// No description provided for @optionAsAltHelp.
  ///
  /// In es, this message translates to:
  /// **'Opción envía Esc + tecla, como esperan emacs y readline, en vez de escribir símbolos como @ o €.'**
  String get optionAsAltHelp;

  /// No description provided for @orAnAddress.
  ///
  /// In es, this message translates to:
  /// **'o una dirección: usuario@host:puerto'**
  String get orAnAddress;

  /// No description provided for @paneOptions.
  ///
  /// In es, this message translates to:
  /// **'Opciones del panel'**
  String get paneOptions;

  /// No description provided for @paneWhat.
  ///
  /// In es, this message translates to:
  /// **'¿Qué abres en este panel?'**
  String get paneWhat;

  /// No description provided for @partNote.
  ///
  /// In es, this message translates to:
  /// **'Se copia con un nombre temporal (.part) y se renombra al terminar: si se corta, el fichero bueno no queda a medias y la copia se puede reanudar.'**
  String get partNote;

  /// No description provided for @passphraseField.
  ///
  /// In es, this message translates to:
  /// **'Frase'**
  String get passphraseField;

  /// No description provided for @passphraseTitle.
  ///
  /// In es, this message translates to:
  /// **'Frase de la clave'**
  String get passphraseTitle;

  /// No description provided for @passwordTitle.
  ///
  /// In es, this message translates to:
  /// **'Contraseña'**
  String get passwordTitle;

  /// No description provided for @paste.
  ///
  /// In es, this message translates to:
  /// **'Pegar'**
  String get paste;

  /// No description provided for @pasteInPanes.
  ///
  /// In es, this message translates to:
  /// **'Pegar en {total} paneles'**
  String pasteInPanes(int total);

  /// No description provided for @pasteMultiBody.
  ///
  /// In es, this message translates to:
  /// **'El texto contiene saltos de línea u otras secuencias que pueden ejecutar comandos al pegarlo.'**
  String get pasteMultiBody;

  /// No description provided for @pasteMultiTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Pegar varias líneas?'**
  String get pasteMultiTitle;

  /// No description provided for @pasteOnlyHere.
  ///
  /// In es, this message translates to:
  /// **'Pegar solo en {name}'**
  String pasteOnlyHere(String name);

  /// No description provided for @pause.
  ///
  /// In es, this message translates to:
  /// **'Pausar'**
  String get pause;

  /// No description provided for @pauseAll.
  ///
  /// In es, this message translates to:
  /// **'Pausar todo'**
  String get pauseAll;

  /// No description provided for @percent.
  ///
  /// In es, this message translates to:
  /// **'{number} %'**
  String percent(int number);

  /// No description provided for @permApplied.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Permisos cambiados en 1 elemento} other{Permisos cambiados en {count} elementos}}'**
  String permApplied(int count);

  /// No description provided for @permBefore.
  ///
  /// In es, this message translates to:
  /// **'Antes: {mode}'**
  String permBefore(String mode);

  /// No description provided for @permEnter.
  ///
  /// In es, this message translates to:
  /// **'Entrar'**
  String get permEnter;

  /// No description provided for @permExecute.
  ///
  /// In es, this message translates to:
  /// **'Ejecutar'**
  String get permExecute;

  /// No description provided for @permGroup.
  ///
  /// In es, this message translates to:
  /// **'Grupo'**
  String get permGroup;

  /// No description provided for @permOctal.
  ///
  /// In es, this message translates to:
  /// **'En octal'**
  String get permOctal;

  /// No description provided for @permOthers.
  ///
  /// In es, this message translates to:
  /// **'Otros'**
  String get permOthers;

  /// No description provided for @permOwner.
  ///
  /// In es, this message translates to:
  /// **'Propietario'**
  String get permOwner;

  /// No description provided for @permOwnerNote.
  ///
  /// In es, this message translates to:
  /// **'El propietario y el grupo no se cambian desde aquí.'**
  String get permOwnerNote;

  /// No description provided for @permRead.
  ///
  /// In es, this message translates to:
  /// **'Leer'**
  String get permRead;

  /// No description provided for @permRecursive.
  ///
  /// In es, this message translates to:
  /// **'Aplicar también a lo que hay dentro'**
  String get permRecursive;

  /// No description provided for @permRecursiveNote.
  ///
  /// In es, this message translates to:
  /// **'A los ficheros solo se les deja «Ejecutar» si ya lo tenían.'**
  String get permRecursiveNote;

  /// No description provided for @permWrite.
  ///
  /// In es, this message translates to:
  /// **'Escribir'**
  String get permWrite;

  /// No description provided for @permissionsEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Permisos…'**
  String get permissionsEllipsis;

  /// No description provided for @permissionsOf.
  ///
  /// In es, this message translates to:
  /// **'Permisos de {name}'**
  String permissionsOf(String name);

  /// No description provided for @pixels.
  ///
  /// In es, this message translates to:
  /// **'{size} px'**
  String pixels(int size);

  /// No description provided for @policyAcceptNew.
  ///
  /// In es, this message translates to:
  /// **'Aceptar nuevas'**
  String get policyAcceptNew;

  /// No description provided for @policyAsk.
  ///
  /// In es, this message translates to:
  /// **'Preguntar'**
  String get policyAsk;

  /// No description provided for @policyStrict.
  ///
  /// In es, this message translates to:
  /// **'Estricta'**
  String get policyStrict;

  /// No description provided for @port.
  ///
  /// In es, this message translates to:
  /// **'Puerto'**
  String get port;

  /// No description provided for @portRange.
  ///
  /// In es, this message translates to:
  /// **'El puerto va de 1 a 65535.'**
  String get portRange;

  /// No description provided for @postQuantum.
  ///
  /// In es, this message translates to:
  /// **'poscuántico'**
  String get postQuantum;

  /// No description provided for @postQuantumKex.
  ///
  /// In es, this message translates to:
  /// **'{kex} (poscuántico)'**
  String postQuantumKex(String kex);

  /// No description provided for @preview.
  ///
  /// In es, this message translates to:
  /// **'Vista previa'**
  String get preview;

  /// No description provided for @previewLive.
  ///
  /// In es, this message translates to:
  /// **'Los cambios se ven al momento en toda la ventana.'**
  String get previewLive;

  /// No description provided for @queueAllDone.
  ///
  /// In es, this message translates to:
  /// **'Todo terminado'**
  String get queueAllDone;

  /// No description provided for @queueFailed.
  ///
  /// In es, this message translates to:
  /// **'{count} con error'**
  String queueFailed(int count);

  /// No description provided for @queuePaused.
  ///
  /// In es, this message translates to:
  /// **'{count} en pausa'**
  String queuePaused(int count);

  /// No description provided for @queueQueued.
  ///
  /// In es, this message translates to:
  /// **'{count} en cola'**
  String queueQueued(int count);

  /// No description provided for @queueRunning.
  ///
  /// In es, this message translates to:
  /// **'{count} en curso'**
  String queueRunning(int count);

  /// No description provided for @quickConnectHint.
  ///
  /// In es, this message translates to:
  /// **'usuario@servidor:puerto'**
  String get quickConnectHint;

  /// No description provided for @quickConnectInvalid.
  ///
  /// In es, this message translates to:
  /// **'Escribe una dirección como usuario@servidor:puerto.'**
  String get quickConnectInvalid;

  /// No description provided for @readyBody.
  ///
  /// In es, this message translates to:
  /// **'Estos atajos te llevan a casi todo:'**
  String get readyBody;

  /// No description provided for @readyTitle.
  ///
  /// In es, this message translates to:
  /// **'Todo listo'**
  String get readyTitle;

  /// No description provided for @receives.
  ///
  /// In es, this message translates to:
  /// **'Recibe'**
  String get receives;

  /// No description provided for @reconnect.
  ///
  /// In es, this message translates to:
  /// **'Reconectar'**
  String get reconnect;

  /// No description provided for @reconnectingEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Reconectando…'**
  String get reconnectingEllipsis;

  /// No description provided for @reconnectingStage.
  ///
  /// In es, this message translates to:
  /// **'Reconectando: {stage}'**
  String reconnectingStage(String stage);

  /// No description provided for @reduceMotion.
  ///
  /// In es, this message translates to:
  /// **'Reducir movimiento'**
  String get reduceMotion;

  /// No description provided for @reload.
  ///
  /// In es, this message translates to:
  /// **'Recargar'**
  String get reload;

  /// No description provided for @remove.
  ///
  /// In es, this message translates to:
  /// **'Quitar'**
  String get remove;

  /// No description provided for @removeTag.
  ///
  /// In es, this message translates to:
  /// **'Quitar {tag}'**
  String removeTag(String tag);

  /// No description provided for @rename.
  ///
  /// In es, this message translates to:
  /// **'Renombrar'**
  String get rename;

  /// No description provided for @renameTabHelp.
  ///
  /// In es, this message translates to:
  /// **'Vacío para volver al nombre del host'**
  String get renameTabHelp;

  /// No description provided for @renameTabTitle.
  ///
  /// In es, this message translates to:
  /// **'Renombrar pestaña'**
  String get renameTabTitle;

  /// No description provided for @renameTitle.
  ///
  /// In es, this message translates to:
  /// **'Renombrar {name}'**
  String renameTitle(String name);

  /// No description provided for @reportCreated.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 host nuevo} other{{count} hosts nuevos}}'**
  String reportCreated(int count);

  /// No description provided for @reportNotEverything.
  ///
  /// In es, this message translates to:
  /// **'No todo se ha podido traer:'**
  String get reportNotEverything;

  /// No description provided for @reportSkipped.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 ya estaba importado y no se ha tocado} other{{count} ya estaban importados y no se han tocado}}'**
  String reportSkipped(int count);

  /// No description provided for @reportWhere.
  ///
  /// In es, this message translates to:
  /// **'Están en el grupo «~/.ssh/config».'**
  String get reportWhere;

  /// No description provided for @resetTheme.
  ///
  /// In es, this message translates to:
  /// **'Restablecer'**
  String get resetTheme;

  /// No description provided for @restart.
  ///
  /// In es, this message translates to:
  /// **'Reiniciar'**
  String get restart;

  /// No description provided for @restorePanes.
  ///
  /// In es, this message translates to:
  /// **'Volver a los paneles'**
  String get restorePanes;

  /// No description provided for @resume.
  ///
  /// In es, this message translates to:
  /// **'Reanudar'**
  String get resume;

  /// No description provided for @retryIn.
  ///
  /// In es, this message translates to:
  /// **'Reintento {attempt} de {max} en {secs} s.'**
  String retryIn(int attempt, int max, int secs);

  /// No description provided for @retryNow.
  ///
  /// In es, this message translates to:
  /// **'Reintentar ahora'**
  String get retryNow;

  /// No description provided for @reviewKey.
  ///
  /// In es, this message translates to:
  /// **'Revisar la clave…'**
  String get reviewKey;

  /// No description provided for @route.
  ///
  /// In es, this message translates to:
  /// **'Cómo llegar'**
  String get route;

  /// No description provided for @routeDirect.
  ///
  /// In es, this message translates to:
  /// **'Directo'**
  String get routeDirect;

  /// No description provided for @routeJump.
  ///
  /// In es, this message translates to:
  /// **'Saltando por otro host'**
  String get routeJump;

  /// No description provided for @routeStart.
  ///
  /// In es, this message translates to:
  /// **'este equipo'**
  String get routeStart;

  /// No description provided for @sameHost.
  ///
  /// In es, this message translates to:
  /// **'el mismo host'**
  String get sameHost;

  /// No description provided for @sampleComment.
  ///
  /// In es, this message translates to:
  /// **'comentario en gris'**
  String get sampleComment;

  /// No description provided for @sampleError.
  ///
  /// In es, this message translates to:
  /// **'error:'**
  String get sampleError;

  /// No description provided for @sampleErrorText.
  ///
  /// In es, this message translates to:
  /// **'no se pudo leer .env'**
  String get sampleErrorText;

  /// No description provided for @sampleWarning.
  ///
  /// In es, this message translates to:
  /// **'aviso:'**
  String get sampleWarning;

  /// No description provided for @sampleWarningText.
  ///
  /// In es, this message translates to:
  /// **'2 migraciones pendientes'**
  String get sampleWarningText;

  /// No description provided for @save.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get save;

  /// No description provided for @saveAndConnect.
  ///
  /// In es, this message translates to:
  /// **'Guardar y conectar'**
  String get saveAndConnect;

  /// No description provided for @saveFailed.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido guardar: {error}'**
  String saveFailed(String error);

  /// No description provided for @saveKeyFailed.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido guardar la clave: {error}'**
  String saveKeyFailed(String error);

  /// No description provided for @saveNewHost.
  ///
  /// In es, this message translates to:
  /// **'Guardar un host nuevo'**
  String get saveNewHost;

  /// No description provided for @scrollback.
  ///
  /// In es, this message translates to:
  /// **'Historial'**
  String get scrollback;

  /// No description provided for @scrollbackHelp.
  ///
  /// In es, this message translates to:
  /// **'Para las pestañas nuevas.'**
  String get scrollbackHelp;

  /// No description provided for @scrollbackLines.
  ///
  /// In es, this message translates to:
  /// **'{lines} líneas'**
  String scrollbackLines(String lines);

  /// No description provided for @searchHosts.
  ///
  /// In es, this message translates to:
  /// **'Buscar hosts'**
  String get searchHosts;

  /// No description provided for @sectionConnection.
  ///
  /// In es, this message translates to:
  /// **'Conexión'**
  String get sectionConnection;

  /// No description provided for @sectionGeneral.
  ///
  /// In es, this message translates to:
  /// **'General'**
  String get sectionGeneral;

  /// No description provided for @selectAll.
  ///
  /// In es, this message translates to:
  /// **'Todos'**
  String get selectAll;

  /// No description provided for @selectAllText.
  ///
  /// In es, this message translates to:
  /// **'Seleccionar todo'**
  String get selectAllText;

  /// No description provided for @selectedCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 seleccionado ({size})} other{{count} seleccionados ({size})}}'**
  String selectedCount(int count, String size);

  /// No description provided for @selectedCountOnly.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 seleccionado} other{{count} seleccionados}}'**
  String selectedCountOnly(int count);

  /// No description provided for @selectedOf.
  ///
  /// In es, this message translates to:
  /// **'{selected} de {total}'**
  String selectedOf(int selected, int total);

  /// No description provided for @sessionClosed.
  ///
  /// In es, this message translates to:
  /// **'Sesión cerrada.'**
  String get sessionClosed;

  /// No description provided for @sessionClosedCode.
  ///
  /// In es, this message translates to:
  /// **'Sesión cerrada (código {code}).'**
  String sessionClosedCode(int code);

  /// No description provided for @setHereWouldInherit.
  ///
  /// In es, this message translates to:
  /// **'Cambiado aquí; heredaría {value}'**
  String setHereWouldInherit(String value);

  /// No description provided for @settings.
  ///
  /// In es, this message translates to:
  /// **'Ajustes'**
  String get settings;

  /// No description provided for @settingsAppearance.
  ///
  /// In es, this message translates to:
  /// **'Apariencia'**
  String get settingsAppearance;

  /// No description provided for @settingsGeneral.
  ///
  /// In es, this message translates to:
  /// **'General'**
  String get settingsGeneral;

  /// No description provided for @settingsTerminal.
  ///
  /// In es, this message translates to:
  /// **'Terminal'**
  String get settingsTerminal;

  /// No description provided for @sftpConnected.
  ///
  /// In es, this message translates to:
  /// **'SFTP en {label}'**
  String sftpConnected(String label);

  /// No description provided for @sftpKeysApple.
  ///
  /// In es, this message translates to:
  /// **'Intro abre · ⌘↑ sube · Tab cambia de lado · F2 renombra · ⌘⌫ elimina'**
  String get sftpKeysApple;

  /// No description provided for @sftpKeysOther.
  ///
  /// In es, this message translates to:
  /// **'Intro abre · Retroceso sube · Tab cambia de lado · F2 renombra · Supr elimina'**
  String get sftpKeysOther;

  /// No description provided for @sftpTabTitle.
  ///
  /// In es, this message translates to:
  /// **'SFTP · {label}'**
  String sftpTabTitle(String label);

  /// No description provided for @shape.
  ///
  /// In es, this message translates to:
  /// **'Forma'**
  String get shape;

  /// No description provided for @shortcutLocal.
  ///
  /// In es, this message translates to:
  /// **'Abre un terminal local'**
  String get shortcutLocal;

  /// No description provided for @shortcutNewHost.
  ///
  /// In es, this message translates to:
  /// **'Guarda un host nuevo'**
  String get shortcutNewHost;

  /// No description provided for @shortcutSearch.
  ///
  /// In es, this message translates to:
  /// **'Busca entre tus hosts'**
  String get shortcutSearch;

  /// No description provided for @shortcutSettings.
  ///
  /// In es, this message translates to:
  /// **'Abre los ajustes'**
  String get shortcutSettings;

  /// No description provided for @showHiddenFiles.
  ///
  /// In es, this message translates to:
  /// **'Mostrar los ocultos'**
  String get showHiddenFiles;

  /// No description provided for @showQueue.
  ///
  /// In es, this message translates to:
  /// **'Ver la cola'**
  String get showQueue;

  /// No description provided for @showRest.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Ver el que falta} other{Ver los {count} restantes}}'**
  String showRest(int count);

  /// No description provided for @skipGuide.
  ///
  /// In es, this message translates to:
  /// **'Saltar la guía'**
  String get skipGuide;

  /// No description provided for @splitDown.
  ///
  /// In es, this message translates to:
  /// **'Dividir abajo'**
  String get splitDown;

  /// No description provided for @splitRight.
  ///
  /// In es, this message translates to:
  /// **'Dividir a la derecha'**
  String get splitRight;

  /// No description provided for @stageAuthenticating.
  ///
  /// In es, this message translates to:
  /// **'Autenticando en {label}{hop}…'**
  String stageAuthenticating(String label, String hop);

  /// No description provided for @stageConnecting.
  ///
  /// In es, this message translates to:
  /// **'Conectando con {label}{hop}…'**
  String stageConnecting(String label, String hop);

  /// No description provided for @stageOpeningSftp.
  ///
  /// In es, this message translates to:
  /// **'Abriendo SFTP en {label}…'**
  String stageOpeningSftp(String label);

  /// No description provided for @stageOpeningShell.
  ///
  /// In es, this message translates to:
  /// **'Abriendo el shell en {label}…'**
  String stageOpeningShell(String label);

  /// No description provided for @start.
  ///
  /// In es, this message translates to:
  /// **'Empezar'**
  String get start;

  /// No description provided for @startHere.
  ///
  /// In es, this message translates to:
  /// **'Empieza aquí'**
  String get startHere;

  /// No description provided for @starting.
  ///
  /// In es, this message translates to:
  /// **'Arrancando…'**
  String get starting;

  /// No description provided for @statusConnected.
  ///
  /// In es, this message translates to:
  /// **'Conectado'**
  String get statusConnected;

  /// No description provided for @statusConnecting.
  ///
  /// In es, this message translates to:
  /// **'Conectando'**
  String get statusConnecting;

  /// No description provided for @statusError.
  ///
  /// In es, this message translates to:
  /// **'Error: {error}'**
  String statusError(String error);

  /// No description provided for @statusFailed.
  ///
  /// In es, this message translates to:
  /// **'Ha fallado la conexión'**
  String get statusFailed;

  /// No description provided for @statusIdle.
  ///
  /// In es, this message translates to:
  /// **'Sin conectar'**
  String get statusIdle;

  /// No description provided for @stepAppearance.
  ///
  /// In es, this message translates to:
  /// **'Apariencia'**
  String get stepAppearance;

  /// No description provided for @stepAuthenticating.
  ///
  /// In es, this message translates to:
  /// **'autenticando…'**
  String get stepAuthenticating;

  /// No description provided for @stepConnecting.
  ///
  /// In es, this message translates to:
  /// **'conectando…'**
  String get stepConnecting;

  /// No description provided for @stepImport.
  ///
  /// In es, this message translates to:
  /// **'Importar'**
  String get stepImport;

  /// No description provided for @stepOpeningSftp.
  ///
  /// In es, this message translates to:
  /// **'abriendo SFTP…'**
  String get stepOpeningSftp;

  /// No description provided for @stepOpeningShell.
  ///
  /// In es, this message translates to:
  /// **'abriendo el shell…'**
  String get stepOpeningShell;

  /// No description provided for @stepReady.
  ///
  /// In es, this message translates to:
  /// **'Listo'**
  String get stepReady;

  /// No description provided for @tags.
  ///
  /// In es, this message translates to:
  /// **'Etiquetas'**
  String get tags;

  /// No description provided for @terminalAlwaysDark.
  ///
  /// In es, this message translates to:
  /// **'Siempre oscuro'**
  String get terminalAlwaysDark;

  /// No description provided for @terminalAsTheme.
  ///
  /// In es, this message translates to:
  /// **'Como el tema'**
  String get terminalAsTheme;

  /// No description provided for @terminalColors.
  ///
  /// In es, this message translates to:
  /// **'Colores del terminal'**
  String get terminalColors;

  /// No description provided for @terminalFont.
  ///
  /// In es, this message translates to:
  /// **'Fuente del terminal'**
  String get terminalFont;

  /// No description provided for @terminalScheme.
  ///
  /// In es, this message translates to:
  /// **'Esquema propio'**
  String get terminalScheme;

  /// No description provided for @terminalShortcuts.
  ///
  /// In es, this message translates to:
  /// **'{key}F busca en el terminal y su historial. {key}+ y {key}− cambian el tamaño de la letra de la pestaña, y {key}0 lo devuelve. Con {key} pulsado, un clic abre un enlace.'**
  String terminalShortcuts(String key);

  /// No description provided for @textSize.
  ///
  /// In es, this message translates to:
  /// **'Tamaño del texto'**
  String get textSize;

  /// No description provided for @textSizeHelp.
  ///
  /// In es, this message translates to:
  /// **'De la interfaz, sobre el del sistema. El terminal tiene el suyo.'**
  String get textSizeHelp;

  /// No description provided for @theme.
  ///
  /// In es, this message translates to:
  /// **'Tema'**
  String get theme;

  /// No description provided for @themeDark.
  ///
  /// In es, this message translates to:
  /// **'Oscuro'**
  String get themeDark;

  /// No description provided for @themeHelp.
  ///
  /// In es, this message translates to:
  /// **'En claro, Papel; en oscuro, Grafito.'**
  String get themeHelp;

  /// No description provided for @themeLight.
  ///
  /// In es, this message translates to:
  /// **'Claro'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In es, this message translates to:
  /// **'Seguir al sistema'**
  String get themeSystem;

  /// No description provided for @themeVariant.
  ///
  /// In es, this message translates to:
  /// **'{name} ({variant})'**
  String themeVariant(String name, String variant);

  /// No description provided for @thisComputer.
  ///
  /// In es, this message translates to:
  /// **'Este equipo'**
  String get thisComputer;

  /// No description provided for @time.
  ///
  /// In es, this message translates to:
  /// **'Tiempo'**
  String get time;

  /// No description provided for @timeLeft.
  ///
  /// In es, this message translates to:
  /// **'quedan {time}'**
  String timeLeft(String time);

  /// No description provided for @todayAt.
  ///
  /// In es, this message translates to:
  /// **'hoy {time}'**
  String todayAt(String time);

  /// No description provided for @transfers.
  ///
  /// In es, this message translates to:
  /// **'Transferencias'**
  String get transfers;

  /// No description provided for @trust.
  ///
  /// In es, this message translates to:
  /// **'Confianza'**
  String get trust;

  /// No description provided for @trustAndConnect.
  ///
  /// In es, this message translates to:
  /// **'Confiar y conectar'**
  String get trustAndConnect;

  /// No description provided for @trustCertified.
  ///
  /// In es, this message translates to:
  /// **'certificada por la CA {ca}'**
  String trustCertified(String ca);

  /// No description provided for @trustKnown.
  ///
  /// In es, this message translates to:
  /// **'conocida'**
  String get trustKnown;

  /// No description provided for @trustNew.
  ///
  /// In es, this message translates to:
  /// **'nueva, guardada ahora'**
  String get trustNew;

  /// No description provided for @trustNewKey.
  ///
  /// In es, this message translates to:
  /// **'Confiar en la clave nueva'**
  String get trustNewKey;

  /// No description provided for @trustNewKeyEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Confiar en la clave nueva…'**
  String get trustNewKeyEllipsis;

  /// No description provided for @tryAgain.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get tryAgain;

  /// No description provided for @uiColors.
  ///
  /// In es, this message translates to:
  /// **'Colores de la interfaz'**
  String get uiColors;

  /// No description provided for @uiFont.
  ///
  /// In es, this message translates to:
  /// **'Fuente de la interfaz'**
  String get uiFont;

  /// No description provided for @upOneLevel.
  ///
  /// In es, this message translates to:
  /// **'Subir un nivel'**
  String get upOneLevel;

  /// No description provided for @upload.
  ///
  /// In es, this message translates to:
  /// **'Subida'**
  String get upload;

  /// No description provided for @uploadToArrow.
  ///
  /// In es, this message translates to:
  /// **'Subir a {where} →'**
  String uploadToArrow(String where);

  /// No description provided for @uploadToHost.
  ///
  /// In es, this message translates to:
  /// **'Subir a {host}'**
  String uploadToHost(String host);

  /// No description provided for @user.
  ///
  /// In es, this message translates to:
  /// **'Usuario'**
  String get user;

  /// No description provided for @variantDark.
  ///
  /// In es, this message translates to:
  /// **'oscuro'**
  String get variantDark;

  /// No description provided for @variantDarkOnly.
  ///
  /// In es, this message translates to:
  /// **'Oscuro'**
  String get variantDarkOnly;

  /// No description provided for @variantLight.
  ///
  /// In es, this message translates to:
  /// **'claro'**
  String get variantLight;

  /// No description provided for @variantLightOnly.
  ///
  /// In es, this message translates to:
  /// **'Claro'**
  String get variantLightOnly;

  /// No description provided for @verificationTitle.
  ///
  /// In es, this message translates to:
  /// **'Verificación'**
  String get verificationTitle;

  /// No description provided for @via.
  ///
  /// In es, this message translates to:
  /// **'vía {hops}'**
  String via(String hops);

  /// No description provided for @waitingAnswer.
  ///
  /// In es, this message translates to:
  /// **'Esperando respuesta…'**
  String get waitingAnswer;

  /// No description provided for @waitingForYou.
  ///
  /// In es, this message translates to:
  /// **'Espera tu respuesta'**
  String get waitingForYou;

  /// No description provided for @warnBadValue.
  ///
  /// In es, this message translates to:
  /// **'Valor no válido en {subject}{at}: {detail}.'**
  String warnBadValue(String subject, String at, String detail);

  /// No description provided for @warnIncludeTooDeep.
  ///
  /// In es, this message translates to:
  /// **'Include anidado demasiado hondo{at}.'**
  String warnIncludeTooDeep(String at);

  /// No description provided for @warnJumpLossy.
  ///
  /// In es, this message translates to:
  /// **'{alias} salta por {jump}, que no es un host importado: se guarda como dirección, sin sus claves ni su ruta.'**
  String warnJumpLossy(String alias, String jump);

  /// No description provided for @warnMatch.
  ///
  /// In es, this message translates to:
  /// **'Bloque Match{at}: OpenWard no lo evalúa y sus líneas se han saltado.'**
  String warnMatch(String at);

  /// No description provided for @warnStricter.
  ///
  /// In es, this message translates to:
  /// **'StrictHostKeyChecking no{at}: se importa como «aceptar nuevas»; una clave que cambia nunca se acepta sin preguntar.'**
  String warnStricter(String at);

  /// No description provided for @warnUnreadable.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido leer {file}: {error}.'**
  String warnUnreadable(String file, String error);

  /// No description provided for @warnUnsupported.
  ///
  /// In es, this message translates to:
  /// **'{subject}: no se importa{at}.'**
  String warnUnsupported(String subject, String at);

  /// No description provided for @welcomeNoConfig.
  ///
  /// In es, this message translates to:
  /// **'No hemos encontrado hosts en ~/.ssh/config. Podrás añadirlos a mano en un momento.'**
  String get welcomeNoConfig;

  /// No description provided for @welcomeTitle.
  ///
  /// In es, this message translates to:
  /// **'Te damos la bienvenida a OpenWard'**
  String get welcomeTitle;

  /// No description provided for @wrongAnswer.
  ///
  /// In es, this message translates to:
  /// **'Respuesta incorrecta.'**
  String get wrongAnswer;

  /// No description provided for @wrongPassphrase.
  ///
  /// In es, this message translates to:
  /// **'Frase incorrecta.'**
  String get wrongPassphrase;

  /// No description provided for @wrongPassword.
  ///
  /// In es, this message translates to:
  /// **'Contraseña incorrecta.'**
  String get wrongPassword;

  /// No description provided for @yes.
  ///
  /// In es, this message translates to:
  /// **'Sí'**
  String get yes;

  /// No description provided for @yesterdayAt.
  ///
  /// In es, this message translates to:
  /// **'ayer {time}'**
  String yesterdayAt(String time);
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
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
