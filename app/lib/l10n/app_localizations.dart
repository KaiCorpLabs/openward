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

  /// No description provided for @about.
  ///
  /// In es, this message translates to:
  /// **'Acerca de'**
  String get about;

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

  /// No description provided for @addCertificate.
  ///
  /// In es, this message translates to:
  /// **'+ Añadir certificado'**
  String get addCertificate;

  /// No description provided for @addFavorite.
  ///
  /// In es, this message translates to:
  /// **'Añadir a favoritos'**
  String get addFavorite;

  /// No description provided for @addKeyEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Añadir clave…'**
  String get addKeyEllipsis;

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

  /// No description provided for @advanced.
  ///
  /// In es, this message translates to:
  /// **'Avanzado'**
  String get advanced;

  /// No description provided for @advancedList.
  ///
  /// In es, this message translates to:
  /// **'proxy, claves del host, sesión persistente, Mosh, comprobación y agente'**
  String get advancedList;

  /// No description provided for @advancedListSerial.
  ///
  /// In es, this message translates to:
  /// **'registro de sesión'**
  String get advancedListSerial;

  /// No description provided for @advancedListTelnet.
  ///
  /// In es, this message translates to:
  /// **'proxy, registro de sesión y tiempo para conectar'**
  String get advancedListTelnet;

  /// No description provided for @advancedSetHere.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 cambiado aquí} other{{count} cambiados aquí}}'**
  String advancedSetHere(int count);

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

  /// No description provided for @agentOtherSocket.
  ///
  /// In es, this message translates to:
  /// **'Otro socket'**
  String get agentOtherSocket;

  /// No description provided for @agentShort.
  ///
  /// In es, this message translates to:
  /// **'Agente'**
  String get agentShort;

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

  /// No description provided for @agoDays.
  ///
  /// In es, this message translates to:
  /// **'hace {count} d'**
  String agoDays(int count);

  /// No description provided for @agoHours.
  ///
  /// In es, this message translates to:
  /// **'hace {count} h'**
  String agoHours(int count);

  /// No description provided for @agoMinutes.
  ///
  /// In es, this message translates to:
  /// **'hace {count} min'**
  String agoMinutes(int count);

  /// No description provided for @agoNow.
  ///
  /// In es, this message translates to:
  /// **'ahora'**
  String get agoNow;

  /// No description provided for @allCount.
  ///
  /// In es, this message translates to:
  /// **'Todas · {count}'**
  String allCount(int count);

  /// No description provided for @alreadyImported.
  ///
  /// In es, this message translates to:
  /// **'ya importado'**
  String get alreadyImported;

  /// No description provided for @alreadyUses.
  ///
  /// In es, this message translates to:
  /// **'Ya la usa'**
  String get alreadyUses;

  /// No description provided for @alsoOnThisComputer.
  ///
  /// In es, this message translates to:
  /// **'También en este equipo'**
  String get alsoOnThisComputer;

  /// No description provided for @announceClosed.
  ///
  /// In es, this message translates to:
  /// **'{name}: desconectado'**
  String announceClosed(String name);

  /// No description provided for @announceConnected.
  ///
  /// In es, this message translates to:
  /// **'{name}: conectado'**
  String announceConnected(String name);

  /// No description provided for @announceFailed.
  ///
  /// In es, this message translates to:
  /// **'{name}: no se pudo conectar. {why}'**
  String announceFailed(String name, String why);

  /// No description provided for @announcePrompt.
  ///
  /// In es, this message translates to:
  /// **'{name} pregunta algo antes de seguir'**
  String announcePrompt(String name);

  /// No description provided for @announceReconnecting.
  ///
  /// In es, this message translates to:
  /// **'{name}: se cortó, reconectando'**
  String announceReconnecting(String name);

  /// No description provided for @announceTunnelFailed.
  ///
  /// In es, this message translates to:
  /// **'El túnel «{name}» no se abrió: {why}'**
  String announceTunnelFailed(String name, String why);

  /// No description provided for @announceTunnelLost.
  ///
  /// In es, this message translates to:
  /// **'Se cortó el túnel «{name}»'**
  String announceTunnelLost(String name);

  /// No description provided for @announceTunnelOpen.
  ///
  /// In es, this message translates to:
  /// **'Túnel «{name}» abierto en el puerto {port}'**
  String announceTunnelOpen(String name, int port);

  /// No description provided for @anyDestination.
  ///
  /// In es, this message translates to:
  /// **'Cualquier destino'**
  String get anyDestination;

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

  /// No description provided for @asTyped.
  ///
  /// In es, this message translates to:
  /// **'tal cual, sin guardarlo'**
  String get asTyped;

  /// No description provided for @askedWhenRun.
  ///
  /// In es, this message translates to:
  /// **'Se pregunta al ejecutarlo'**
  String get askedWhenRun;

  /// No description provided for @askedWhenRunHint.
  ///
  /// In es, this message translates to:
  /// **'Sale de lo que escribes entre llaves.'**
  String get askedWhenRunHint;

  /// No description provided for @asks.
  ///
  /// In es, this message translates to:
  /// **'Pregunta'**
  String get asks;

  /// No description provided for @asksNothing.
  ///
  /// In es, this message translates to:
  /// **'No pregunta nada. Escribe {example} donde quieras que pregunte.'**
  String asksNothing(String example);

  /// No description provided for @awayFor.
  ///
  /// In es, this message translates to:
  /// **'{time} fuera'**
  String awayFor(String time);

  /// No description provided for @back.
  ///
  /// In es, this message translates to:
  /// **'Atrás'**
  String get back;

  /// No description provided for @backAgain.
  ///
  /// In es, this message translates to:
  /// **'Conectado de nuevo a {host}'**
  String backAgain(String host);

  /// No description provided for @badgeChanges.
  ///
  /// In es, this message translates to:
  /// **'cambia'**
  String get badgeChanges;

  /// No description provided for @badgeLeaves.
  ///
  /// In es, this message translates to:
  /// **'la deja'**
  String get badgeLeaves;

  /// No description provided for @badgeNew.
  ///
  /// In es, this message translates to:
  /// **'nueva'**
  String get badgeNew;

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

  /// No description provided for @bracesWord.
  ///
  /// In es, this message translates to:
  /// **'llaves'**
  String get bracesWord;

  /// No description provided for @bringsTunnels.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{trae 1 túnel} other{trae {count} túneles}}'**
  String bringsTunnels(int count);

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

  /// No description provided for @bySsh.
  ///
  /// In es, this message translates to:
  /// **'por SSH'**
  String get bySsh;

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

  /// No description provided for @certExpiredOn.
  ///
  /// In es, this message translates to:
  /// **'caducó el {date}'**
  String certExpiredOn(String date);

  /// No description provided for @certExpiresIn.
  ///
  /// In es, this message translates to:
  /// **'caduca en {days, plural, =1{1 día} other{{days} días}}'**
  String certExpiresIn(int days);

  /// No description provided for @certForever.
  ///
  /// In es, this message translates to:
  /// **'sin caducidad'**
  String get certForever;

  /// No description provided for @certNextToKey.
  ///
  /// In es, this message translates to:
  /// **'Junto a la clave (-cert.pub): se usa sin añadirlo.'**
  String get certNextToKey;

  /// No description provided for @certNoAuthority.
  ///
  /// In es, this message translates to:
  /// **'ninguna @cert-authority de known_hosts cubre este host'**
  String get certNoAuthority;

  /// No description provided for @certNotForHost.
  ///
  /// In es, this message translates to:
  /// **'no se emitió para este nombre'**
  String get certNotForHost;

  /// No description provided for @certNotHost.
  ///
  /// In es, this message translates to:
  /// **'no es un certificado de host'**
  String get certNotHost;

  /// No description provided for @certOutOfDate.
  ///
  /// In es, this message translates to:
  /// **'ha caducado o aún no es válido'**
  String get certOutOfDate;

  /// No description provided for @certUntil.
  ///
  /// In es, this message translates to:
  /// **'hasta el {date}'**
  String certUntil(String date);

  /// No description provided for @certUntrusted.
  ///
  /// In es, this message translates to:
  /// **'no lo firma una autoridad de confianza'**
  String get certUntrusted;

  /// No description provided for @certificate.
  ///
  /// In es, this message translates to:
  /// **'certificado'**
  String get certificate;

  /// No description provided for @certificateExpired.
  ///
  /// In es, this message translates to:
  /// **'certificado caducado'**
  String get certificateExpired;

  /// No description provided for @certificateTitle.
  ///
  /// In es, this message translates to:
  /// **'Certificado'**
  String get certificateTitle;

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

  /// No description provided for @checkNotImported.
  ///
  /// In es, this message translates to:
  /// **'{label} usa {protocol} y no se ha importado.'**
  String checkNotImported(String label, String protocol);

  /// No description provided for @checkTitle.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Revisa 1 cosa} other{Revisa {count} cosas}}'**
  String checkTitle(int count);

  /// No description provided for @checkWithoutKey.
  ///
  /// In es, this message translates to:
  /// **'«{label}» se ha quedado sin clave: la suya no está en ~/.ssh.'**
  String checkWithoutKey(String label);

  /// No description provided for @checkedFingerprint.
  ///
  /// In es, this message translates to:
  /// **'He comprobado la huella nueva'**
  String get checkedFingerprint;

  /// No description provided for @checking.
  ///
  /// In es, this message translates to:
  /// **'comprobando…'**
  String get checking;

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

  /// No description provided for @chooseExportedFile.
  ///
  /// In es, this message translates to:
  /// **'Elige el archivo exportado'**
  String get chooseExportedFile;

  /// No description provided for @chooseFile.
  ///
  /// In es, this message translates to:
  /// **'Elegir…'**
  String get chooseFile;

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

  /// No description provided for @clearAction.
  ///
  /// In es, this message translates to:
  /// **'Borrar'**
  String get clearAction;

  /// No description provided for @clearFilter.
  ///
  /// In es, this message translates to:
  /// **'Quitar el filtro'**
  String get clearFilter;

  /// No description provided for @clearFinished.
  ///
  /// In es, this message translates to:
  /// **'Quitar las terminadas'**
  String get clearFinished;

  /// No description provided for @clearHistory.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0{Borrar el historial} =1{Borrar 1 comando} other{Borrar {count} comandos}}'**
  String clearHistory(int count);

  /// No description provided for @clearHistoryBody.
  ///
  /// In es, this message translates to:
  /// **'Los comandos que la paleta recuerda se olvidan, en todos los hosts.'**
  String get clearHistoryBody;

  /// No description provided for @clearHistoryTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Borrar el historial de comandos?'**
  String get clearHistoryTitle;

  /// No description provided for @clearRecent.
  ///
  /// In es, this message translates to:
  /// **'Borrar ({count})'**
  String clearRecent(int count);

  /// No description provided for @clearRecentBody.
  ///
  /// In es, this message translates to:
  /// **'La lista de la página de inicio y de la paleta queda vacía. Los hosts guardados no cambian.'**
  String get clearRecentBody;

  /// No description provided for @clearRecentTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Borrar las conexiones recientes?'**
  String get clearRecentTitle;

  /// No description provided for @clearScrollback.
  ///
  /// In es, this message translates to:
  /// **'Limpiar el búfer'**
  String get clearScrollback;

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

  /// No description provided for @closeAction.
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get closeAction;

  /// No description provided for @closeMarkedMany.
  ///
  /// In es, this message translates to:
  /// **'¿Cerrar {count} sesiones conectadas?'**
  String closeMarkedMany(int count);

  /// No description provided for @closeMarkedManyBody.
  ///
  /// In es, this message translates to:
  /// **'Son de entornos marcados: {names}.'**
  String closeMarkedManyBody(String names);

  /// No description provided for @closeMarkedOne.
  ///
  /// In es, this message translates to:
  /// **'¿Cerrar «{label}»?'**
  String closeMarkedOne(String label);

  /// No description provided for @closeMarkedOneBody.
  ///
  /// In es, this message translates to:
  /// **'Está conectada a un host de {env}: lo que esté en marcha en ella se corta.'**
  String closeMarkedOneBody(String env);

  /// No description provided for @closeOtherTabs.
  ///
  /// In es, this message translates to:
  /// **'Cerrar las demás'**
  String get closeOtherTabs;

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

  /// No description provided for @closeTabs.
  ///
  /// In es, this message translates to:
  /// **'Cerrar las {count}'**
  String closeTabs(int count);

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

  /// No description provided for @collapse.
  ///
  /// In es, this message translates to:
  /// **'Plegar'**
  String get collapse;

  /// No description provided for @colorBlue.
  ///
  /// In es, this message translates to:
  /// **'Azul'**
  String get colorBlue;

  /// No description provided for @colorGray.
  ///
  /// In es, this message translates to:
  /// **'Gris'**
  String get colorGray;

  /// No description provided for @colorGreen.
  ///
  /// In es, this message translates to:
  /// **'Verde'**
  String get colorGreen;

  /// No description provided for @colorOrange.
  ///
  /// In es, this message translates to:
  /// **'Naranja'**
  String get colorOrange;

  /// No description provided for @colorPink.
  ///
  /// In es, this message translates to:
  /// **'Rosa'**
  String get colorPink;

  /// No description provided for @colorRed.
  ///
  /// In es, this message translates to:
  /// **'Rojo'**
  String get colorRed;

  /// No description provided for @colorViolet.
  ///
  /// In es, this message translates to:
  /// **'Violeta'**
  String get colorViolet;

  /// No description provided for @colorYellow.
  ///
  /// In es, this message translates to:
  /// **'Amarillo'**
  String get colorYellow;

  /// No description provided for @comebackLine.
  ///
  /// In es, this message translates to:
  /// **'conectado de nuevo a las {time} · estuvo fuera {away} · terminal nuevo'**
  String comebackLine(String time, String away);

  /// No description provided for @comingFromOther.
  ///
  /// In es, this message translates to:
  /// **'¿Vienes de PuTTY, MobaXterm o SecureCRT?'**
  String get comingFromOther;

  /// No description provided for @command.
  ///
  /// In es, this message translates to:
  /// **'Comando'**
  String get command;

  /// No description provided for @commandHint.
  ///
  /// In es, this message translates to:
  /// **'Cada línea se envía como si la escribieras. Para escribir {open} tal cual, pon {escaped}.'**
  String commandHint(String open, String escaped);

  /// No description provided for @commandHistory.
  ///
  /// In es, this message translates to:
  /// **'Historial de comandos'**
  String get commandHistory;

  /// No description provided for @commandHistoryHelp.
  ///
  /// In es, this message translates to:
  /// **'Lo que ejecutas en los terminales se guarda en este equipo (nunca en el vault) para buscarlo y repetirlo con {keys}. Nunca se guarda lo que la pantalla no muestra, como una contraseña, ni lo que empieza por un espacio.'**
  String commandHistoryHelp(String keys);

  /// No description provided for @commandPalette.
  ///
  /// In es, this message translates to:
  /// **'Paleta de comandos'**
  String get commandPalette;

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

  /// No description provided for @connectTimeoutAfter.
  ///
  /// In es, this message translates to:
  /// **'Se rinde a los {seconds} s sin respuesta'**
  String connectTimeoutAfter(int seconds);

  /// No description provided for @connectTimeoutLabel.
  ///
  /// In es, this message translates to:
  /// **'Tiempo para conectar'**
  String get connectTimeoutLabel;

  /// No description provided for @connectToAddress.
  ///
  /// In es, this message translates to:
  /// **'Conectar a {address}'**
  String connectToAddress(String address);

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
  /// **'Lo que no cambies aquí se hereda. Manda lo del host, luego su identidad, luego sus grupos y, al final, los valores por defecto.'**
  String get connectionHint;

  /// No description provided for @connectionLost.
  ///
  /// In es, this message translates to:
  /// **'Se perdió la conexión con {label}{why}.'**
  String connectionLost(String label, String why);

  /// No description provided for @connectionLostTitle.
  ///
  /// In es, this message translates to:
  /// **'Se perdió la conexión con {host}'**
  String connectionLostTitle(String host);

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

  /// No description provided for @copyAction.
  ///
  /// In es, this message translates to:
  /// **'Copiar'**
  String get copyAction;

  /// No description provided for @copyAddress.
  ///
  /// In es, this message translates to:
  /// **'Copiar dirección'**
  String get copyAddress;

  /// No description provided for @copyFingerprint.
  ///
  /// In es, this message translates to:
  /// **'Copiar la huella'**
  String get copyFingerprint;

  /// No description provided for @copyOfName.
  ///
  /// In es, this message translates to:
  /// **'{name} (copia)'**
  String copyOfName(String name);

  /// No description provided for @copyPath.
  ///
  /// In es, this message translates to:
  /// **'Copiar la ruta'**
  String get copyPath;

  /// No description provided for @copyPublicKey.
  ///
  /// In es, this message translates to:
  /// **'Copiar la clave pública'**
  String get copyPublicKey;

  /// No description provided for @copyReport.
  ///
  /// In es, this message translates to:
  /// **'Copiar el informe'**
  String get copyReport;

  /// No description provided for @create.
  ///
  /// In es, this message translates to:
  /// **'Crear'**
  String get create;

  /// No description provided for @csvSpreadsheet.
  ///
  /// In es, this message translates to:
  /// **'CSV (hoja de cálculo)'**
  String get csvSpreadsheet;

  /// No description provided for @ctrlShiftPrefix.
  ///
  /// In es, this message translates to:
  /// **'Ctrl+Mayús+'**
  String get ctrlShiftPrefix;

  /// No description provided for @currentPassphrase.
  ///
  /// In es, this message translates to:
  /// **'Frase de paso actual'**
  String get currentPassphrase;

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

  /// No description provided for @defaultValueOptional.
  ///
  /// In es, this message translates to:
  /// **'Valor por defecto (opcional)'**
  String get defaultValueOptional;

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
  /// **'Eliminar grupo…'**
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

  /// No description provided for @deleteIdentityBody.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{El host que la usa volverá a heredar el usuario y las claves de su grupo.} other{Los {count} hosts que la usan volverán a heredar el usuario y las claves de sus grupos.}}'**
  String deleteIdentityBody(int count);

  /// No description provided for @deleteIdentityTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar «{name}»?'**
  String deleteIdentityTitle(String name);

  /// No description provided for @deleteIdentityUnused.
  ///
  /// In es, this message translates to:
  /// **'Nadie la usa. Las claves siguen en su sitio: solo se borra la identidad.'**
  String get deleteIdentityUnused;

  /// No description provided for @deleteKeyBody.
  ///
  /// In es, this message translates to:
  /// **'Se borran {path} y su .pub de este equipo. No se puede deshacer: si no tienes otra copia, no podrás volver a entrar con ella.'**
  String deleteKeyBody(String path);

  /// No description provided for @deleteKeyTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar {name}?'**
  String deleteKeyTitle(String name);

  /// No description provided for @deleteKeyUsed.
  ///
  /// In es, this message translates to:
  /// **'La usan {who}: seguirán nombrándola y no podrán entrar con ella.'**
  String deleteKeyUsed(String who);

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

  /// No description provided for @deleteWorkspaceBody.
  ///
  /// In es, this message translates to:
  /// **'Solo se elimina la distribución guardada: los hosts, y lo que esté abierto, se quedan.'**
  String get deleteWorkspaceBody;

  /// No description provided for @deleteWorkspaceTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar «{name}»?'**
  String deleteWorkspaceTitle(String name);

  /// No description provided for @deletedHost.
  ///
  /// In es, this message translates to:
  /// **'(host eliminado)'**
  String get deletedHost;

  /// No description provided for @deletedIdentity.
  ///
  /// In es, this message translates to:
  /// **'(identidad eliminada)'**
  String get deletedIdentity;

  /// No description provided for @destination.
  ///
  /// In es, this message translates to:
  /// **'Destino'**
  String get destination;

  /// No description provided for @details.
  ///
  /// In es, this message translates to:
  /// **'Detalles'**
  String get details;

  /// No description provided for @discardChanges.
  ///
  /// In es, this message translates to:
  /// **'Descartar'**
  String get discardChanges;

  /// No description provided for @discardChangesBody.
  ///
  /// In es, this message translates to:
  /// **'Lo que has cambiado en este panel no se ha guardado.'**
  String get discardChangesBody;

  /// No description provided for @discardChangesTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Descartar los cambios?'**
  String get discardChangesTitle;

  /// No description provided for @dividerHint.
  ///
  /// In es, this message translates to:
  /// **'Arrastra para cambiar el tamaño · doble clic: mitad y mitad'**
  String get dividerHint;

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

  /// No description provided for @dragPaneHint.
  ///
  /// In es, this message translates to:
  /// **'Arrastra para mover el panel: a otro panel o a la barra de pestañas'**
  String get dragPaneHint;

  /// No description provided for @dragToOrder.
  ///
  /// In es, this message translates to:
  /// **'arrastra para ordenar'**
  String get dragToOrder;

  /// No description provided for @dropAbove.
  ///
  /// In es, this message translates to:
  /// **'encima de {pane}'**
  String dropAbove(String pane);

  /// No description provided for @dropAskFirst.
  ///
  /// In es, this message translates to:
  /// **'Si alguno ya existe, te preguntamos antes de tocarlo.'**
  String get dropAskFirst;

  /// No description provided for @dropBelow.
  ///
  /// In es, this message translates to:
  /// **'debajo de {pane}'**
  String dropBelow(String pane);

  /// No description provided for @dropBottom.
  ///
  /// In es, this message translates to:
  /// **'abajo'**
  String get dropBottom;

  /// No description provided for @dropHereToMove.
  ///
  /// In es, this message translates to:
  /// **'Suéltalo para moverlo aquí'**
  String get dropHereToMove;

  /// No description provided for @dropHostNewTab.
  ///
  /// In es, this message translates to:
  /// **'Soltar aquí: abrir {name} en una pestaña nueva'**
  String dropHostNewTab(String name);

  /// No description provided for @dropLeft.
  ///
  /// In es, this message translates to:
  /// **'a la izquierda'**
  String get dropLeft;

  /// No description provided for @dropLeftOf.
  ///
  /// In es, this message translates to:
  /// **'a la izquierda de {pane}'**
  String dropLeftOf(String pane);

  /// No description provided for @dropMove.
  ///
  /// In es, this message translates to:
  /// **'Soltar: {name} {where}'**
  String dropMove(String name, String where);

  /// No description provided for @dropNewTab.
  ///
  /// In es, this message translates to:
  /// **'Soltar aquí: {name} en una pestaña nueva'**
  String dropNewTab(String name);

  /// No description provided for @dropOpenHost.
  ///
  /// In es, this message translates to:
  /// **'Soltar: abrir {name} {where}'**
  String dropOpenHost(String name, String where);

  /// No description provided for @dropRight.
  ///
  /// In es, this message translates to:
  /// **'a la derecha'**
  String get dropRight;

  /// No description provided for @dropRightOf.
  ///
  /// In es, this message translates to:
  /// **'a la derecha de {pane}'**
  String dropRightOf(String pane);

  /// No description provided for @dropSplitAround.
  ///
  /// In es, this message translates to:
  /// **'Soltar: {name} {where}; {other}, un panel nuevo'**
  String dropSplitAround(String name, String where, String other);

  /// No description provided for @dropTabLast.
  ///
  /// In es, this message translates to:
  /// **'Soltar aquí: {name} al final'**
  String dropTabLast(String name);

  /// No description provided for @dropToDownload.
  ///
  /// In es, this message translates to:
  /// **'Suelta para descargar aquí'**
  String get dropToDownload;

  /// No description provided for @dropToImport.
  ///
  /// In es, this message translates to:
  /// **'O arrastra aquí el archivo o la carpeta: se reconoce solo.'**
  String get dropToImport;

  /// No description provided for @dropToUpload.
  ///
  /// In es, this message translates to:
  /// **'Suelta para subir aquí'**
  String get dropToUpload;

  /// No description provided for @dropTop.
  ///
  /// In es, this message translates to:
  /// **'arriba'**
  String get dropTop;

  /// No description provided for @duplicate.
  ///
  /// In es, this message translates to:
  /// **'Duplicar'**
  String get duplicate;

  /// No description provided for @duplicateTab.
  ///
  /// In es, this message translates to:
  /// **'Duplicar'**
  String get duplicateTab;

  /// No description provided for @durationHours.
  ///
  /// In es, this message translates to:
  /// **'{hours} h {minutes} min'**
  String durationHours(int hours, int minutes);

  /// No description provided for @durationMinSec.
  ///
  /// In es, this message translates to:
  /// **'{minutes} min {seconds} s'**
  String durationMinSec(int minutes, int seconds);

  /// No description provided for @durationMinutes.
  ///
  /// In es, this message translates to:
  /// **'{count} min'**
  String durationMinutes(int count);

  /// No description provided for @durationSec.
  ///
  /// In es, this message translates to:
  /// **'{seconds} s'**
  String durationSec(int seconds);

  /// No description provided for @durationUnderMinute.
  ///
  /// In es, this message translates to:
  /// **'menos de 1 min'**
  String get durationUnderMinute;

  /// No description provided for @dynamicSentence.
  ///
  /// In es, this message translates to:
  /// **'Usa {here} como proxy SOCKS5: las conexiones salen de {host}.'**
  String dynamicSentence(String here, String host);

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

  /// No description provided for @editIdentity.
  ///
  /// In es, this message translates to:
  /// **'Editar identidad'**
  String get editIdentity;

  /// No description provided for @editSnippet.
  ///
  /// In es, this message translates to:
  /// **'Editar snippet'**
  String get editSnippet;

  /// No description provided for @editTheIdentity.
  ///
  /// In es, this message translates to:
  /// **'Editar la identidad'**
  String get editTheIdentity;

  /// No description provided for @editTunnel.
  ///
  /// In es, this message translates to:
  /// **'Editar túnel'**
  String get editTunnel;

  /// No description provided for @emptyFolder.
  ///
  /// In es, this message translates to:
  /// **'Esta carpeta está vacía'**
  String get emptyFolder;

  /// No description provided for @emptyPane.
  ///
  /// In es, this message translates to:
  /// **'panel vacío'**
  String get emptyPane;

  /// No description provided for @envColor.
  ///
  /// In es, this message translates to:
  /// **'Color'**
  String get envColor;

  /// No description provided for @envDialogTitle.
  ///
  /// In es, this message translates to:
  /// **'Otro entorno'**
  String get envDialogTitle;

  /// No description provided for @envHint.
  ///
  /// In es, this message translates to:
  /// **'Marca las pestañas y los terminales de estos hosts con un color y un nombre corto, para no confundir un servidor con otro.'**
  String get envHint;

  /// No description provided for @envInheritors.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Lo hereda el host del grupo; puede cambiarlo.} other{Lo heredan los {count} hosts del grupo y sus subgrupos; cada host puede cambiarlo.}}'**
  String envInheritors(int count);

  /// No description provided for @envName.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get envName;

  /// No description provided for @envNeedsName.
  ///
  /// In es, this message translates to:
  /// **'Ponle un nombre al entorno.'**
  String get envNeedsName;

  /// No description provided for @envNone.
  ///
  /// In es, this message translates to:
  /// **'Ninguno'**
  String get envNone;

  /// No description provided for @envNoneNote.
  ///
  /// In es, this message translates to:
  /// **'sin marca'**
  String get envNoneNote;

  /// No description provided for @envOther.
  ///
  /// In es, this message translates to:
  /// **'Otro, con su nombre y color…'**
  String get envOther;

  /// No description provided for @envPersonal.
  ///
  /// In es, this message translates to:
  /// **'Personal'**
  String get envPersonal;

  /// No description provided for @envPersonalShort.
  ///
  /// In es, this message translates to:
  /// **'casa'**
  String get envPersonalShort;

  /// No description provided for @envPreview.
  ///
  /// In es, this message translates to:
  /// **'Vista previa: una pestaña y un terminal marcados como {name}'**
  String envPreview(String name);

  /// No description provided for @envPreviewHost.
  ///
  /// In es, this message translates to:
  /// **'web-1'**
  String get envPreviewHost;

  /// No description provided for @envProduction.
  ///
  /// In es, this message translates to:
  /// **'Producción'**
  String get envProduction;

  /// No description provided for @envProductionShort.
  ///
  /// In es, this message translates to:
  /// **'prod'**
  String get envProductionShort;

  /// No description provided for @envShort.
  ///
  /// In es, this message translates to:
  /// **'Nombre corto'**
  String get envShort;

  /// No description provided for @envShortHelp.
  ///
  /// In es, this message translates to:
  /// **'En las pestañas y en la barra lateral'**
  String get envShortHelp;

  /// No description provided for @envStaging.
  ///
  /// In es, this message translates to:
  /// **'Preproducción'**
  String get envStaging;

  /// No description provided for @envStagingShort.
  ///
  /// In es, this message translates to:
  /// **'pre'**
  String get envStagingShort;

  /// No description provided for @envTesting.
  ///
  /// In es, this message translates to:
  /// **'Pruebas'**
  String get envTesting;

  /// No description provided for @envTestingShort.
  ///
  /// In es, this message translates to:
  /// **'pruebas'**
  String get envTestingShort;

  /// No description provided for @envUse.
  ///
  /// In es, this message translates to:
  /// **'Usar'**
  String get envUse;

  /// No description provided for @environment.
  ///
  /// In es, this message translates to:
  /// **'Entorno'**
  String get environment;

  /// No description provided for @equalizePanes.
  ///
  /// In es, this message translates to:
  /// **'Igualar tamaños'**
  String get equalizePanes;

  /// No description provided for @errConflict.
  ///
  /// In es, this message translates to:
  /// **'ha cambiado mientras tanto'**
  String get errConflict;

  /// No description provided for @errCycle.
  ///
  /// In es, this message translates to:
  /// **'un grupo no puede estar dentro de sí mismo'**
  String get errCycle;

  /// No description provided for @errFileChanged.
  ///
  /// In es, this message translates to:
  /// **'el archivo ha cambiado mientras tanto'**
  String get errFileChanged;

  /// No description provided for @errInUse.
  ///
  /// In es, this message translates to:
  /// **'otros hosts saltan por él'**
  String get errInUse;

  /// No description provided for @errInternal.
  ///
  /// In es, this message translates to:
  /// **'algo ha fallado dentro de OpenWard (más en «Detalles»)'**
  String get errInternal;

  /// No description provided for @errInvalid.
  ///
  /// In es, this message translates to:
  /// **'lo que dice no encaja'**
  String get errInvalid;

  /// No description provided for @errNewerFormat.
  ///
  /// In es, this message translates to:
  /// **'tus datos los escribió una versión más nueva de OpenWard'**
  String get errNewerFormat;

  /// No description provided for @errNotFound.
  ///
  /// In es, this message translates to:
  /// **'ya no existe'**
  String get errNotFound;

  /// No description provided for @errOpenElsewhere.
  ///
  /// In es, this message translates to:
  /// **'otro OpenWard tiene abiertos estos datos'**
  String get errOpenElsewhere;

  /// No description provided for @errStorage.
  ///
  /// In es, this message translates to:
  /// **'el disco no lo ha aceptado'**
  String get errStorage;

  /// No description provided for @errorDetailsHint.
  ///
  /// In es, this message translates to:
  /// **'En inglés, tal como lo dice el núcleo: cópialo si nos informas del problema.'**
  String get errorDetailsHint;

  /// No description provided for @errorDetailsTitle.
  ///
  /// In es, this message translates to:
  /// **'Detalles del error'**
  String get errorDetailsTitle;

  /// No description provided for @exampleVariable.
  ///
  /// In es, this message translates to:
  /// **'nombre'**
  String get exampleVariable;

  /// No description provided for @expand.
  ///
  /// In es, this message translates to:
  /// **'Desplegar'**
  String get expand;

  /// No description provided for @exportEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Exportar…'**
  String get exportEllipsis;

  /// No description provided for @failureAuth.
  ///
  /// In es, this message translates to:
  /// **'{user}@{label} no ha podido autenticarse.'**
  String failureAuth(String user, String label);

  /// No description provided for @failureAuthCertExpired.
  ///
  /// In es, this message translates to:
  /// **'No se pudo entrar como {user} en {host}: el certificado {path} ha caducado; pide uno nuevo.'**
  String failureAuthCertExpired(String user, String host, String path);

  /// No description provided for @failureAuthMethods.
  ///
  /// In es, this message translates to:
  /// **'{user}@{label} no ha podido autenticarse (el servidor acepta: {methods}).'**
  String failureAuthMethods(String user, String label, String methods);

  /// No description provided for @failureAuthSecurityKey.
  ///
  /// In es, this message translates to:
  /// **'No se pudo entrar como {user} en {host}: {why}.'**
  String failureAuthSecurityKey(String user, String host, String why);

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

  /// No description provided for @failureHostKeyRevoked.
  ///
  /// In es, this message translates to:
  /// **'{label} usa una clave revocada ({fingerprint}): se rechaza siempre. Si es un error, quítala de la lista de hosts conocidos.'**
  String failureHostKeyRevoked(String label, String fingerprint);

  /// No description provided for @failureNoSftp.
  ///
  /// In es, this message translates to:
  /// **'{label} no tiene SFTP: al servidor le falta sftp-server.'**
  String failureNoSftp(String label);

  /// No description provided for @failureOther.
  ///
  /// In es, this message translates to:
  /// **'Algo ha fallado (más en «Detalles»).'**
  String get failureOther;

  /// No description provided for @failureSerialBusy.
  ///
  /// In es, this message translates to:
  /// **'{port} está abierto en otro programa, o en otra pestaña.'**
  String failureSerialBusy(String port);

  /// No description provided for @failureSerialDenied.
  ///
  /// In es, this message translates to:
  /// **'Tu usuario no puede abrir {port}.'**
  String failureSerialDenied(String port);

  /// No description provided for @failureSerialDeniedLinux.
  ///
  /// In es, this message translates to:
  /// **'Tu usuario no puede abrir {port}: añádelo al grupo dialout (sudo usermod -aG dialout, con tu usuario) y vuelve a entrar en la sesión.'**
  String failureSerialDeniedLinux(String port);

  /// No description provided for @failureSerialGone.
  ///
  /// In es, this message translates to:
  /// **'Se ha desconectado {port}: ¿se ha soltado el cable?'**
  String failureSerialGone(String port);

  /// No description provided for @failureSerialMissing.
  ///
  /// In es, this message translates to:
  /// **'No hay ningún puerto {port}: ¿está conectado el cable?'**
  String failureSerialMissing(String port);

  /// No description provided for @failureSerialOther.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido abrir {port} (más en «Detalles»).'**
  String failureSerialOther(String port);

  /// No description provided for @failureSerialSettings.
  ///
  /// In es, this message translates to:
  /// **'{port} no admite esa velocidad o ese formato.'**
  String failureSerialSettings(String port);

  /// No description provided for @favorite.
  ///
  /// In es, this message translates to:
  /// **'Favorito'**
  String get favorite;

  /// No description provided for @favoriteLower.
  ///
  /// In es, this message translates to:
  /// **'favorito'**
  String get favoriteLower;

  /// No description provided for @favoriteNote.
  ///
  /// In es, this message translates to:
  /// **'arriba en la barra, en el raíl y en el inicio'**
  String get favoriteNote;

  /// No description provided for @favorites.
  ///
  /// In es, this message translates to:
  /// **'Favoritos'**
  String get favorites;

  /// No description provided for @favoritesEmpty.
  ///
  /// In es, this message translates to:
  /// **'Marca con ★ los hosts que más usas (en su página, al pasar el ratón, o en su editor) y aparecerán aquí, en el orden que les des.'**
  String get favoritesEmpty;

  /// No description provided for @favoritesEmptyShort.
  ///
  /// In es, this message translates to:
  /// **'Marca con ★ en Hosts los que más uses.'**
  String get favoritesEmptyShort;

  /// No description provided for @featureFirewall.
  ///
  /// In es, this message translates to:
  /// **'el firewall «{name}» de SecureCRT'**
  String featureFirewall(String name);

  /// No description provided for @featureHardwareKey.
  ///
  /// In es, this message translates to:
  /// **'una llave de seguridad'**
  String get featureHardwareKey;

  /// No description provided for @featureIncompleteProxy.
  ///
  /// In es, this message translates to:
  /// **'un proxy sin dirección o sin puerto'**
  String get featureIncompleteProxy;

  /// No description provided for @featureJumpNotSsh.
  ///
  /// In es, this message translates to:
  /// **'un salto por un perfil que no es SSH'**
  String get featureJumpNotSsh;

  /// No description provided for @featureJumpThrough.
  ///
  /// In es, this message translates to:
  /// **'un salto por {target}, que no está'**
  String featureJumpThrough(String target);

  /// No description provided for @featureMobaCredential.
  ///
  /// In es, this message translates to:
  /// **'una credencial guardada en MobaXterm'**
  String get featureMobaCredential;

  /// No description provided for @featureProxy.
  ///
  /// In es, this message translates to:
  /// **'un proxy {kind}'**
  String featureProxy(String kind);

  /// No description provided for @featureSecureCrtGlobalKey.
  ///
  /// In es, this message translates to:
  /// **'la clave global de SecureCRT'**
  String get featureSecureCrtGlobalKey;

  /// No description provided for @featureSocks4.
  ///
  /// In es, this message translates to:
  /// **'un proxy SOCKS4'**
  String get featureSocks4;

  /// No description provided for @featureTabbyVault.
  ///
  /// In es, this message translates to:
  /// **'una clave del almacén de Tabby'**
  String get featureTabbyVault;

  /// No description provided for @featureTelnetProxy.
  ///
  /// In es, this message translates to:
  /// **'un proxy Telnet'**
  String get featureTelnetProxy;

  /// No description provided for @featureX11.
  ///
  /// In es, this message translates to:
  /// **'el reenvío de X11'**
  String get featureX11;

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

  /// No description provided for @fileName.
  ///
  /// In es, this message translates to:
  /// **'Archivo'**
  String get fileName;

  /// No description provided for @fileNotFound.
  ///
  /// In es, this message translates to:
  /// **'No existe: {path}'**
  String fileNotFound(String path);

  /// No description provided for @fileOther.
  ///
  /// In es, this message translates to:
  /// **'Algo ha fallado con el archivo (más en «Detalles»).'**
  String get fileOther;

  /// No description provided for @filledInEachPane.
  ///
  /// In es, this message translates to:
  /// **'También se rellenan solas, en cada panel:'**
  String get filledInEachPane;

  /// No description provided for @filterFolder.
  ///
  /// In es, this message translates to:
  /// **'Filtrar en esta carpeta'**
  String get filterFolder;

  /// No description provided for @filterHostsAndGroups.
  ///
  /// In es, this message translates to:
  /// **'Filtrar hosts y grupos'**
  String get filterHostsAndGroups;

  /// No description provided for @filterIdentities.
  ///
  /// In es, this message translates to:
  /// **'Filtrar por nombre, usuario o clave'**
  String get filterIdentities;

  /// No description provided for @filterSnippets.
  ///
  /// In es, this message translates to:
  /// **'Filtrar por nombre o comando'**
  String get filterSnippets;

  /// No description provided for @filterTunnels.
  ///
  /// In es, this message translates to:
  /// **'Filtrar por nombre, host o puerto'**
  String get filterTunnels;

  /// No description provided for @findASnippet.
  ///
  /// In es, this message translates to:
  /// **'Buscar un snippet'**
  String get findASnippet;

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

  /// No description provided for @findEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Buscar…'**
  String get findEllipsis;

  /// No description provided for @findHint.
  ///
  /// In es, this message translates to:
  /// **'Buscar en el terminal'**
  String get findHint;

  /// No description provided for @findInTerminal.
  ///
  /// In es, this message translates to:
  /// **'Buscar en el terminal'**
  String get findInTerminal;

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

  /// No description provided for @findOutSystem.
  ///
  /// In es, this message translates to:
  /// **'Averiguar el sistema'**
  String get findOutSystem;

  /// No description provided for @findSearching.
  ///
  /// In es, this message translates to:
  /// **'Buscando…'**
  String get findSearching;

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

  /// No description provided for @fingerprintNeedsPublic.
  ///
  /// In es, this message translates to:
  /// **'Sin .pub: huella desconocida'**
  String get fingerprintNeedsPublic;

  /// No description provided for @firstConnectionTo.
  ///
  /// In es, this message translates to:
  /// **'Primera conexión con {label}'**
  String firstConnectionTo(String label);

  /// No description provided for @flowHardware.
  ///
  /// In es, this message translates to:
  /// **'RTS/CTS (hardware)'**
  String get flowHardware;

  /// No description provided for @flowNone.
  ///
  /// In es, this message translates to:
  /// **'Ninguno'**
  String get flowNone;

  /// No description provided for @flowSoftware.
  ///
  /// In es, this message translates to:
  /// **'XON/XOFF (software)'**
  String get flowSoftware;

  /// No description provided for @foldSidebar.
  ///
  /// In es, this message translates to:
  /// **'Plegar la barra lateral'**
  String get foldSidebar;

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

  /// No description provided for @forgetAction.
  ///
  /// In es, this message translates to:
  /// **'Olvidar'**
  String get forgetAction;

  /// No description provided for @forgetFileKeyBody.
  ///
  /// In es, this message translates to:
  /// **'Se borra esa línea del fichero, que también usa el ssh de tu sistema, y antes se guarda una copia en known_hosts.old, como hace ssh-keygen -R.'**
  String get forgetFileKeyBody;

  /// No description provided for @forgetFileKeyTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Quitar la clave de {name} de {file}?'**
  String forgetFileKeyTitle(String name, String file);

  /// No description provided for @forgetKeyBody.
  ///
  /// In es, this message translates to:
  /// **'OpenWard deja de confiar en esta clave.'**
  String get forgetKeyBody;

  /// No description provided for @forgetKeyThen.
  ///
  /// In es, this message translates to:
  /// **'La próxima vez que conectes se preguntará otra vez por su clave, salvo que haya otra en la que confíes.'**
  String get forgetKeyThen;

  /// No description provided for @forgetKeyTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Olvidar la clave de {name}?'**
  String forgetKeyTitle(String name);

  /// No description provided for @forward.
  ///
  /// In es, this message translates to:
  /// **'Reenvío'**
  String get forward;

  /// No description provided for @foundMobaXterm.
  ///
  /// In es, this message translates to:
  /// **'Sesiones en {path}'**
  String foundMobaXterm(String path);

  /// No description provided for @foundSessions.
  ///
  /// In es, this message translates to:
  /// **'Sesiones guardadas en {path}'**
  String foundSessions(String path);

  /// No description provided for @foundSshConfig.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 host} other{{count} hosts}}{existing, plural, =0{} other{ · {existing} ya importados}}'**
  String foundSshConfig(int count, int existing);

  /// No description provided for @foundTabby.
  ///
  /// In es, this message translates to:
  /// **'Su configuración, en {path}'**
  String foundTabby(String path);

  /// No description provided for @foundTermius.
  ///
  /// In es, this message translates to:
  /// **'Instalado: se leen sus datos directamente, sin exportar nada'**
  String get foundTermius;

  /// No description provided for @fromDefault.
  ///
  /// In es, this message translates to:
  /// **'Valor por defecto'**
  String get fromDefault;

  /// No description provided for @fromExportedFile.
  ///
  /// In es, this message translates to:
  /// **'Desde un archivo exportado'**
  String get fromExportedFile;

  /// No description provided for @fromGroup.
  ///
  /// In es, this message translates to:
  /// **'Del grupo {name}'**
  String fromGroup(String name);

  /// No description provided for @fromHere.
  ///
  /// In es, this message translates to:
  /// **'desde aquí'**
  String get fromHere;

  /// No description provided for @fromIdentity.
  ///
  /// In es, this message translates to:
  /// **'De la identidad {name}'**
  String fromIdentity(String name);

  /// No description provided for @fromNowhere.
  ///
  /// In es, this message translates to:
  /// **'Sin valor: lo decide la conexión'**
  String get fromNowhere;

  /// No description provided for @fromSshConfig.
  ///
  /// In es, this message translates to:
  /// **'de ~/.ssh/config'**
  String get fromSshConfig;

  /// No description provided for @fromThere.
  ///
  /// In es, this message translates to:
  /// **'desde allí'**
  String get fromThere;

  /// No description provided for @goToPage.
  ///
  /// In es, this message translates to:
  /// **'Ir a {page}'**
  String goToPage(String page);

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

  /// No description provided for @groupNamed.
  ///
  /// In es, this message translates to:
  /// **'Grupo {name}'**
  String groupNamed(String name);

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

  /// No description provided for @groups.
  ///
  /// In es, this message translates to:
  /// **'Grupos'**
  String get groups;

  /// No description provided for @hashedName.
  ///
  /// In es, this message translates to:
  /// **'Nombre cifrado'**
  String get hashedName;

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

  /// No description provided for @host.
  ///
  /// In es, this message translates to:
  /// **'Host'**
  String get host;

  /// No description provided for @hostCountText.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0{ningún host} =1{1 host} other{{count} hosts}}'**
  String hostCountText(int count);

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

  /// No description provided for @hostKeyOtherTypeBody.
  ///
  /// In es, this message translates to:
  /// **'OpenWard conoce {where} por su clave {known}, pero ahora ofrece una {offered} que no conoce. Puede que el servidor haya cambiado sus claves, o que otro equipo se haga pasar por él: confía en ella solo si sabes por qué ha cambiado.'**
  String hostKeyOtherTypeBody(String where, String known, String offered);

  /// No description provided for @hostKeyOtherTypeTitle.
  ///
  /// In es, this message translates to:
  /// **'Otra clave para {label}'**
  String hostKeyOtherTypeTitle(String label);

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

  /// No description provided for @hosts.
  ///
  /// In es, this message translates to:
  /// **'Hosts'**
  String get hosts;

  /// No description provided for @hostsAll.
  ///
  /// In es, this message translates to:
  /// **'Todos'**
  String get hostsAll;

  /// No description provided for @hostsClearFilters.
  ///
  /// In es, this message translates to:
  /// **'Quitar los filtros'**
  String get hostsClearFilters;

  /// No description provided for @hostsColAddress.
  ///
  /// In es, this message translates to:
  /// **'Dirección'**
  String get hostsColAddress;

  /// No description provided for @hostsColEnvironment.
  ///
  /// In es, this message translates to:
  /// **'Entorno'**
  String get hostsColEnvironment;

  /// No description provided for @hostsColLast.
  ///
  /// In es, this message translates to:
  /// **'Última conexión'**
  String get hostsColLast;

  /// No description provided for @hostsColName.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get hostsColName;

  /// No description provided for @hostsColSystem.
  ///
  /// In es, this message translates to:
  /// **'Sistema'**
  String get hostsColSystem;

  /// No description provided for @hostsFilters.
  ///
  /// In es, this message translates to:
  /// **'Filtros'**
  String get hostsFilters;

  /// No description provided for @hostsHintConnect.
  ///
  /// In es, this message translates to:
  /// **'conectar'**
  String get hostsHintConnect;

  /// No description provided for @hostsHintDrag.
  ///
  /// In es, this message translates to:
  /// **'arrastra uno a la barra de pestañas para abrirlo ahí'**
  String get hostsHintDrag;

  /// No description provided for @hostsHintEdit.
  ///
  /// In es, this message translates to:
  /// **'editar'**
  String get hostsHintEdit;

  /// No description provided for @hostsHintFavorite.
  ///
  /// In es, this message translates to:
  /// **'favorito'**
  String get hostsHintFavorite;

  /// No description provided for @hostsNoGroup.
  ///
  /// In es, this message translates to:
  /// **'Sin grupo'**
  String get hostsNoGroup;

  /// No description provided for @hostsOpenNow.
  ///
  /// In es, this message translates to:
  /// **'abierto ahora'**
  String get hostsOpenNow;

  /// No description provided for @hostsSearchHint.
  ///
  /// In es, this message translates to:
  /// **'Busca por nombre, dirección, etiqueta o sistema'**
  String get hostsSearchHint;

  /// No description provided for @hostsSection.
  ///
  /// In es, this message translates to:
  /// **'Hosts'**
  String get hostsSection;

  /// No description provided for @hostsSummary.
  ///
  /// In es, this message translates to:
  /// **'{hosts} · {groups, plural, =0{sin grupos} =1{1 grupo} other{{groups} grupos}}'**
  String hostsSummary(int hosts, int groups);

  /// No description provided for @hostsViewCards.
  ///
  /// In es, this message translates to:
  /// **'Tarjetas'**
  String get hostsViewCards;

  /// No description provided for @hostsViewList.
  ///
  /// In es, this message translates to:
  /// **'Lista'**
  String get hostsViewList;

  /// No description provided for @howCsv.
  ///
  /// In es, this message translates to:
  /// **'Un host por fila, con cabecera: la plantilla de Termius o columnas como nombre, host, puerto, usuario y grupo.'**
  String get howCsv;

  /// No description provided for @howMobaXterm.
  ///
  /// In es, this message translates to:
  /// **'Sessions › Export all sessions to file: un archivo .mxtsessions'**
  String get howMobaXterm;

  /// No description provided for @howPutty.
  ///
  /// In es, this message translates to:
  /// **'Un .reg exportado del registro (reg export HKCU\\Software\\SimonTatham\\PuTTY\\Sessions putty.reg)'**
  String get howPutty;

  /// No description provided for @howSecureCrt.
  ///
  /// In es, this message translates to:
  /// **'Tools › Export Settings…: un archivo .xml'**
  String get howSecureCrt;

  /// No description provided for @howTabby.
  ///
  /// In es, this message translates to:
  /// **'Su config.yaml, si no está en este equipo'**
  String get howTabby;

  /// No description provided for @identities.
  ///
  /// In es, this message translates to:
  /// **'Identidades'**
  String get identities;

  /// No description provided for @identitiesCount.
  ///
  /// In es, this message translates to:
  /// **'{total, plural, =1{1 identidad} other{{total} identidades}} · {used} en uso'**
  String identitiesCount(int total, int used);

  /// No description provided for @identitiesIntro.
  ///
  /// In es, this message translates to:
  /// **'Usuario, claves y agente con un nombre, para usarlos en varios hosts y grupos. Cambiar una identidad cambia todos los que la usan.'**
  String get identitiesIntro;

  /// No description provided for @identitiesNoSecrets.
  ///
  /// In es, this message translates to:
  /// **'No se guardan contraseñas ni frases de paso: se piden al conectar, como hasta ahora. De cada clave solo se lee su parte pública (.pub).'**
  String get identitiesNoSecrets;

  /// No description provided for @identity.
  ///
  /// In es, this message translates to:
  /// **'Identidad'**
  String get identity;

  /// No description provided for @identityEditorHint.
  ///
  /// In es, this message translates to:
  /// **'Usuario, claves y agente con un nombre, para usarlos en varios hosts.'**
  String get identityEditorHint;

  /// No description provided for @identityKeyMissingHere.
  ///
  /// In es, this message translates to:
  /// **'{user} · falta su clave en este equipo'**
  String identityKeyMissingHere(String user);

  /// No description provided for @identityNeedsName.
  ///
  /// In es, this message translates to:
  /// **'Ponle un nombre.'**
  String get identityNeedsName;

  /// No description provided for @identityNewNote.
  ///
  /// In es, this message translates to:
  /// **'Úsala desde el editor de un host o de un grupo, o con «Usar en…» en la lista de identidades.'**
  String get identityNewNote;

  /// No description provided for @identityNone.
  ///
  /// In es, this message translates to:
  /// **'Ninguna'**
  String get identityNone;

  /// No description provided for @identityNoneNote.
  ///
  /// In es, this message translates to:
  /// **'Aunque se herede una de más arriba'**
  String get identityNoneNote;

  /// No description provided for @identitySaveChanges.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Al guardar cambia el host que la usa.} other{Al guardar cambian los {count} hosts que la usan.}} Un host que pone su propio usuario o sus claves mantiene los suyos.'**
  String identitySaveChanges(int count);

  /// No description provided for @identityUsedBy.
  ///
  /// In es, this message translates to:
  /// **'La usan: {who}'**
  String identityUsedBy(String who);

  /// No description provided for @ignore.
  ///
  /// In es, this message translates to:
  /// **'Ignorar'**
  String get ignore;

  /// No description provided for @importAction.
  ///
  /// In es, this message translates to:
  /// **'Importar'**
  String get importAction;

  /// No description provided for @importAnything.
  ///
  /// In es, this message translates to:
  /// **'Importar de otro programa o de ~/.ssh/config'**
  String get importAnything;

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

  /// No description provided for @importFromSshConfig.
  ///
  /// In es, this message translates to:
  /// **'Importar de ~/.ssh/config'**
  String get importFromSshConfig;

  /// No description provided for @importHostsTitle.
  ///
  /// In es, this message translates to:
  /// **'Importar hosts'**
  String get importHostsTitle;

  /// No description provided for @importIntoGroup.
  ///
  /// In es, this message translates to:
  /// **'Se guardan en el grupo «~/.ssh/config». Un host trae consigo los hosts por los que salta.'**
  String get importIntoGroup;

  /// No description provided for @importIntro.
  ///
  /// In es, this message translates to:
  /// **'Trae tus hosts de otro programa. Solo se leen: el original no cambia.'**
  String get importIntro;

  /// No description provided for @importKeepsFile.
  ///
  /// In es, this message translates to:
  /// **'El fichero no se toca, y las claves se quedan donde están: OpenWard guarda la ruta, nunca la clave.'**
  String get importKeepsFile;

  /// No description provided for @importKey.
  ///
  /// In es, this message translates to:
  /// **'Importar una clave'**
  String get importKey;

  /// No description provided for @importKeyAction.
  ///
  /// In es, this message translates to:
  /// **'Importar…'**
  String get importKeyAction;

  /// No description provided for @importKeyIntro.
  ///
  /// In es, this message translates to:
  /// **'Pega una clave privada o elige su archivo. Se guarda como un archivo nuevo en ~/.ssh; el original no cambia.'**
  String get importKeyIntro;

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

  /// No description provided for @importReportCopied.
  ///
  /// In es, this message translates to:
  /// **'Informe copiado'**
  String get importReportCopied;

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

  /// No description provided for @inWhere.
  ///
  /// In es, this message translates to:
  /// **'en {where}'**
  String inWhere(String where);

  /// No description provided for @inheritAgain.
  ///
  /// In es, this message translates to:
  /// **'Volver a heredar'**
  String get inheritAgain;

  /// No description provided for @inheritsFrom.
  ///
  /// In es, this message translates to:
  /// **'La hereda de {group}'**
  String inheritsFrom(String group);

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

  /// No description provided for @installKeyAction.
  ///
  /// In es, this message translates to:
  /// **'Subir a un servidor…'**
  String get installKeyAction;

  /// No description provided for @installKeyAdded.
  ///
  /// In es, this message translates to:
  /// **'Clave añadida en {host}'**
  String installKeyAdded(String host);

  /// No description provided for @installKeyFailed.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido subir a {host}'**
  String installKeyFailed(String host);

  /// No description provided for @installKeyIntro.
  ///
  /// In es, this message translates to:
  /// **'Su parte pública se añade al ~/.ssh/authorized_keys del servidor, como hace ssh-copy-id. Entras una vez con lo que uses ahora.'**
  String get installKeyIntro;

  /// No description provided for @installKeyNext.
  ///
  /// In es, this message translates to:
  /// **'Para entrar con ella, elígela en el host o en su identidad.'**
  String get installKeyNext;

  /// No description provided for @installKeyNoHosts.
  ///
  /// In es, this message translates to:
  /// **'Ningún host coincide. Escribe una dirección para usarla sin guardarla.'**
  String get installKeyNoHosts;

  /// No description provided for @installKeySearch.
  ///
  /// In es, this message translates to:
  /// **'Busca un host o escribe usuario@dirección'**
  String get installKeySearch;

  /// No description provided for @installKeyTitle.
  ///
  /// In es, this message translates to:
  /// **'Subir {name} a un servidor'**
  String installKeyTitle(String name);

  /// No description provided for @installKeyToAddress.
  ///
  /// In es, this message translates to:
  /// **'Subir a {address}'**
  String installKeyToAddress(String address);

  /// No description provided for @installKeyWasThere.
  ///
  /// In es, this message translates to:
  /// **'{host} ya tenía esta clave'**
  String installKeyWasThere(String host);

  /// No description provided for @installKeyWriteFailed.
  ///
  /// In es, this message translates to:
  /// **'El servidor no dejó escribir ~/.ssh/authorized_keys: {error}'**
  String installKeyWriteFailed(String error);

  /// No description provided for @installingKey.
  ///
  /// In es, this message translates to:
  /// **'Añadiendo la clave en {host}…'**
  String installingKey(String host);

  /// No description provided for @itemCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 elemento} other{{count} elementos}}'**
  String itemCount(int count);

  /// No description provided for @itsPort.
  ///
  /// In es, this message translates to:
  /// **'Su puerto'**
  String get itsPort;

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

  /// No description provided for @keepaliveEvery.
  ///
  /// In es, this message translates to:
  /// **'Cada {every} s · perdida a los {lost} s'**
  String keepaliveEvery(int every, int lost);

  /// No description provided for @keepaliveLabel.
  ///
  /// In es, this message translates to:
  /// **'Comprobar la conexión'**
  String get keepaliveLabel;

  /// No description provided for @keepaliveOff.
  ///
  /// In es, this message translates to:
  /// **'Nunca'**
  String get keepaliveOff;

  /// No description provided for @keyAdded.
  ///
  /// In es, this message translates to:
  /// **'Guardada en {path}.'**
  String keyAdded(String path);

  /// No description provided for @keyBackspace.
  ///
  /// In es, this message translates to:
  /// **'Retroceso'**
  String get keyBackspace;

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

  /// No description provided for @keyColumn.
  ///
  /// In es, this message translates to:
  /// **'Clave'**
  String get keyColumn;

  /// No description provided for @keyCommentLabel.
  ///
  /// In es, this message translates to:
  /// **'Comentario'**
  String get keyCommentLabel;

  /// No description provided for @keyDelete.
  ///
  /// In es, this message translates to:
  /// **'Supr'**
  String get keyDelete;

  /// No description provided for @keyDeleted.
  ///
  /// In es, this message translates to:
  /// **'{name} eliminada.'**
  String keyDeleted(String name);

  /// No description provided for @keyExchange.
  ///
  /// In es, this message translates to:
  /// **'Intercambio'**
  String get keyExchange;

  /// No description provided for @keyExported.
  ///
  /// In es, this message translates to:
  /// **'{name} copiada a {path}.'**
  String keyExported(String name, String path);

  /// No description provided for @keyFailed.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido (más en «Detalles»).'**
  String get keyFailed;

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

  /// No description provided for @keyMissing.
  ///
  /// In es, this message translates to:
  /// **'No está en este equipo'**
  String get keyMissing;

  /// No description provided for @keyMissingWarning.
  ///
  /// In es, this message translates to:
  /// **'{path} no está en este equipo. {count, plural, =0{Cópiala o cambia la ruta antes de usarla.} =1{El host que la usa no podrá usar esa clave hasta que la copies o cambies la ruta.} other{Los {count} hosts que la usan no podrán usar esa clave hasta que la copies o cambies la ruta.}}'**
  String keyMissingWarning(String path, int count);

  /// No description provided for @keyNameInvalid.
  ///
  /// In es, this message translates to:
  /// **'Ese nombre no vale para un archivo de clave: usa letras, números, «-», «_», «.» o «@».'**
  String get keyNameInvalid;

  /// No description provided for @keyNameTaken.
  ///
  /// In es, this message translates to:
  /// **'Ya hay un archivo {name} en ~/.ssh. Elige otro nombre.'**
  String keyNameTaken(String name);

  /// No description provided for @keyNoPublicHalf.
  ///
  /// In es, this message translates to:
  /// **'Sin .pub al lado: su tipo se sabrá al conectar'**
  String get keyNoPublicHalf;

  /// No description provided for @keyNotOpenSsh.
  ///
  /// In es, this message translates to:
  /// **'Esta clave no es de OpenSSH: su frase de paso se cambia con el programa que la hizo.'**
  String get keyNotOpenSsh;

  /// No description provided for @keyNotReadable.
  ///
  /// In es, this message translates to:
  /// **'Eso no es una clave privada que OpenWard pueda leer (OpenSSH, PEM o PuTTY).'**
  String get keyNotReadable;

  /// No description provided for @keyNow.
  ///
  /// In es, this message translates to:
  /// **'Ahora ({algorithm})'**
  String keyNow(String algorithm);

  /// No description provided for @keyPassphraseChanged.
  ///
  /// In es, this message translates to:
  /// **'La frase de paso de {name} ha cambiado.'**
  String keyPassphraseChanged(String name);

  /// No description provided for @keyPassphraseEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Cambiar la frase de paso…'**
  String get keyPassphraseEllipsis;

  /// No description provided for @keyPassphraseEmpty.
  ///
  /// In es, this message translates to:
  /// **'Vacía, la clave queda sin frase de paso: quien tenga el archivo podrá usarla.'**
  String get keyPassphraseEmpty;

  /// No description provided for @keyPassphraseTitle.
  ///
  /// In es, this message translates to:
  /// **'Frase de paso de {name}'**
  String keyPassphraseTitle(String name);

  /// No description provided for @keyPerHost.
  ///
  /// In es, this message translates to:
  /// **'Una por host (lleva %h, %r…)'**
  String get keyPerHost;

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

  /// No description provided for @keyRenameNote.
  ///
  /// In es, this message translates to:
  /// **'Su .pub y su certificado van con ella, y los hosts, grupos e identidades que la usan pasan a nombrarla así.'**
  String get keyRenameNote;

  /// No description provided for @keyRenameTitle.
  ///
  /// In es, this message translates to:
  /// **'Renombrar {name}'**
  String keyRenameTitle(String name);

  /// No description provided for @keySaved.
  ///
  /// In es, this message translates to:
  /// **'Guardada'**
  String get keySaved;

  /// No description provided for @keyType.
  ///
  /// In es, this message translates to:
  /// **'Tipo'**
  String get keyType;

  /// No description provided for @keyTypeEcdsa.
  ///
  /// In es, this message translates to:
  /// **'Para servidores o normas que piden curvas NIST.'**
  String get keyTypeEcdsa;

  /// No description provided for @keyTypeEd25519.
  ///
  /// In es, this message translates to:
  /// **'La recomendada: corta, rápida, y la aceptan los servidores de los últimos diez años.'**
  String get keyTypeEd25519;

  /// No description provided for @keyTypeRsa.
  ///
  /// In es, this message translates to:
  /// **'Para servidores antiguos que no aceptan nada más nuevo. Tarda unos segundos en crearse.'**
  String get keyTypeRsa;

  /// No description provided for @keyTypeSecurityEcdsa.
  ///
  /// In es, this message translates to:
  /// **'ECDSA P-256 en la llave: la tienen todas las llaves FIDO2.'**
  String get keyTypeSecurityEcdsa;

  /// No description provided for @keyTypeSecurityEd25519.
  ///
  /// In es, this message translates to:
  /// **'Ed25519 en la llave: la mejor opción si tu llave la tiene (casi todas desde 2020).'**
  String get keyTypeSecurityEd25519;

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

  /// No description provided for @keysInOrder.
  ///
  /// In es, this message translates to:
  /// **'Se prueban en este orden; arrastra para cambiarlo.'**
  String get keysInOrder;

  /// No description provided for @keysIntro.
  ///
  /// In es, this message translates to:
  /// **'Las claves privadas de ~/.ssh. Se quedan ahí: el vault solo guarda qué clave usa cada host. Aquí puedes crear claves, traer las que tengas y subir la parte pública a un servidor.'**
  String get keysIntro;

  /// No description provided for @kindDynamic.
  ///
  /// In es, this message translates to:
  /// **'Dinámico (-D)'**
  String get kindDynamic;

  /// No description provided for @kindDynamicShort.
  ///
  /// In es, this message translates to:
  /// **'Dinámico'**
  String get kindDynamicShort;

  /// No description provided for @kindLocal.
  ///
  /// In es, this message translates to:
  /// **'Local (-L)'**
  String get kindLocal;

  /// No description provided for @kindLocalShort.
  ///
  /// In es, this message translates to:
  /// **'Local'**
  String get kindLocalShort;

  /// No description provided for @kindRemote.
  ///
  /// In es, this message translates to:
  /// **'Remoto (-R)'**
  String get kindRemote;

  /// No description provided for @kindRemoteShort.
  ///
  /// In es, this message translates to:
  /// **'Remoto'**
  String get kindRemoteShort;

  /// No description provided for @knownHosts.
  ///
  /// In es, this message translates to:
  /// **'Hosts conocidos'**
  String get knownHosts;

  /// No description provided for @knownHostsFileChanged.
  ///
  /// In es, this message translates to:
  /// **'El fichero ha cambiado desde que se mostró. Vuelve a mirarlo antes de quitar nada.'**
  String get knownHostsFileChanged;

  /// No description provided for @knownHostsIntro.
  ///
  /// In es, this message translates to:
  /// **'Las claves de servidor en las que confías. Al conectar se miran las de OpenWard y las de {file}; las nuevas se guardan en OpenWard.'**
  String knownHostsIntro(String file);

  /// No description provided for @lanLocalNote.
  ///
  /// In es, this message translates to:
  /// **'Cualquiera de tu red podrá usarlo mientras esté abierto.'**
  String get lanLocalNote;

  /// No description provided for @lanRemoteNote.
  ///
  /// In es, this message translates to:
  /// **'El servidor tiene que permitirlo (GatewayPorts en sshd); si no, escucha solo en sí mismo.'**
  String get lanRemoteNote;

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

  /// No description provided for @latencyChecks.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{la última comprobación} other{las últimas {count} comprobaciones}}'**
  String latencyChecks(int count);

  /// No description provided for @latencyClick.
  ///
  /// In es, this message translates to:
  /// **'Un clic abre los detalles de la conexión y su huella.'**
  String get latencyClick;

  /// No description provided for @latencyHigh.
  ///
  /// In es, this message translates to:
  /// **'{ms} ms: {times} veces lo habitual'**
  String latencyHigh(int ms, int times);

  /// No description provided for @latencyHighLabel.
  ///
  /// In es, this message translates to:
  /// **'Latencia alta: {ms} ms'**
  String latencyHighLabel(int ms);

  /// No description provided for @latencyLabel.
  ///
  /// In es, this message translates to:
  /// **'Latencia: {ms} ms'**
  String latencyLabel(int ms);

  /// No description provided for @latencyUsual.
  ///
  /// In es, this message translates to:
  /// **'habitual {ms} ms'**
  String latencyUsual(int ms);

  /// No description provided for @latencyWith.
  ///
  /// In es, this message translates to:
  /// **'Latencia con {host}'**
  String latencyWith(String host);

  /// No description provided for @legacyHostKeys.
  ///
  /// In es, this message translates to:
  /// **'Claves antiguas (ssh-rsa)'**
  String get legacyHostKeys;

  /// No description provided for @legacyHostKeysNote.
  ///
  /// In es, this message translates to:
  /// **'Solo para servidores anteriores a OpenSSH 7.2, que firman su clave con SHA-1. OpenSSH dejó de aceptarlo en la 8.8.'**
  String get legacyHostKeysNote;

  /// No description provided for @legacyHostKeysOff.
  ///
  /// In es, this message translates to:
  /// **'No'**
  String get legacyHostKeysOff;

  /// No description provided for @legacyHostKeysOn.
  ///
  /// In es, this message translates to:
  /// **'Aceptar ssh-rsa con SHA-1'**
  String get legacyHostKeysOn;

  /// No description provided for @legendInheritAgain.
  ///
  /// In es, this message translates to:
  /// **'vuelve a heredar'**
  String get legendInheritAgain;

  /// No description provided for @legendInherited.
  ///
  /// In es, this message translates to:
  /// **'heredado'**
  String get legendInherited;

  /// No description provided for @legendSetHere.
  ///
  /// In es, this message translates to:
  /// **'cambiado aquí'**
  String get legendSetHere;

  /// No description provided for @library.
  ///
  /// In es, this message translates to:
  /// **'Biblioteca'**
  String get library;

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

  /// No description provided for @lineNumber.
  ///
  /// In es, this message translates to:
  /// **'línea {line}'**
  String lineNumber(int line);

  /// No description provided for @linesCount.
  ///
  /// In es, this message translates to:
  /// **'{count} líneas'**
  String linesCount(int count);

  /// No description provided for @linkLeadsElsewhere.
  ///
  /// In es, this message translates to:
  /// **'Cuidado: el texto dice otra cosa, pero lleva a {url}'**
  String linkLeadsElsewhere(String url);

  /// No description provided for @linkNotOpened.
  ///
  /// In es, this message translates to:
  /// **'Los enlaces «{scheme}:» no se abren desde el terminal.'**
  String linkNotOpened(String scheme);

  /// No description provided for @localSentence.
  ///
  /// In es, this message translates to:
  /// **'Lo que conecte a {here} llega a {dest} como si saliera de {host}.'**
  String localSentence(String here, String dest, String host);

  /// No description provided for @localShell.
  ///
  /// In es, this message translates to:
  /// **'Local'**
  String get localShell;

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

  /// No description provided for @logCommands.
  ///
  /// In es, this message translates to:
  /// **'Comandos'**
  String get logCommands;

  /// No description provided for @logCopied.
  ///
  /// In es, this message translates to:
  /// **'Copiado.'**
  String get logCopied;

  /// No description provided for @logCopyCommand.
  ///
  /// In es, this message translates to:
  /// **'Copiar el comando elegido y su salida'**
  String get logCopyCommand;

  /// No description provided for @logCopyText.
  ///
  /// In es, this message translates to:
  /// **'Copiar como texto'**
  String get logCopyText;

  /// No description provided for @logDelete.
  ///
  /// In es, this message translates to:
  /// **'Borrar el registro…'**
  String get logDelete;

  /// No description provided for @logDeleteBody.
  ///
  /// In es, this message translates to:
  /// **'Se borra lo que se vio en esta sesión y su entrada. No se puede deshacer.'**
  String get logDeleteBody;

  /// No description provided for @logDeleteTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Borrar este registro?'**
  String get logDeleteTitle;

  /// No description provided for @logEditNote.
  ///
  /// In es, this message translates to:
  /// **'Editar la nota'**
  String get logEditNote;

  /// No description provided for @logEndedTooltip.
  ///
  /// In es, this message translates to:
  /// **'El registro de esta conexión'**
  String get logEndedTooltip;

  /// No description provided for @logExportCast.
  ///
  /// In es, this message translates to:
  /// **'Asciicast (.cast)'**
  String get logExportCast;

  /// No description provided for @logExportCastHelp.
  ///
  /// In es, this message translates to:
  /// **'Con tiempos y colores; se reproduce con asciinema.'**
  String get logExportCastHelp;

  /// No description provided for @logExportText.
  ///
  /// In es, this message translates to:
  /// **'Texto (.txt)'**
  String get logExportText;

  /// No description provided for @logExportTextHelp.
  ///
  /// In es, this message translates to:
  /// **'Lo que se vio, sin colores ni tiempos.'**
  String get logExportTextHelp;

  /// No description provided for @logExported.
  ///
  /// In es, this message translates to:
  /// **'Guardado en {path}.'**
  String logExported(String path);

  /// No description provided for @logFailed.
  ///
  /// In es, this message translates to:
  /// **'El registro se detuvo: {reason}'**
  String logFailed(String reason);

  /// No description provided for @logIncomplete.
  ///
  /// In es, this message translates to:
  /// **'Se corta antes del final: OpenWard se cerró de golpe.'**
  String get logIncomplete;

  /// No description provided for @logMarkBack.
  ///
  /// In es, this message translates to:
  /// **'Volvió la conexión'**
  String get logMarkBack;

  /// No description provided for @logMarkFull.
  ///
  /// In es, this message translates to:
  /// **'Registro lleno'**
  String get logMarkFull;

  /// No description provided for @logMarkLost.
  ///
  /// In es, this message translates to:
  /// **'Se cortó la conexión'**
  String get logMarkLost;

  /// No description provided for @logMarkOmitted.
  ///
  /// In es, this message translates to:
  /// **'Salida omitida'**
  String get logMarkOmitted;

  /// No description provided for @logMarkPause.
  ///
  /// In es, this message translates to:
  /// **'En pausa'**
  String get logMarkPause;

  /// No description provided for @logMenuEnded.
  ///
  /// In es, this message translates to:
  /// **'El registro de esta conexión'**
  String get logMenuEnded;

  /// No description provided for @logMenuNeverTyped.
  ///
  /// In es, this message translates to:
  /// **'nunca lo que escribes'**
  String get logMenuNeverTyped;

  /// No description provided for @logMenuPaused.
  ///
  /// In es, this message translates to:
  /// **'En pausa'**
  String get logMenuPaused;

  /// No description provided for @logMenuPausedSub.
  ///
  /// In es, this message translates to:
  /// **'Lo que sale ahora no se guarda'**
  String get logMenuPausedSub;

  /// No description provided for @logMenuSince.
  ///
  /// In es, this message translates to:
  /// **'Desde las {time}'**
  String logMenuSince(String time);

  /// No description provided for @logMenuTitle.
  ///
  /// In es, this message translates to:
  /// **'Se guarda lo que sale en pantalla'**
  String get logMenuTitle;

  /// No description provided for @logMoreActions.
  ///
  /// In es, this message translates to:
  /// **'Más acciones'**
  String get logMoreActions;

  /// No description provided for @logNeverExpires.
  ///
  /// In es, this message translates to:
  /// **'No caduca'**
  String get logNeverExpires;

  /// No description provided for @logNoteHelp.
  ///
  /// In es, this message translates to:
  /// **'No caduca: se guarda hasta que lo quites.'**
  String get logNoteHelp;

  /// No description provided for @logNoteHint.
  ///
  /// In es, this message translates to:
  /// **'Por qué lo guardas (opcional)'**
  String get logNoteHint;

  /// No description provided for @logNoteTitle.
  ///
  /// In es, this message translates to:
  /// **'Guardar este registro'**
  String get logNoteTitle;

  /// No description provided for @logOpenThis.
  ///
  /// In es, this message translates to:
  /// **'Abrir el registro de esta sesión'**
  String get logOpenThis;

  /// No description provided for @logPause.
  ///
  /// In es, this message translates to:
  /// **'Pausar el registro'**
  String get logPause;

  /// No description provided for @logPauseHelp.
  ///
  /// In es, this message translates to:
  /// **'Lo que salga mientras, no se guarda'**
  String get logPauseHelp;

  /// No description provided for @logPausePlayback.
  ///
  /// In es, this message translates to:
  /// **'Pausar'**
  String get logPausePlayback;

  /// No description provided for @logPausedFor.
  ///
  /// In es, this message translates to:
  /// **'En pausa · {duration}'**
  String logPausedFor(String duration);

  /// No description provided for @logPausedTotal.
  ///
  /// In es, this message translates to:
  /// **'{duration} en pausa'**
  String logPausedTotal(String duration);

  /// No description provided for @logPlay.
  ///
  /// In es, this message translates to:
  /// **'Reproducir'**
  String get logPlay;

  /// No description provided for @logPosition.
  ///
  /// In es, this message translates to:
  /// **'Momento de la sesión'**
  String get logPosition;

  /// No description provided for @logReadOnly.
  ///
  /// In es, this message translates to:
  /// **'Solo lectura'**
  String get logReadOnly;

  /// No description provided for @logRecordingTooltip.
  ///
  /// In es, this message translates to:
  /// **'Se guarda lo que sale en pantalla'**
  String get logRecordingTooltip;

  /// No description provided for @logResume.
  ///
  /// In es, this message translates to:
  /// **'Seguir grabando'**
  String get logResume;

  /// No description provided for @logResumeHelp.
  ///
  /// In es, this message translates to:
  /// **'El registro guarda un hueco con lo que duró la pausa'**
  String get logResumeHelp;

  /// No description provided for @logSaved.
  ///
  /// In es, this message translates to:
  /// **'Guardado'**
  String get logSaved;

  /// No description provided for @logSeeIt.
  ///
  /// In es, this message translates to:
  /// **'Ver el registro'**
  String get logSeeIt;

  /// No description provided for @logSpeed.
  ///
  /// In es, this message translates to:
  /// **'Velocidad: {speed}'**
  String logSpeed(String speed);

  /// No description provided for @logStillRecording.
  ///
  /// In es, this message translates to:
  /// **'Sigue grabando: lo de los últimos segundos aún no está aquí.'**
  String get logStillRecording;

  /// No description provided for @logStopEverywhere.
  ///
  /// In es, this message translates to:
  /// **'Activado en todos los hosts; se cambia en Ajustes'**
  String get logStopEverywhere;

  /// No description provided for @logStopFromGroup.
  ///
  /// In es, this message translates to:
  /// **'Lo hereda de {group}; se cambia en su editor'**
  String logStopFromGroup(String group);

  /// No description provided for @logStopHost.
  ///
  /// In es, this message translates to:
  /// **'No guardar registros de {host}…'**
  String logStopHost(String host);

  /// No description provided for @logStopOwn.
  ///
  /// In es, this message translates to:
  /// **'Activado en este host; se cambia en su editor'**
  String get logStopOwn;

  /// No description provided for @logTab.
  ///
  /// In es, this message translates to:
  /// **'Registro'**
  String get logTab;

  /// No description provided for @logTabTitle.
  ///
  /// In es, this message translates to:
  /// **'{label} · {when}'**
  String logTabTitle(String label, String when);

  /// No description provided for @logUnsave.
  ///
  /// In es, this message translates to:
  /// **'Dejar de guardar'**
  String get logUnsave;

  /// No description provided for @logViewerEmpty.
  ///
  /// In es, this message translates to:
  /// **'Abre un registro desde la página Registros.'**
  String get logViewerEmpty;

  /// No description provided for @logs.
  ///
  /// In es, this message translates to:
  /// **'Registros'**
  String get logs;

  /// No description provided for @logsAll.
  ///
  /// In es, this message translates to:
  /// **'Todas'**
  String get logsAll;

  /// No description provided for @logsAlsoHere.
  ///
  /// In es, this message translates to:
  /// **'También en este equipo'**
  String get logsAlsoHere;

  /// No description provided for @logsAppQuit.
  ///
  /// In es, this message translates to:
  /// **'Se cerró la app'**
  String get logsAppQuit;

  /// No description provided for @logsAppQuitAt.
  ///
  /// In es, this message translates to:
  /// **'OpenWard se cerró a las {time} sin acabar la sesión. Esto es lo último que se guardó.'**
  String logsAppQuitAt(String time);

  /// No description provided for @logsCommands.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 comando} other{{count} comandos}}'**
  String logsCommands(int count);

  /// No description provided for @logsConnectAgain.
  ///
  /// In es, this message translates to:
  /// **'Conectar otra vez'**
  String get logsConnectAgain;

  /// No description provided for @logsCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 registro} other{{count} registros}}'**
  String logsCount(int count);

  /// No description provided for @logsCut.
  ///
  /// In es, this message translates to:
  /// **'Se cortó'**
  String get logsCut;

  /// No description provided for @logsCutAt.
  ///
  /// In es, this message translates to:
  /// **'La conexión se cortó a las {time}. Esto es lo último que se vio.'**
  String logsCutAt(String time);

  /// No description provided for @logsDeleteAll.
  ///
  /// In es, this message translates to:
  /// **'Borrar todos los registros'**
  String get logsDeleteAll;

  /// No description provided for @logsDeleteAllAction.
  ///
  /// In es, this message translates to:
  /// **'Borrar todos'**
  String get logsDeleteAllAction;

  /// No description provided for @logsDeleteAllEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Borrar todos…'**
  String get logsDeleteAllEllipsis;

  /// No description provided for @logsDeleteAllHelp.
  ///
  /// In es, this message translates to:
  /// **'{count} y {size}, también los guardados. No se puede deshacer.'**
  String logsDeleteAllHelp(String count, String size);

  /// No description provided for @logsDeleteAllTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Borrar todos los registros?'**
  String get logsDeleteAllTitle;

  /// No description provided for @logsEmptyBody.
  ///
  /// In es, this message translates to:
  /// **'Cada conexión deja aquí cuándo fue y cuánto duró. Para guardar también lo que se vio, activa el registro de sesión en un host, en un grupo o en Ajustes.'**
  String get logsEmptyBody;

  /// No description provided for @logsEmptyTitle.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay sesiones'**
  String get logsEmptyTitle;

  /// No description provided for @logsEverywhere.
  ///
  /// In es, this message translates to:
  /// **'Guardar el registro en todos los hosts'**
  String get logsEverywhere;

  /// No description provided for @logsEverywhereHelp.
  ///
  /// In es, this message translates to:
  /// **'Lo que sale en pantalla, con sus tiempos, para volver a verlo, buscar en él y exportarlo. Nunca lo que escribes: una contraseña que no se ve no queda; un cat .env, sí. Solo en este equipo.'**
  String get logsEverywhereHelp;

  /// No description provided for @logsExceptIn.
  ///
  /// In es, this message translates to:
  /// **'Desactivado en:'**
  String get logsExceptIn;

  /// No description provided for @logsFolder.
  ///
  /// In es, this message translates to:
  /// **'Carpeta'**
  String get logsFolder;

  /// No description provided for @logsGroup.
  ///
  /// In es, this message translates to:
  /// **'grupo'**
  String get logsGroup;

  /// No description provided for @logsHitAt.
  ///
  /// In es, this message translates to:
  /// **'A los {time} de la sesión'**
  String logsHitAt(String time);

  /// No description provided for @logsHits.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 coincidencia} other{{count} coincidencias}}'**
  String logsHits(int count);

  /// No description provided for @logsHitsIn.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{en 1 registro} other{en {count} registros}}'**
  String logsHitsIn(int count);

  /// No description provided for @logsHost.
  ///
  /// In es, this message translates to:
  /// **'host'**
  String get logsHost;

  /// No description provided for @logsKeep.
  ///
  /// In es, this message translates to:
  /// **'Borrar los registros pasados'**
  String get logsKeep;

  /// No description provided for @logsKeepAlways.
  ///
  /// In es, this message translates to:
  /// **'Nunca'**
  String get logsKeepAlways;

  /// No description provided for @logsKeepDays.
  ///
  /// In es, this message translates to:
  /// **'{days, plural, =1{Al día} other{A los {days} días}}'**
  String logsKeepDays(int days);

  /// No description provided for @logsKeepHelp.
  ///
  /// In es, this message translates to:
  /// **'Los guardados no caducan nunca.'**
  String get logsKeepHelp;

  /// No description provided for @logsLastCommands.
  ///
  /// In es, this message translates to:
  /// **'Últimos comandos'**
  String get logsLastCommands;

  /// No description provided for @logsLive.
  ///
  /// In es, this message translates to:
  /// **'Grabando'**
  String get logsLive;

  /// No description provided for @logsLocal.
  ///
  /// In es, this message translates to:
  /// **'Locales'**
  String get logsLocal;

  /// No description provided for @logsLocalHelp.
  ///
  /// In es, this message translates to:
  /// **'Tu propio equipo. Por defecto no.'**
  String get logsLocalHelp;

  /// No description provided for @logsLocalTerminals.
  ///
  /// In es, this message translates to:
  /// **'También los terminales locales'**
  String get logsLocalTerminals;

  /// No description provided for @logsMoreHits.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{y 1 más} other{y {count} más}}'**
  String logsMoreHits(int count);

  /// No description provided for @logsNoLimit.
  ///
  /// In es, this message translates to:
  /// **'Sin límite'**
  String get logsNoLimit;

  /// No description provided for @logsNoRecording.
  ///
  /// In es, this message translates to:
  /// **'Esta sesión no tiene registro: solo cuándo y cuánto duró.'**
  String get logsNoRecording;

  /// No description provided for @logsNoneOff.
  ///
  /// In es, this message translates to:
  /// **'Ningún host ni grupo lo desactiva.'**
  String get logsNoneOff;

  /// No description provided for @logsNoneOn.
  ///
  /// In es, this message translates to:
  /// **'Ningún host ni grupo lo activa por su cuenta.'**
  String get logsNoneOn;

  /// No description provided for @logsNotRecorded.
  ///
  /// In es, this message translates to:
  /// **'Sin registro'**
  String get logsNotRecorded;

  /// No description provided for @logsNothing.
  ///
  /// In es, this message translates to:
  /// **'Ninguna sesión con estos filtros.'**
  String get logsNothing;

  /// No description provided for @logsNow.
  ///
  /// In es, this message translates to:
  /// **'ahora'**
  String get logsNow;

  /// No description provided for @logsOnlyIn.
  ///
  /// In es, this message translates to:
  /// **'Activado solo en:'**
  String get logsOnlyIn;

  /// No description provided for @logsOpen.
  ///
  /// In es, this message translates to:
  /// **'Abrir el registro'**
  String get logsOpen;

  /// No description provided for @logsOpenEntry.
  ///
  /// In es, this message translates to:
  /// **'Abierta'**
  String get logsOpenEntry;

  /// No description provided for @logsOpenHere.
  ///
  /// In es, this message translates to:
  /// **'Abrir aquí'**
  String get logsOpenHere;

  /// No description provided for @logsPick.
  ///
  /// In es, this message translates to:
  /// **'Elige una sesión para ver lo último que se vio.'**
  String get logsPick;

  /// No description provided for @logsRecorded.
  ///
  /// In es, this message translates to:
  /// **'Con registro'**
  String get logsRecorded;

  /// No description provided for @logsSaved.
  ///
  /// In es, this message translates to:
  /// **'Guardadas'**
  String get logsSaved;

  /// No description provided for @logsSavedCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 guardado} other{{count} guardados}}'**
  String logsSavedCount(int count);

  /// No description provided for @logsSearchHint.
  ///
  /// In es, this message translates to:
  /// **'Busca en lo que se vio: comandos y salida'**
  String get logsSearchHint;

  /// No description provided for @logsSearchNone.
  ///
  /// In es, this message translates to:
  /// **'Nada en lo grabado.'**
  String get logsSearchNone;

  /// No description provided for @logsSearchNote.
  ///
  /// In es, this message translates to:
  /// **'Se busca en lo que quedó grabado. Las sesiones sin registro solo guardan cuándo y cuánto duraron.'**
  String get logsSearchNote;

  /// No description provided for @logsSearching.
  ///
  /// In es, this message translates to:
  /// **'Buscando…'**
  String get logsSearching;

  /// No description provided for @logsSessionTitle.
  ///
  /// In es, this message translates to:
  /// **'Registros de sesión'**
  String get logsSessionTitle;

  /// No description provided for @logsSettings.
  ///
  /// In es, this message translates to:
  /// **'Ajustes de registros'**
  String get logsSettings;

  /// No description provided for @logsSettingsEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Ajustes de registros…'**
  String get logsSettingsEllipsis;

  /// No description provided for @logsSpace.
  ///
  /// In es, this message translates to:
  /// **'Espacio máximo'**
  String get logsSpace;

  /// No description provided for @logsSpaceHelp.
  ///
  /// In es, this message translates to:
  /// **'Al llegar, se borran primero los más antiguos sin guardar.'**
  String get logsSpaceHelp;

  /// No description provided for @logsToday.
  ///
  /// In es, this message translates to:
  /// **'Hoy'**
  String get logsToday;

  /// No description provided for @logsUnencrypted.
  ///
  /// In es, this message translates to:
  /// **'De momento se guardan sin cifrar, en una carpeta que solo puede leer tu usuario, igual que el historial de comandos. Cuando el vault vaya cifrado, los registros irán cifrados con él y esta nota desaparecerá.'**
  String get logsUnencrypted;

  /// No description provided for @logsUsage.
  ///
  /// In es, this message translates to:
  /// **'{size} de {max} · se guardan {days} días'**
  String logsUsage(String size, String max, int days);

  /// No description provided for @logsWhereNote.
  ///
  /// In es, this message translates to:
  /// **'En el editor de cada host o grupo, «Registro de sesión» › Avanzado: se hereda como el resto, de los grupos al host.'**
  String get logsWhereNote;

  /// No description provided for @logsYesterday.
  ///
  /// In es, this message translates to:
  /// **'Ayer'**
  String get logsYesterday;

  /// No description provided for @lostInLog.
  ///
  /// In es, this message translates to:
  /// **'Lo que se vio hasta ahora está en su registro, aunque cierres esta pestaña.'**
  String get lostInLog;

  /// No description provided for @lostKeptInTmux.
  ///
  /// In es, this message translates to:
  /// **'Tu sesión sigue en tmux en {host}: al volver la encontrarás como estaba. Lo que escribas ahora no se envía.'**
  String lostKeptInTmux(String host);

  /// No description provided for @lostNewShell.
  ///
  /// In es, this message translates to:
  /// **'Lo que escribas ahora no se envía. Al volver se abre un terminal nuevo: lo que corría en {host} no sigue.'**
  String lostNewShell(String host);

  /// No description provided for @madeGroups.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 grupo, con sus ajustes} other{{count} grupos, con sus ajustes}}'**
  String madeGroups(int count);

  /// No description provided for @madeIdentities.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 identidad} other{{count} identidades}}'**
  String madeIdentities(int count);

  /// No description provided for @madeKey.
  ///
  /// In es, this message translates to:
  /// **'Clave guardada en {path}'**
  String madeKey(String path);

  /// No description provided for @madeKnownHosts.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 clave de host de confianza, en Biblioteca › Hosts conocidos} other{{count} claves de host de confianza, en Biblioteca › Hosts conocidos}}'**
  String madeKnownHosts(int count);

  /// No description provided for @madeSkipped.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 host ya estaba de antes y se ha dejado como estaba} other{{count} hosts ya estaban de antes y se han dejado como estaban}}'**
  String madeSkipped(int count);

  /// No description provided for @madeSnippets.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 snippet, en Biblioteca › Snippets} other{{count} snippets, en Biblioteca › Snippets}}'**
  String madeSnippets(int count);

  /// No description provided for @madeTunnels.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 túnel, en Biblioteca › Túneles} other{{count} túneles, en Biblioteca › Túneles}}'**
  String madeTunnels(int count);

  /// No description provided for @makeKey.
  ///
  /// In es, this message translates to:
  /// **'Crear la clave'**
  String get makeKey;

  /// No description provided for @makingKey.
  ///
  /// In es, this message translates to:
  /// **'Creando…'**
  String get makingKey;

  /// No description provided for @manageSnippets.
  ///
  /// In es, this message translates to:
  /// **'Gestionar snippets…'**
  String get manageSnippets;

  /// No description provided for @markerCertAuthority.
  ///
  /// In es, this message translates to:
  /// **'Autoridad de certificados: confía en los hosts que firma'**
  String get markerCertAuthority;

  /// No description provided for @markerRevoked.
  ///
  /// In es, this message translates to:
  /// **'Revocada: se rechaza siempre'**
  String get markerRevoked;

  /// No description provided for @matchCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0{ninguna coincide} =1{1 coincide} other{{count} coinciden}}'**
  String matchCount(int count);

  /// No description provided for @matchesHost.
  ///
  /// In es, this message translates to:
  /// **'Coincide con {host}'**
  String matchesHost(String host);

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

  /// No description provided for @missingProxy.
  ///
  /// In es, this message translates to:
  /// **'Falta el servidor o el puerto del proxy.'**
  String get missingProxy;

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

  /// No description provided for @monthsShort.
  ///
  /// In es, this message translates to:
  /// **'ene,feb,mar,abr,may,jun,jul,ago,sept,oct,nov,dic'**
  String get monthsShort;

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

  /// No description provided for @moshFallbackNoClient.
  ///
  /// In es, this message translates to:
  /// **'sin Mosh: falta mosh-client en este equipo (brew install mosh, o apt install mosh) · sigue por SSH'**
  String get moshFallbackNoClient;

  /// No description provided for @moshFallbackNoServer.
  ///
  /// In es, this message translates to:
  /// **'sin Mosh: el servidor no tiene mosh-server · sigue por SSH'**
  String get moshFallbackNoServer;

  /// No description provided for @moshFallbackNoUdp.
  ///
  /// In es, this message translates to:
  /// **'sin Mosh: no llega el UDP del servidor (un cortafuegos, o una red que no lo deja pasar) · sigue por SSH, en tmux'**
  String get moshFallbackNoUdp;

  /// No description provided for @moshFallbackOther.
  ///
  /// In es, this message translates to:
  /// **'sin Mosh: {said} · sigue por SSH'**
  String moshFallbackOther(String said);

  /// No description provided for @moshFallbackWindows.
  ///
  /// In es, this message translates to:
  /// **'sin Mosh: en Windows todavía no · sigue por SSH'**
  String get moshFallbackWindows;

  /// No description provided for @moshNote.
  ///
  /// In es, this message translates to:
  /// **'Hace falta mosh-server en el servidor y mosh-client en este equipo (macOS: brew install mosh; Linux: apt o dnf install mosh). El UDP va directo: los saltos solo sirven para arrancarlo. Si no llega, la sesión sigue por SSH, en tmux.'**
  String get moshNote;

  /// No description provided for @moshOff.
  ///
  /// In es, this message translates to:
  /// **'Apagado: SSH'**
  String get moshOff;

  /// No description provided for @moshOn.
  ///
  /// In es, this message translates to:
  /// **'Encendido: por Mosh cuando se pueda'**
  String get moshOn;

  /// No description provided for @moshServer.
  ///
  /// In es, this message translates to:
  /// **'Servidor de Mosh'**
  String get moshServer;

  /// No description provided for @moshServerHelp.
  ///
  /// In es, this message translates to:
  /// **'Dónde está mosh-server en el servidor, si no está en su PATH: /opt/homebrew/bin/mosh-server'**
  String get moshServerHelp;

  /// No description provided for @moveEarlier.
  ///
  /// In es, this message translates to:
  /// **'Mover antes'**
  String get moveEarlier;

  /// No description provided for @moveLater.
  ///
  /// In es, this message translates to:
  /// **'Mover después'**
  String get moveLater;

  /// No description provided for @moveToNewTab.
  ///
  /// In es, this message translates to:
  /// **'Mover a una pestaña nueva'**
  String get moveToNewTab;

  /// No description provided for @movedToGroup.
  ///
  /// In es, this message translates to:
  /// **'{host} está ahora en {group}.'**
  String movedToGroup(String host, String group);

  /// No description provided for @name.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get name;

  /// No description provided for @nameAndMore.
  ///
  /// In es, this message translates to:
  /// **'{name} y {count} más'**
  String nameAndMore(String name, int count);

  /// No description provided for @nameNoSlash.
  ///
  /// In es, this message translates to:
  /// **'Un nombre no puede llevar «/».'**
  String get nameNoSlash;

  /// No description provided for @namesAndMore.
  ///
  /// In es, this message translates to:
  /// **'{names} y {count} más'**
  String namesAndMore(String names, int count);

  /// No description provided for @netLost.
  ///
  /// In es, this message translates to:
  /// **'se ha perdido la conexión.'**
  String get netLost;

  /// No description provided for @netNoAnswer.
  ///
  /// In es, this message translates to:
  /// **'no responde ({seconds} s sin respuesta).'**
  String netNoAnswer(int seconds);

  /// No description provided for @netNotFound.
  ///
  /// In es, this message translates to:
  /// **'no se encuentra el host.'**
  String get netNotFound;

  /// No description provided for @netOther.
  ///
  /// In es, this message translates to:
  /// **'ha fallado la red (más en «Detalles»).'**
  String get netOther;

  /// No description provided for @netProxyCommand.
  ///
  /// In es, this message translates to:
  /// **'el ProxyCommand ha fallado: {said}'**
  String netProxyCommand(String said);

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

  /// No description provided for @netUnreachable.
  ///
  /// In es, this message translates to:
  /// **'no se llega al host.'**
  String get netUnreachable;

  /// No description provided for @netUnreachableMac.
  ///
  /// In es, this message translates to:
  /// **'no se llega al host. Si está en tu red local, mira que OpenWard tenga permiso en Ajustes del Sistema › Privacidad y seguridad › Red local.'**
  String get netUnreachableMac;

  /// No description provided for @newEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Nuevo…'**
  String get newEllipsis;

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

  /// No description provided for @newIdentity.
  ///
  /// In es, this message translates to:
  /// **'Nueva identidad'**
  String get newIdentity;

  /// No description provided for @newIdentityEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Nueva identidad…'**
  String get newIdentityEllipsis;

  /// No description provided for @newKey.
  ///
  /// In es, this message translates to:
  /// **'Nueva clave'**
  String get newKey;

  /// No description provided for @newKeyAction.
  ///
  /// In es, this message translates to:
  /// **'Nueva clave…'**
  String get newKeyAction;

  /// No description provided for @newKeyWhere.
  ///
  /// In es, this message translates to:
  /// **'Se guarda en {private} (solo tú puedes leerla) y su parte pública en {public}.'**
  String newKeyWhere(String private, String public);

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

  /// No description provided for @newPassphrase.
  ///
  /// In es, this message translates to:
  /// **'Frase de paso nueva'**
  String get newPassphrase;

  /// No description provided for @newSnippet.
  ///
  /// In es, this message translates to:
  /// **'Nuevo snippet'**
  String get newSnippet;

  /// No description provided for @newSubgroup.
  ///
  /// In es, this message translates to:
  /// **'Nuevo subgrupo'**
  String get newSubgroup;

  /// No description provided for @newTunnel.
  ///
  /// In es, this message translates to:
  /// **'Nuevo túnel'**
  String get newTunnel;

  /// No description provided for @newsConnectionBody.
  ///
  /// In es, this message translates to:
  /// **'Si el servidor se va, se nota en segundos y la conexión vuelve sola; con la sesión persistente, vuelves al mismo terminal en tmux. Al conectar y al reconectar, el camino hasta el host, animado.'**
  String get newsConnectionBody;

  /// No description provided for @newsConnectionTitle.
  ///
  /// In es, this message translates to:
  /// **'Conexión viva'**
  String get newsConnectionTitle;

  /// No description provided for @newsEditorBody.
  ///
  /// In es, this message translates to:
  /// **'Lo heredado se ve con borde discontinuo y de dónde viene; se cambia escribiendo encima, y ↺ vuelve a heredarlo. Lo avanzado, plegado. Igual en grupos, y la misma rejilla en identidades.'**
  String get newsEditorBody;

  /// No description provided for @newsEditorTitle.
  ///
  /// In es, this message translates to:
  /// **'Un editor de hosts más claro'**
  String get newsEditorTitle;

  /// No description provided for @newsEnvBody.
  ///
  /// In es, this message translates to:
  /// **'Marca un grupo como Producción, Pruebas o con un nombre y color propios: sus pestañas y terminales lo dicen, para no escribir en el servidor equivocado.'**
  String get newsEnvBody;

  /// No description provided for @newsEnvTitle.
  ///
  /// In es, this message translates to:
  /// **'El entorno de cada servidor, a la vista'**
  String get newsEnvTitle;

  /// No description provided for @newsFavoritesBody.
  ///
  /// In es, this message translates to:
  /// **'La estrella al pasar el ratón por un host: arriba en la barra, en el raíl, en la paleta y en el inicio, en el orden que les des.'**
  String get newsFavoritesBody;

  /// No description provided for @newsFavoritesTitle.
  ///
  /// In es, this message translates to:
  /// **'Favoritos'**
  String get newsFavoritesTitle;

  /// No description provided for @newsFocusBody.
  ///
  /// In es, this message translates to:
  /// **'La barra lateral se pliega en iconos o se oculta ({keys}), sola al abrir una sesión si quieres, y oculta se asoma al dejar el ratón en el borde. Su ancho se cambia arrastrando el borde, y el terminal tiene más margen. Todo en Ajustes › General.'**
  String newsFocusBody(String keys);

  /// No description provided for @newsFocusTitle.
  ///
  /// In es, this message translates to:
  /// **'Más sitio para el terminal'**
  String get newsFocusTitle;

  /// No description provided for @newsFresh.
  ///
  /// In es, this message translates to:
  /// **'nuevo'**
  String get newsFresh;

  /// No description provided for @newsHopsBody.
  ///
  /// In es, this message translates to:
  /// **'Con un bastion por medio, la tarjeta de la latencia dice cuánto tarda cada salto, para ver qué parte del camino va lenta.'**
  String get newsHopsBody;

  /// No description provided for @newsHopsTitle.
  ///
  /// In es, this message translates to:
  /// **'La latencia de cada salto'**
  String get newsHopsTitle;

  /// No description provided for @newsIdentitiesBody.
  ///
  /// In es, this message translates to:
  /// **'Usuario, claves y agente con un nombre, para un grupo entero o varios hosts a la vez.'**
  String get newsIdentitiesBody;

  /// No description provided for @newsIdentitiesTitle.
  ///
  /// In es, this message translates to:
  /// **'Identidades'**
  String get newsIdentitiesTitle;

  /// No description provided for @newsImportBody.
  ///
  /// In es, this message translates to:
  /// **'Hosts, grupos, identidades y túneles de Termius, PuTTY, KiTTY, MobaXterm, Tabby o SecureCRT, y hosts de un CSV, desde «…» › Importar… en la barra lateral. Las contraseñas no se traen.'**
  String get newsImportBody;

  /// No description provided for @newsImportTitle.
  ///
  /// In es, this message translates to:
  /// **'Importar desde tu cliente anterior'**
  String get newsImportTitle;

  /// No description provided for @newsKeysBody.
  ///
  /// In es, this message translates to:
  /// **'Crea claves Ed25519, ECDSA o RSA, importa las tuyas, mira sus huellas y súbelas a un servidor sin salir de OpenWard, como ssh-copy-id.'**
  String get newsKeysBody;

  /// No description provided for @newsKeysTitle.
  ///
  /// In es, this message translates to:
  /// **'Claves'**
  String get newsKeysTitle;

  /// No description provided for @newsLatencyBody.
  ///
  /// In es, this message translates to:
  /// **'La barra de estado dice cuánto tarda el servidor en responder, con una gráfica de las últimas comprobaciones; en ámbar si sube mucho sobre lo habitual. Al pasar el ratón, la ruta y el cifrado.'**
  String get newsLatencyBody;

  /// No description provided for @newsLatencyTitle.
  ///
  /// In es, this message translates to:
  /// **'La latencia, siempre a la vista'**
  String get newsLatencyTitle;

  /// No description provided for @newsLogoBody.
  ///
  /// In es, this message translates to:
  /// **'Umbral, una O abierta con un chevrón: en el icono de la app y, dentro, en la bienvenida, el inicio, Acerca de y aquí, en el color de tu tema.'**
  String get newsLogoBody;

  /// No description provided for @newsLogoTitle.
  ///
  /// In es, this message translates to:
  /// **'Logo nuevo'**
  String get newsLogoTitle;

  /// No description provided for @newsLogsBody.
  ///
  /// In es, this message translates to:
  /// **'Cada conexión deja su entrada en Registros ({shortcut}): dónde, cuándo y cómo acabó. Donde lo actives (Ajustes › Registros, o en un grupo o un host), también lo que salió en pantalla, para buscar en él, volver a verlo comando a comando y exportarlo. Nunca lo que escribes; viene apagado mientras no vaya cifrado.'**
  String newsLogsBody(String shortcut);

  /// No description provided for @newsLogsTitle.
  ///
  /// In es, this message translates to:
  /// **'Registros de sesión'**
  String get newsLogsTitle;

  /// No description provided for @newsMoreThemesBody.
  ///
  /// In es, this message translates to:
  /// **'Monitor, con letras verdes de verdad; Berenjena, con el terminal morado; Búnker, todo en un solo fósforo; Marino, verde sobre azul marino; y Catppuccin, Dracula y Tokyo Night para toda la ventana. En Ajustes › Apariencia.'**
  String get newsMoreThemesBody;

  /// No description provided for @newsMoreThemesTitle.
  ///
  /// In es, this message translates to:
  /// **'Siete familias de temas más'**
  String get newsMoreThemesTitle;

  /// No description provided for @newsPaletteBody.
  ///
  /// In es, this message translates to:
  /// **'Todo lo que hace la ventana, tus hosts, snippets y los comandos que ya ejecutaste, a unas letras ({shortcut}). El historial se queda en este equipo y nunca guarda contraseñas.'**
  String newsPaletteBody(String shortcut);

  /// No description provided for @newsPaletteTitle.
  ///
  /// In es, this message translates to:
  /// **'Paleta de comandos e historial'**
  String get newsPaletteTitle;

  /// No description provided for @newsPanesBody.
  ///
  /// In es, this message translates to:
  /// **'Divide una pestaña ({split}) o arrastra otra, o un host, sobre un terminal; escribe en varios paneles a la vez ({broadcast}). Con exit, la pestaña se cierra sola.'**
  String newsPanesBody(String split, String broadcast);

  /// No description provided for @newsPanesBody2.
  ///
  /// In es, this message translates to:
  /// **'Arrastrar una pestaña sobre un terminal ya no mueve la ventana. El menú de cada panel lo mueve a su pestaña, lo intercambia o iguala tamaños ({keys}); el panel nuevo ofrece las pestañas abiertas, cada panel tiene su nombre y el borde entre ellos se ve y se agarra.'**
  String newsPanesBody2(String keys);

  /// No description provided for @newsPanesTitle.
  ///
  /// In es, this message translates to:
  /// **'Paneles y broadcast'**
  String get newsPanesTitle;

  /// No description provided for @newsPanesTitle2.
  ///
  /// In es, this message translates to:
  /// **'Paneles sin adivinar'**
  String get newsPanesTitle2;

  /// No description provided for @newsSearchBody.
  ///
  /// In es, this message translates to:
  /// **'{keys} abre la paleta con las pestañas abiertas, las conexiones recientes, los hosts, las acciones y lo que ya ejecutaste. Empieza por > para ver solo las acciones.'**
  String newsSearchBody(String keys);

  /// No description provided for @newsSearchTitle.
  ///
  /// In es, this message translates to:
  /// **'Un atajo para buscarlo todo'**
  String get newsSearchTitle;

  /// No description provided for @newsSftpBody.
  ///
  /// In es, this message translates to:
  /// **'Arrastra entre este equipo y el servidor, con cola, reanudación y lo que ya existe resuelto a tu manera ({shortcut}).'**
  String newsSftpBody(String shortcut);

  /// No description provided for @newsSftpTitle.
  ///
  /// In es, this message translates to:
  /// **'SFTP de doble panel'**
  String get newsSftpTitle;

  /// No description provided for @newsShortcutsBody.
  ///
  /// In es, this message translates to:
  /// **'{keys} abre la lista de atajos, con búsqueda, y los botones dicen el suyo al pasar el ratón.'**
  String newsShortcutsBody(String keys);

  /// No description provided for @newsShortcutsTitle.
  ///
  /// In es, this message translates to:
  /// **'Todos los atajos, a mano'**
  String get newsShortcutsTitle;

  /// No description provided for @newsSidebarBody.
  ///
  /// In es, this message translates to:
  /// **'Todos los hosts están en Hosts ({keys}), con filtros por entorno, etiqueta y sistema. La barra lateral se queda con lo de cada día: lo abierto, los favoritos y los recientes, con la Biblioteca en una fila; plegada en raíl, lo abierto cabe en un contador.'**
  String newsSidebarBody(String keys);

  /// No description provided for @newsSidebarTitle.
  ///
  /// In es, this message translates to:
  /// **'Los hosts, en su página'**
  String get newsSidebarTitle;

  /// No description provided for @newsSnippetsBody.
  ///
  /// In es, this message translates to:
  /// **'Comandos con variables a un atajo ({shortcut}), y las claves en las que confías, con las de ~/.ssh/known_hosts.'**
  String newsSnippetsBody(String shortcut);

  /// No description provided for @newsSnippetsTitle.
  ///
  /// In es, this message translates to:
  /// **'Snippets y hosts conocidos'**
  String get newsSnippetsTitle;

  /// No description provided for @newsStartBody.
  ///
  /// In es, this message translates to:
  /// **'La conexión rápida completa con tus hosts y las direcciones que ya usaste; debajo, las conexiones recientes con cuánto duraron y los túneles abiertos.'**
  String get newsStartBody;

  /// No description provided for @newsStartTitle.
  ///
  /// In es, this message translates to:
  /// **'Un inicio para volver a lo de siempre'**
  String get newsStartTitle;

  /// No description provided for @newsSystemBody2.
  ///
  /// In es, this message translates to:
  /// **'Debian, Ubuntu, Fedora, Alpine y 22 sistemas más, con su logo del color de su entorno; macOS y Windows, con un icono propio. Para los que no lo dicen al conectar, como los de Tailscale SSH, «Averiguar el sistema» en su menú lee /etc/os-release; o en todos, desde Ajustes › General.'**
  String get newsSystemBody2;

  /// No description provided for @newsSystemTitle2.
  ///
  /// In es, this message translates to:
  /// **'El sistema de cada servidor, con su logo'**
  String get newsSystemTitle2;

  /// No description provided for @newsThemesBody.
  ///
  /// In es, this message translates to:
  /// **'Cinco temas en claro y oscuro, capas que se combinan, tamaño del texto, contraste mínimo y reducir movimiento.'**
  String get newsThemesBody;

  /// No description provided for @newsThemesTitle.
  ///
  /// In es, this message translates to:
  /// **'Temas y accesibilidad visual'**
  String get newsThemesTitle;

  /// No description provided for @newsTunnelsBody.
  ///
  /// In es, this message translates to:
  /// **'Local, remoto y SOCKS5, que se abren al conectar; también proxy HTTP y SOCKS5 para llegar al servidor.'**
  String get newsTunnelsBody;

  /// No description provided for @newsTunnelsTitle.
  ///
  /// In es, this message translates to:
  /// **'Túneles guardados y proxy'**
  String get newsTunnelsTitle;

  /// No description provided for @newsWorkspacesBody.
  ///
  /// In es, this message translates to:
  /// **'Guarda tus pestañas y paneles con un nombre y ábrelos otra vez, ya conectados, desde la biblioteca o la paleta.'**
  String get newsWorkspacesBody;

  /// No description provided for @newsWorkspacesTitle.
  ///
  /// In es, this message translates to:
  /// **'Espacios de trabajo'**
  String get newsWorkspacesTitle;

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

  /// No description provided for @noAnswerFor.
  ///
  /// In es, this message translates to:
  /// **'Sin respuesta desde hace {seconds} s.'**
  String noAnswerFor(int seconds);

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

  /// No description provided for @noIdentities.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay identidades'**
  String get noIdentities;

  /// No description provided for @noIdentitiesBody.
  ///
  /// In es, this message translates to:
  /// **'Una identidad junta un usuario, sus claves y el agente con un nombre («deploy en producción»). Ponla en un grupo y todos sus hosts entran igual; cámbiala una vez y cambian todos.'**
  String get noIdentitiesBody;

  /// No description provided for @noIdentityInherited.
  ///
  /// In es, this message translates to:
  /// **'Ningún grupo pone una'**
  String get noIdentityInherited;

  /// No description provided for @noIdentityNow.
  ///
  /// In es, this message translates to:
  /// **'Sin identidad'**
  String get noIdentityNow;

  /// No description provided for @noJumpsYet.
  ///
  /// In es, this message translates to:
  /// **'Ninguno todavía.'**
  String get noJumpsYet;

  /// No description provided for @noKeys.
  ///
  /// In es, this message translates to:
  /// **'No hay claves en ~/.ssh'**
  String get noKeys;

  /// No description provided for @noKeysBody.
  ///
  /// In es, this message translates to:
  /// **'Crea una con «Nueva clave…» o trae la que ya tengas con «Importar…».'**
  String get noKeysBody;

  /// No description provided for @noKeysYet.
  ///
  /// In es, this message translates to:
  /// **'Sin claves: se prueban las habituales de ~/.ssh y las del agente.'**
  String get noKeysYet;

  /// No description provided for @noKnownHosts.
  ///
  /// In es, this message translates to:
  /// **'Aún no confías en ninguna clave'**
  String get noKnownHosts;

  /// No description provided for @noKnownHostsBody.
  ///
  /// In es, this message translates to:
  /// **'Las claves de los servidores aparecen aquí cuando conectas y confías en ellas.'**
  String get noKnownHostsBody;

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

  /// No description provided for @noPublicKey.
  ///
  /// In es, this message translates to:
  /// **'{name} no tiene .pub y está cifrada: sin su frase de paso no se puede leer la parte pública.'**
  String noPublicKey(String name);

  /// No description provided for @noResponse.
  ///
  /// In es, this message translates to:
  /// **'sin respuesta'**
  String get noResponse;

  /// No description provided for @noResults.
  ///
  /// In es, this message translates to:
  /// **'Ningún host coincide.'**
  String get noResults;

  /// No description provided for @noSnippetMatches.
  ///
  /// In es, this message translates to:
  /// **'Ningún snippet coincide'**
  String get noSnippetMatches;

  /// No description provided for @noSnippets.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay snippets'**
  String get noSnippets;

  /// No description provided for @noSnippetsBody.
  ///
  /// In es, this message translates to:
  /// **'Un snippet es un comando guardado que envías a un terminal con un atajo. Lo que escribas entre {braces} se pregunta al ejecutarlo.'**
  String noSnippetsBody(String braces);

  /// No description provided for @noSnippetsYet.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay snippets. Crea uno en Biblioteca › Snippets.'**
  String get noSnippetsYet;

  /// No description provided for @noTunnels.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay túneles'**
  String get noTunnels;

  /// No description provided for @noTunnelsBody.
  ///
  /// In es, this message translates to:
  /// **'Un túnel lleva un puerto de este equipo a un servicio que solo ve el servidor (una base de datos, un panel), o al revés. Crea uno o tráelos de tu ~/.ssh/config.'**
  String get noTunnelsBody;

  /// No description provided for @noWorkspaces.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay espacios de trabajo'**
  String get noWorkspaces;

  /// No description provided for @noWorkspacesBody.
  ///
  /// In es, this message translates to:
  /// **'Abre las pestañas y divide los paneles como los quieras, y guárdalos con «Guardar las pestañas abiertas…» (también en el menú de una pestaña y en la paleta de comandos).'**
  String get noWorkspacesBody;

  /// No description provided for @notNow.
  ///
  /// In es, this message translates to:
  /// **'Ahora no'**
  String get notNow;

  /// No description provided for @notResponding.
  ///
  /// In es, this message translates to:
  /// **'{host} no responde'**
  String notResponding(String host);

  /// No description provided for @notSaved.
  ///
  /// In es, this message translates to:
  /// **'sin guardar'**
  String get notSaved;

  /// No description provided for @notes.
  ///
  /// In es, this message translates to:
  /// **'Notas'**
  String get notes;

  /// No description provided for @nowIdentity.
  ///
  /// In es, this message translates to:
  /// **'Ahora: {identity}'**
  String nowIdentity(String identity);

  /// No description provided for @nowIdentityFromGroup.
  ///
  /// In es, this message translates to:
  /// **'Ahora: {identity}, del grupo {group}'**
  String nowIdentityFromGroup(String identity, String group);

  /// No description provided for @nowNoIdentity.
  ///
  /// In es, this message translates to:
  /// **'ahora: ninguna'**
  String get nowNoIdentity;

  /// No description provided for @offerOnlyTheseKeys.
  ///
  /// In es, this message translates to:
  /// **'Ofrecer solo estas claves'**
  String get offerOnlyTheseKeys;

  /// No description provided for @offerOnlyTheseKeysNote.
  ///
  /// In es, this message translates to:
  /// **'No probar las demás claves del agente (IdentitiesOnly). Útil si el servidor corta tras varios intentos.'**
  String get offerOnlyTheseKeysNote;

  /// No description provided for @ok.
  ///
  /// In es, this message translates to:
  /// **'Aceptar'**
  String get ok;

  /// No description provided for @onConnect.
  ///
  /// In es, this message translates to:
  /// **'Al conectar'**
  String get onConnect;

  /// No description provided for @onExit.
  ///
  /// In es, this message translates to:
  /// **'Al salir del shell'**
  String get onExit;

  /// No description provided for @onExitAlways.
  ///
  /// In es, this message translates to:
  /// **'Cerrar siempre'**
  String get onExitAlways;

  /// No description provided for @onExitClean.
  ///
  /// In es, this message translates to:
  /// **'Cerrar si sale bien'**
  String get onExitClean;

  /// No description provided for @onExitHelp.
  ///
  /// In es, this message translates to:
  /// **'Con exit o logout, el panel (o la pestaña, si es el último) se cierra solo. Si el programa acaba con un error, se queda abierto para que leas qué pasó, salvo con «Cerrar siempre». Una conexión que se corta nunca se cierra sola: sigue reconectando.'**
  String get onExitHelp;

  /// No description provided for @onExitNever.
  ///
  /// In es, this message translates to:
  /// **'Dejarla abierta'**
  String get onExitNever;

  /// No description provided for @onSecurityKey.
  ///
  /// In es, this message translates to:
  /// **'En una llave de seguridad (FIDO2)'**
  String get onSecurityKey;

  /// No description provided for @onSecurityKeyNote.
  ///
  /// In es, this message translates to:
  /// **'Toca la llave cuando parpadee. El archivo no guarda ningún secreto: sin la llave no sirve, y nadie puede sacarla de ella.'**
  String get onSecurityKeyNote;

  /// No description provided for @onSend.
  ///
  /// In es, this message translates to:
  /// **'Al enviar'**
  String get onSend;

  /// No description provided for @onSessionHide.
  ///
  /// In es, this message translates to:
  /// **'Oculta'**
  String get onSessionHide;

  /// No description provided for @onSessionKeep.
  ///
  /// In es, this message translates to:
  /// **'Como esté'**
  String get onSessionKeep;

  /// No description provided for @onSessionRail.
  ///
  /// In es, this message translates to:
  /// **'En raíl'**
  String get onSessionRail;

  /// No description provided for @onThisComputer.
  ///
  /// In es, this message translates to:
  /// **'En este equipo'**
  String get onThisComputer;

  /// No description provided for @onlyTheServer.
  ///
  /// In es, this message translates to:
  /// **'Solo el servidor'**
  String get onlyTheServer;

  /// No description provided for @onlyThisComputer.
  ///
  /// In es, this message translates to:
  /// **'Solo este equipo (127.0.0.1)'**
  String get onlyThisComputer;

  /// No description provided for @open.
  ///
  /// In es, this message translates to:
  /// **'Abrir'**
  String get open;

  /// No description provided for @openATerminalFirst.
  ///
  /// In es, this message translates to:
  /// **'Abre un terminal para ejecutarlo'**
  String get openATerminalFirst;

  /// No description provided for @openAction.
  ///
  /// In es, this message translates to:
  /// **'Abrir'**
  String get openAction;

  /// No description provided for @openCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 abierto} other{{count} abiertos}}'**
  String openCount(int count);

  /// No description provided for @openLocal.
  ///
  /// In es, this message translates to:
  /// **'Abrir un terminal local'**
  String get openLocal;

  /// No description provided for @openOnConnect.
  ///
  /// In es, this message translates to:
  /// **'Abrir al conectar a {host}'**
  String openOnConnect(String host);

  /// No description provided for @openOnConnectNote.
  ///
  /// In es, this message translates to:
  /// **'Desde un terminal o un SFTP. Si el puerto está ocupado, la conexión sigue y el túnel avisa.'**
  String get openOnConnectNote;

  /// No description provided for @openOtherHere.
  ///
  /// In es, this message translates to:
  /// **'Abrir otra cosa aquí…'**
  String get openOtherHere;

  /// No description provided for @openSection.
  ///
  /// In es, this message translates to:
  /// **'Abiertas'**
  String get openSection;

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

  /// No description provided for @openTabsCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 pestaña abierta} other{{count} pestañas abiertas}}'**
  String openTabsCount(int count);

  /// No description provided for @openTunnels.
  ///
  /// In es, this message translates to:
  /// **'Túneles abiertos'**
  String get openTunnels;

  /// No description provided for @optionAltBoth.
  ///
  /// In es, this message translates to:
  /// **'Las dos'**
  String get optionAltBoth;

  /// No description provided for @optionAltLeft.
  ///
  /// In es, this message translates to:
  /// **'La izquierda'**
  String get optionAltLeft;

  /// No description provided for @optionAltOff.
  ///
  /// In es, this message translates to:
  /// **'Ninguna'**
  String get optionAltOff;

  /// No description provided for @optionAltRight.
  ///
  /// In es, this message translates to:
  /// **'La derecha'**
  String get optionAltRight;

  /// No description provided for @optionAsAlt.
  ///
  /// In es, this message translates to:
  /// **'Opción como Alt'**
  String get optionAsAlt;

  /// No description provided for @optionAsAltHelp.
  ///
  /// In es, this message translates to:
  /// **'La Opción que sea Alt envía Esc + tecla, como esperan emacs y readline; la otra sigue escribiendo símbolos como @ o €.'**
  String get optionAsAltHelp;

  /// No description provided for @orAnAddress.
  ///
  /// In es, this message translates to:
  /// **'o una dirección: usuario@host:puerto'**
  String get orAnAddress;

  /// No description provided for @orTypeAPath.
  ///
  /// In es, this message translates to:
  /// **'o escribe una ruta: admite ~, %h, %r y %u'**
  String get orTypeAPath;

  /// No description provided for @ownUserWins.
  ///
  /// In es, this message translates to:
  /// **'Pone su propio usuario ({user}), que seguirá mandando.'**
  String ownUserWins(String user);

  /// No description provided for @paletteActions.
  ///
  /// In es, this message translates to:
  /// **'Acciones'**
  String get paletteActions;

  /// No description provided for @paletteBroadcast.
  ///
  /// In es, this message translates to:
  /// **'Broadcast en esta pestaña (encender o apagar)'**
  String get paletteBroadcast;

  /// No description provided for @paletteChoose.
  ///
  /// In es, this message translates to:
  /// **'elegir'**
  String get paletteChoose;

  /// No description provided for @paletteDo.
  ///
  /// In es, this message translates to:
  /// **'hacer'**
  String get paletteDo;

  /// No description provided for @paletteForget.
  ///
  /// In es, this message translates to:
  /// **'quitar del historial'**
  String get paletteForget;

  /// No description provided for @paletteHere.
  ///
  /// In es, this message translates to:
  /// **'aquí'**
  String get paletteHere;

  /// No description provided for @paletteHint.
  ///
  /// In es, this message translates to:
  /// **'Busca un host, una pestaña, una acción o un comando que ya usaste…'**
  String get paletteHint;

  /// No description provided for @paletteHistory.
  ///
  /// In es, this message translates to:
  /// **'Historial'**
  String get paletteHistory;

  /// No description provided for @paletteHosts.
  ///
  /// In es, this message translates to:
  /// **'Hosts'**
  String get paletteHosts;

  /// No description provided for @paletteNothing.
  ///
  /// In es, this message translates to:
  /// **'Nada coincide.'**
  String get paletteNothing;

  /// No description provided for @paletteOnlyActions.
  ///
  /// In es, this message translates to:
  /// **'solo acciones'**
  String get paletteOnlyActions;

  /// No description provided for @paletteRecent.
  ///
  /// In es, this message translates to:
  /// **'Recientes'**
  String get paletteRecent;

  /// No description provided for @paletteRun.
  ///
  /// In es, this message translates to:
  /// **'ejecutar'**
  String get paletteRun;

  /// No description provided for @paletteTabs.
  ///
  /// In es, this message translates to:
  /// **'Pestañas abiertas'**
  String get paletteTabs;

  /// No description provided for @paletteTypeOnly.
  ///
  /// In es, this message translates to:
  /// **'solo escribir'**
  String get paletteTypeOnly;

  /// No description provided for @paneOpenTabs.
  ///
  /// In es, this message translates to:
  /// **'Pestañas abiertas'**
  String get paneOpenTabs;

  /// No description provided for @paneOpenTabsNote.
  ///
  /// In es, this message translates to:
  /// **'pasan a este panel'**
  String get paneOpenTabsNote;

  /// No description provided for @paneOptions.
  ///
  /// In es, this message translates to:
  /// **'Opciones del panel'**
  String get paneOptions;

  /// No description provided for @paneSearch.
  ///
  /// In es, this message translates to:
  /// **'Busca una pestaña o un host'**
  String get paneSearch;

  /// No description provided for @paneWhat.
  ///
  /// In es, this message translates to:
  /// **'¿Qué abres en este panel?'**
  String get paneWhat;

  /// No description provided for @parityEven.
  ///
  /// In es, this message translates to:
  /// **'Par'**
  String get parityEven;

  /// No description provided for @parityNone.
  ///
  /// In es, this message translates to:
  /// **'Ninguna'**
  String get parityNone;

  /// No description provided for @parityOdd.
  ///
  /// In es, this message translates to:
  /// **'Impar'**
  String get parityOdd;

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

  /// No description provided for @passphraseOptional.
  ///
  /// In es, this message translates to:
  /// **'Frase de paso (opcional)'**
  String get passphraseOptional;

  /// No description provided for @passphraseTitle.
  ///
  /// In es, this message translates to:
  /// **'Frase de la clave'**
  String get passphraseTitle;

  /// No description provided for @passphrasesDiffer.
  ///
  /// In es, this message translates to:
  /// **'Las dos frases de paso no coinciden.'**
  String get passphrasesDiffer;

  /// No description provided for @passwordTitle.
  ///
  /// In es, this message translates to:
  /// **'Contraseña'**
  String get passwordTitle;

  /// No description provided for @passwordsNever.
  ///
  /// In es, this message translates to:
  /// **'Las contraseñas no se traen nunca: OpenWard las pide al conectar.'**
  String get passwordsNever;

  /// No description provided for @paste.
  ///
  /// In es, this message translates to:
  /// **'Pegar'**
  String get paste;

  /// No description provided for @pasteHasHidden.
  ///
  /// In es, this message translates to:
  /// **'Lleva caracteres que no se ven, en ámbar: un terminal los obedece aunque no los enseñe.'**
  String get pasteHasHidden;

  /// No description provided for @pasteHiddenTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Pegar con caracteres que no se ven?'**
  String get pasteHiddenTitle;

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

  /// No description provided for @persistentOff.
  ///
  /// In es, this message translates to:
  /// **'No'**
  String get persistentOff;

  /// No description provided for @persistentOn.
  ///
  /// In es, this message translates to:
  /// **'Sí, en tmux: sigue tras un corte'**
  String get persistentOn;

  /// No description provided for @persistentSession.
  ///
  /// In es, this message translates to:
  /// **'Sesión persistente'**
  String get persistentSession;

  /// No description provided for @pickIdentity.
  ///
  /// In es, this message translates to:
  /// **'Elige una identidad o «Ninguna».'**
  String get pickIdentity;

  /// No description provided for @pinField.
  ///
  /// In es, this message translates to:
  /// **'PIN'**
  String get pinField;

  /// No description provided for @pinSidebar.
  ///
  /// In es, this message translates to:
  /// **'Dejar la barra abierta'**
  String get pinSidebar;

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

  /// No description provided for @portBusyNow.
  ///
  /// In es, this message translates to:
  /// **'ocupado ahora'**
  String get portBusyNow;

  /// No description provided for @portHere.
  ///
  /// In es, this message translates to:
  /// **'Puerto aquí'**
  String get portHere;

  /// No description provided for @portOnHost.
  ///
  /// In es, this message translates to:
  /// **'Puerto en {host}'**
  String portOnHost(String host);

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

  /// No description provided for @pressEnterAtTheEnd.
  ///
  /// In es, this message translates to:
  /// **'Pulsar Intro al final'**
  String get pressEnterAtTheEnd;

  /// No description provided for @pressEnterAtTheEndNote.
  ///
  /// In es, this message translates to:
  /// **'Apágalo para dejar el comando escrito y revisarlo antes de ejecutarlo.'**
  String get pressEnterAtTheEndNote;

  /// No description provided for @preview.
  ///
  /// In es, this message translates to:
  /// **'Vista previa'**
  String get preview;

  /// No description provided for @previewCannotImport.
  ///
  /// In es, this message translates to:
  /// **'{protocol}: aún no se puede usar'**
  String previewCannotImport(String protocol);

  /// No description provided for @previewHostsOf.
  ///
  /// In es, this message translates to:
  /// **'{selected} de {total} hosts'**
  String previewHostsOf(int selected, int total);

  /// No description provided for @previewIdentities.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 identidad} other{{count} identidades}}'**
  String previewIdentities(int count);

  /// No description provided for @previewIntoExisting.
  ///
  /// In es, this message translates to:
  /// **'En «{name}», el grupo de la importación anterior'**
  String previewIntoExisting(String name);

  /// No description provided for @previewIntoGroup.
  ///
  /// In es, this message translates to:
  /// **'Dentro del grupo'**
  String get previewIntoGroup;

  /// No description provided for @previewKeyFound.
  ///
  /// In es, this message translates to:
  /// **'→ {path} · la misma clave pública'**
  String previewKeyFound(String path);

  /// No description provided for @previewKeyMissing.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0{No está en ~/.ssh.} =1{No está en ~/.ssh. Sin ella, quien la usa se queda sin clave.} other{No está en ~/.ssh. Sin ella, los {count} que la usan se quedan sin clave.}}'**
  String previewKeyMissing(int count);

  /// No description provided for @previewKeys.
  ///
  /// In es, this message translates to:
  /// **'Claves'**
  String get previewKeys;

  /// No description provided for @previewKnownHosts.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 host conocido} other{{count} hosts conocidos}}'**
  String previewKnownHosts(int count);

  /// No description provided for @previewLive.
  ///
  /// In es, this message translates to:
  /// **'Los cambios se ven al momento en toda la ventana.'**
  String get previewLive;

  /// No description provided for @previewNoPasswords.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{No se trae la contraseña o frase de paso guardada: OpenWard la pide al conectar.} other{No se traen las {count} contraseñas y frases de paso guardadas: OpenWard las pide al conectar.}}'**
  String previewNoPasswords(int count);

  /// No description provided for @previewSaveKey.
  ///
  /// In es, this message translates to:
  /// **'Guardarla en {path}, que solo podrás leer tú'**
  String previewSaveKey(String path);

  /// No description provided for @previewSnippets.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 snippet} other{{count} snippets}}'**
  String previewSnippets(int count);

  /// No description provided for @previewSubtitle.
  ///
  /// In es, this message translates to:
  /// **'{hosts, plural, =1{1 host} other{{hosts} hosts}}{groups, plural, =0{} =1{ en 1 grupo} other{ en {groups} grupos}}'**
  String previewSubtitle(int hosts, int groups);

  /// No description provided for @previewTitle.
  ///
  /// In es, this message translates to:
  /// **'Importar de {program}'**
  String previewTitle(String program);

  /// No description provided for @previewTunnels.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 túnel} other{{count} túneles}}'**
  String previewTunnels(int count);

  /// No description provided for @privateKey.
  ///
  /// In es, this message translates to:
  /// **'Clave privada'**
  String get privateKey;

  /// No description provided for @protection.
  ///
  /// In es, this message translates to:
  /// **'Protección'**
  String get protection;

  /// No description provided for @protocol.
  ///
  /// In es, this message translates to:
  /// **'Protocolo'**
  String get protocol;

  /// No description provided for @protocolSerial.
  ///
  /// In es, this message translates to:
  /// **'Puerto serie'**
  String get protocolSerial;

  /// No description provided for @proxy.
  ///
  /// In es, this message translates to:
  /// **'Proxy'**
  String get proxy;

  /// No description provided for @proxyHttpNote.
  ///
  /// In es, this message translates to:
  /// **'Con un proxy HTTP, la petición CONNECT va sin cifrar: el proxy ve a qué host y puerto te conectas, pero no lo que pasa por SSH.'**
  String get proxyHttpNote;

  /// No description provided for @proxyLoginBody.
  ///
  /// In es, this message translates to:
  /// **'{proxy} pide usuario y contraseña para dejarte pasar. No se guardan.'**
  String proxyLoginBody(String proxy);

  /// No description provided for @proxyLoginTitle.
  ///
  /// In es, this message translates to:
  /// **'El proxy pide entrar'**
  String get proxyLoginTitle;

  /// No description provided for @proxyNone.
  ///
  /// In es, this message translates to:
  /// **'Sin proxy'**
  String get proxyNone;

  /// No description provided for @proxyNotWithCommand.
  ///
  /// In es, this message translates to:
  /// **'Con ProxyCommand no se usa el proxy.'**
  String get proxyNotWithCommand;

  /// No description provided for @proxyRouteTitle.
  ///
  /// In es, this message translates to:
  /// **'La ruta queda así'**
  String get proxyRouteTitle;

  /// No description provided for @proxyServer.
  ///
  /// In es, this message translates to:
  /// **'Servidor proxy'**
  String get proxyServer;

  /// No description provided for @proxyUser.
  ///
  /// In es, this message translates to:
  /// **'Usuario del proxy'**
  String get proxyUser;

  /// No description provided for @proxyUserHelp.
  ///
  /// In es, this message translates to:
  /// **'Opcional. La contraseña se pide al conectar y no se guarda.'**
  String get proxyUserHelp;

  /// No description provided for @publicKeyCopied.
  ///
  /// In es, this message translates to:
  /// **'Clave pública de {name} copiada.'**
  String publicKeyCopied(String name);

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
  /// **'usuario@servidor:puerto o el nombre de un host'**
  String get quickConnectHint;

  /// No description provided for @quickConnectInvalid.
  ///
  /// In es, this message translates to:
  /// **'Escribe una dirección como usuario@servidor:puerto.'**
  String get quickConnectInvalid;

  /// No description provided for @quit.
  ///
  /// In es, this message translates to:
  /// **'Salir'**
  String get quit;

  /// No description provided for @quitBody.
  ///
  /// In es, this message translates to:
  /// **'Se corta: {what}.'**
  String quitBody(String what);

  /// No description provided for @quitSessions.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 sesión abierta} other{{count} sesiones abiertas}}'**
  String quitSessions(int count);

  /// No description provided for @quitTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Salir de OpenWard?'**
  String get quitTitle;

  /// No description provided for @quitTransfers.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 transferencia en curso} other{{count} transferencias en curso}}'**
  String quitTransfers(int count);

  /// No description provided for @quitTunnels.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 túnel abierto} other{{count} túneles abiertos}}'**
  String quitTunnels(int count);

  /// No description provided for @readFailedTitle.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido leer'**
  String get readFailedTitle;

  /// No description provided for @readFormat.
  ///
  /// In es, this message translates to:
  /// **'Es de {program}, pero no está como se esperaba (más en «Detalles»).'**
  String readFormat(String program);

  /// No description provided for @readNotRecognized.
  ///
  /// In es, this message translates to:
  /// **'No se reconoce de qué programa es. Elige el que exporta PuTTY (.reg), MobaXterm (.mxtsessions), SecureCRT (.xml) o el config.yaml de Tabby.'**
  String get readNotRecognized;

  /// No description provided for @readOsRelease.
  ///
  /// In es, this message translates to:
  /// **'Leer /etc/os-release'**
  String get readOsRelease;

  /// No description provided for @readOsReleaseEverywhere.
  ///
  /// In es, this message translates to:
  /// **'Leer /etc/os-release en todos los hosts'**
  String get readOsReleaseEverywhere;

  /// No description provided for @readOsReleaseEverywhereHelp.
  ///
  /// In es, this message translates to:
  /// **'Para saber el sistema de los servidores que no lo dicen al conectar. Ejecuta un comando en cada uno; un host o un grupo puede apagarlo. Solo en este equipo.'**
  String get readOsReleaseEverywhereHelp;

  /// No description provided for @readOsReleaseNote.
  ///
  /// In es, this message translates to:
  /// **'Para afinar el sistema; ejecuta un comando en el servidor. Apagado, no se ejecuta nada.'**
  String get readOsReleaseNote;

  /// No description provided for @readOsReleaseOff.
  ///
  /// In es, this message translates to:
  /// **'No'**
  String get readOsReleaseOff;

  /// No description provided for @readOsReleaseOn.
  ///
  /// In es, this message translates to:
  /// **'Sí, al conectar'**
  String get readOsReleaseOn;

  /// No description provided for @readTermius.
  ///
  /// In es, this message translates to:
  /// **'Leer Termius'**
  String get readTermius;

  /// No description provided for @readTermiusKeychain.
  ///
  /// In es, this message translates to:
  /// **'El sistema no dejó usar la clave de Termius del llavero. Vuelve a intentarlo y elige «Permitir».'**
  String get readTermiusKeychain;

  /// No description provided for @readTermiusNoKey.
  ///
  /// In es, this message translates to:
  /// **'La clave de Termius no está en el llavero. Abre Termius una vez en este equipo y vuelve a intentarlo.'**
  String get readTermiusNoKey;

  /// No description provided for @readTermiusNotFound.
  ///
  /// In es, this message translates to:
  /// **'No hay datos de Termius en este equipo.'**
  String get readTermiusNotFound;

  /// No description provided for @readTermiusWrongKey.
  ///
  /// In es, this message translates to:
  /// **'La clave del llavero no abre los datos de Termius; puede que Termius haya cambiado su formato. No se ha importado nada.'**
  String get readTermiusWrongKey;

  /// No description provided for @readUnreadable.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido leer el archivo (más en «Detalles»).'**
  String get readUnreadable;

  /// No description provided for @readingFile.
  ///
  /// In es, this message translates to:
  /// **'Leyendo el archivo…'**
  String get readingFile;

  /// No description provided for @readingProgram.
  ///
  /// In es, this message translates to:
  /// **'Leyendo los datos de {program}…'**
  String readingProgram(String program);

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

  /// No description provided for @recentConnections.
  ///
  /// In es, this message translates to:
  /// **'Conexiones recientes'**
  String get recentConnections;

  /// No description provided for @recentConnectionsHelp.
  ///
  /// In es, this message translates to:
  /// **'Las conexiones que abres se guardan en este equipo (nunca en el vault) para volver a ellas desde la paleta. Los terminales locales no.'**
  String get recentConnectionsHelp;

  /// No description provided for @recentEmptyBody.
  ///
  /// In es, this message translates to:
  /// **'Lo que abras saldrá aquí, con cuándo y cuánto duró, para volver con un clic.'**
  String get recentEmptyBody;

  /// No description provided for @recentEmptyTitle.
  ///
  /// In es, this message translates to:
  /// **'Aún no te has conectado'**
  String get recentEmptyTitle;

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

  /// No description provided for @reimportNote.
  ///
  /// In es, this message translates to:
  /// **'Si vuelves a importar, lo que ya trajiste se queda como está, con tus cambios. Solo entra lo nuevo.'**
  String get reimportNote;

  /// No description provided for @reload.
  ///
  /// In es, this message translates to:
  /// **'Recargar'**
  String get reload;

  /// No description provided for @remoteSentence.
  ///
  /// In es, this message translates to:
  /// **'Lo que se conecte en {host} al puerto {port} llega a {dest} de este equipo.'**
  String remoteSentence(String host, String port, String dest);

  /// No description provided for @remove.
  ///
  /// In es, this message translates to:
  /// **'Quitar'**
  String get remove;

  /// No description provided for @removeCertificate.
  ///
  /// In es, this message translates to:
  /// **'Quitar el certificado'**
  String get removeCertificate;

  /// No description provided for @removeFavorite.
  ///
  /// In es, this message translates to:
  /// **'Quitar de favoritos'**
  String get removeFavorite;

  /// No description provided for @removeKey.
  ///
  /// In es, this message translates to:
  /// **'Quitar la clave'**
  String get removeKey;

  /// No description provided for @removeTag.
  ///
  /// In es, this message translates to:
  /// **'Quitar {tag}'**
  String removeTag(String tag);

  /// No description provided for @removeTheLine.
  ///
  /// In es, this message translates to:
  /// **'Quitar la línea'**
  String get removeTheLine;

  /// No description provided for @rename.
  ///
  /// In es, this message translates to:
  /// **'Renombrar'**
  String get rename;

  /// No description provided for @renameEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Renombrar…'**
  String get renameEllipsis;

  /// No description provided for @renameTab.
  ///
  /// In es, this message translates to:
  /// **'Renombrar…'**
  String get renameTab;

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

  /// No description provided for @renameWorkspace.
  ///
  /// In es, this message translates to:
  /// **'Renombrar el espacio de trabajo'**
  String get renameWorkspace;

  /// No description provided for @reopenTab.
  ///
  /// In es, this message translates to:
  /// **'Reabrir la pestaña cerrada'**
  String get reopenTab;

  /// No description provided for @repeatPassphrase.
  ///
  /// In es, this message translates to:
  /// **'Repítela'**
  String get repeatPassphrase;

  /// No description provided for @reportCopied.
  ///
  /// In es, this message translates to:
  /// **'Copiado. Pégalo en tu informe.'**
  String get reportCopied;

  /// No description provided for @reportCore.
  ///
  /// In es, this message translates to:
  /// **'núcleo'**
  String get reportCore;

  /// No description provided for @reportCounts.
  ///
  /// In es, this message translates to:
  /// **'Hosts: {hosts} · grupos: {groups} · túneles: {tunnels} · identidades: {identities} · snippets: {snippets}'**
  String reportCounts(
    int hosts,
    int groups,
    int tunnels,
    int identities,
    int snippets,
  );

  /// No description provided for @reportCreated.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 host nuevo} other{{count} hosts nuevos}}'**
  String reportCreated(int count);

  /// No description provided for @reportHow.
  ///
  /// In es, this message translates to:
  /// **'Pégalo en la issue junto con qué hacías, qué esperabas y qué pasó, como pide la guía de prueba.'**
  String get reportHow;

  /// No description provided for @reportNotEverything.
  ///
  /// In es, this message translates to:
  /// **'No todo se ha podido traer:'**
  String get reportNotEverything;

  /// No description provided for @reportProblem.
  ///
  /// In es, this message translates to:
  /// **'Informar de un problema'**
  String get reportProblem;

  /// No description provided for @reportProblemEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Informar de un problema…'**
  String get reportProblemEllipsis;

  /// No description provided for @reportProblemHint.
  ///
  /// In es, this message translates to:
  /// **'Copia la versión y el sistema para pegarlos en tu informe.'**
  String get reportProblemHint;

  /// No description provided for @reportSkipped.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 ya estaba importado y no se ha tocado} other{{count} ya estaban importados y no se han tocado}}'**
  String reportSkipped(int count);

  /// No description provided for @reportText.
  ///
  /// In es, this message translates to:
  /// **'texto'**
  String get reportText;

  /// No description provided for @reportTheme.
  ///
  /// In es, this message translates to:
  /// **'Tema'**
  String get reportTheme;

  /// No description provided for @reportTitle.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0{Nada nuevo de {program}} =1{1 host importado de {program}} other{{count} hosts importados de {program}}}'**
  String reportTitle(int count, String program);

  /// No description provided for @reportTunnels.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 túnel nuevo} other{{count} túneles nuevos}}'**
  String reportTunnels(int count);

  /// No description provided for @reportWhat.
  ///
  /// In es, this message translates to:
  /// **'Esto es lo que se copia. No incluye hosts, direcciones, usuarios ni claves.'**
  String get reportWhat;

  /// No description provided for @reportWhere.
  ///
  /// In es, this message translates to:
  /// **'Están en el grupo «~/.ssh/config».'**
  String get reportWhere;

  /// No description provided for @reportWhere2.
  ///
  /// In es, this message translates to:
  /// **'Están en el grupo «{group}» de la barra lateral, con sus subgrupos.'**
  String reportWhere2(String group);

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

  /// No description provided for @retry.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get retry;

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

  /// No description provided for @revealInExplorer.
  ///
  /// In es, this message translates to:
  /// **'Mostrar en el Explorador'**
  String get revealInExplorer;

  /// No description provided for @revealInFinder.
  ///
  /// In es, this message translates to:
  /// **'Mostrar en el Finder'**
  String get revealInFinder;

  /// No description provided for @revealInFolder.
  ///
  /// In es, this message translates to:
  /// **'Mostrar la carpeta'**
  String get revealInFolder;

  /// No description provided for @review.
  ///
  /// In es, this message translates to:
  /// **'Revisar'**
  String get review;

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

  /// No description provided for @runEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Ejecutar…'**
  String get runEllipsis;

  /// No description provided for @runIn.
  ///
  /// In es, this message translates to:
  /// **'Ejecutar en…'**
  String get runIn;

  /// No description provided for @runSnippetBroadcast.
  ///
  /// In es, this message translates to:
  /// **'Va a los {count} paneles que reciben el broadcast'**
  String runSnippetBroadcast(int count);

  /// No description provided for @runSnippetHint.
  ///
  /// In es, this message translates to:
  /// **'Rellena lo que pregunta. No se guarda.'**
  String get runSnippetHint;

  /// No description provided for @runSnippetIn.
  ///
  /// In es, this message translates to:
  /// **'En {where}'**
  String runSnippetIn(String where);

  /// No description provided for @runSnippetTitle.
  ///
  /// In es, this message translates to:
  /// **'Ejecutar «{name}»'**
  String runSnippetTitle(String name);

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

  /// No description provided for @saveAndOpen.
  ///
  /// In es, this message translates to:
  /// **'Guardar y abrir'**
  String get saveAndOpen;

  /// No description provided for @saveAs.
  ///
  /// In es, this message translates to:
  /// **'Guardar como'**
  String get saveAs;

  /// No description provided for @saveAsHost.
  ///
  /// In es, this message translates to:
  /// **'Guardar como host…'**
  String get saveAsHost;

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

  /// No description provided for @saveOpenTabs.
  ///
  /// In es, this message translates to:
  /// **'Guardar las pestañas abiertas…'**
  String get saveOpenTabs;

  /// No description provided for @saveTabsNeedsTabs.
  ///
  /// In es, this message translates to:
  /// **'Abre alguna pestaña para poder guardarla.'**
  String get saveTabsNeedsTabs;

  /// No description provided for @saveWorkspaceIntro.
  ///
  /// In es, this message translates to:
  /// **'Las pestañas de terminal y de archivos abiertas, con sus paneles. Al abrirlo, cada panel se conecta de nuevo.'**
  String get saveWorkspaceIntro;

  /// No description provided for @saveWorkspaceTitle.
  ///
  /// In es, this message translates to:
  /// **'Guardar como espacio de trabajo'**
  String get saveWorkspaceTitle;

  /// No description provided for @savedHost.
  ///
  /// In es, this message translates to:
  /// **'Host guardado'**
  String get savedHost;

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

  /// No description provided for @search.
  ///
  /// In es, this message translates to:
  /// **'Buscar'**
  String get search;

  /// No description provided for @searchHosts.
  ///
  /// In es, this message translates to:
  /// **'Buscar hosts'**
  String get searchHosts;

  /// No description provided for @searchKeys.
  ///
  /// In es, this message translates to:
  /// **'Buscar por nombre, huella o host'**
  String get searchKeys;

  /// No description provided for @searchKnownHosts.
  ///
  /// In es, this message translates to:
  /// **'Buscar un host, una huella…'**
  String get searchKnownHosts;

  /// No description provided for @sectionConnection.
  ///
  /// In es, this message translates to:
  /// **'Conexión'**
  String get sectionConnection;

  /// No description provided for @sectionEnvironment.
  ///
  /// In es, this message translates to:
  /// **'Entorno'**
  String get sectionEnvironment;

  /// No description provided for @sectionGeneral.
  ///
  /// In es, this message translates to:
  /// **'General'**
  String get sectionGeneral;

  /// No description provided for @sectionSystem.
  ///
  /// In es, this message translates to:
  /// **'Sistema'**
  String get sectionSystem;

  /// No description provided for @securityKeyPill.
  ///
  /// In es, this message translates to:
  /// **'Llave de seguridad'**
  String get securityKeyPill;

  /// No description provided for @securityKeyPinBody.
  ///
  /// In es, this message translates to:
  /// **'La clave {key} pide el PIN de su llave.'**
  String securityKeyPinBody(String key);

  /// No description provided for @securityKeyPinOptional.
  ///
  /// In es, this message translates to:
  /// **'PIN de la llave (si tiene)'**
  String get securityKeyPinOptional;

  /// No description provided for @securityKeyPinTitle.
  ///
  /// In es, this message translates to:
  /// **'PIN de la llave de seguridad'**
  String get securityKeyPinTitle;

  /// No description provided for @seenFrom.
  ///
  /// In es, this message translates to:
  /// **'visto desde {host}'**
  String seenFrom(String host);

  /// No description provided for @seenFromHere.
  ///
  /// In es, this message translates to:
  /// **'visto desde este equipo'**
  String get seenFromHere;

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

  /// No description provided for @sendAction.
  ///
  /// In es, this message translates to:
  /// **'Enviar'**
  String get sendAction;

  /// No description provided for @sendToPanes.
  ///
  /// In es, this message translates to:
  /// **'Enviar a {count} paneles'**
  String sendToPanes(int count);

  /// No description provided for @separatePanes.
  ///
  /// In es, this message translates to:
  /// **'Separar los paneles en pestañas'**
  String get separatePanes;

  /// No description provided for @serialBaud.
  ///
  /// In es, this message translates to:
  /// **'Velocidad'**
  String get serialBaud;

  /// No description provided for @serialBaudMissing.
  ///
  /// In es, this message translates to:
  /// **'Pon una velocidad.'**
  String get serialBaudMissing;

  /// No description provided for @serialBaudUnit.
  ///
  /// In es, this message translates to:
  /// **'{baud} baudios'**
  String serialBaudUnit(int baud);

  /// No description provided for @serialDataBits.
  ///
  /// In es, this message translates to:
  /// **'Bits de datos'**
  String get serialDataBits;

  /// No description provided for @serialFlow.
  ///
  /// In es, this message translates to:
  /// **'Control de flujo'**
  String get serialFlow;

  /// No description provided for @serialLine.
  ///
  /// In es, this message translates to:
  /// **'Velocidad y formato'**
  String get serialLine;

  /// No description provided for @serialOpenEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Abrir un puerto serie…'**
  String get serialOpenEllipsis;

  /// No description provided for @serialOpenNote.
  ///
  /// In es, this message translates to:
  /// **'Para la consola de un router o un switch, con su cable: casi siempre 9600 baudios, 8N1.'**
  String get serialOpenNote;

  /// No description provided for @serialOpenTitle.
  ///
  /// In es, this message translates to:
  /// **'Abrir un puerto serie'**
  String get serialOpenTitle;

  /// No description provided for @serialParity.
  ///
  /// In es, this message translates to:
  /// **'Paridad'**
  String get serialParity;

  /// No description provided for @serialPortMissing.
  ///
  /// In es, this message translates to:
  /// **'Elige el puerto.'**
  String get serialPortMissing;

  /// No description provided for @serialPortsAgain.
  ///
  /// In es, this message translates to:
  /// **'Buscar otra vez'**
  String get serialPortsAgain;

  /// No description provided for @serialPortsNone.
  ///
  /// In es, this message translates to:
  /// **'No hay ningún puerto serie conectado.'**
  String get serialPortsNone;

  /// No description provided for @serialPortsTooltip.
  ///
  /// In es, this message translates to:
  /// **'Los puertos de este equipo'**
  String get serialPortsTooltip;

  /// No description provided for @serialSendBreak.
  ///
  /// In es, this message translates to:
  /// **'Enviar un break por el puerto serie'**
  String get serialSendBreak;

  /// No description provided for @serialShort.
  ///
  /// In es, this message translates to:
  /// **'Serie'**
  String get serialShort;

  /// No description provided for @serialStopBits.
  ///
  /// In es, this message translates to:
  /// **'Bits de parada'**
  String get serialStopBits;

  /// No description provided for @serialSummary.
  ///
  /// In es, this message translates to:
  /// **'{baud} baudios, {frame}, {flow}'**
  String serialSummary(int baud, String frame, String flow);

  /// No description provided for @serialSummaryNoFlow.
  ///
  /// In es, this message translates to:
  /// **'sin control de flujo'**
  String get serialSummaryNoFlow;

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

  /// No description provided for @sessionLog.
  ///
  /// In es, this message translates to:
  /// **'Registro de sesión'**
  String get sessionLog;

  /// No description provided for @sessionLogNote.
  ///
  /// In es, this message translates to:
  /// **'Nunca lo que escribes. Se ve y se busca en Registros.'**
  String get sessionLogNote;

  /// No description provided for @sessionLogOff.
  ///
  /// In es, this message translates to:
  /// **'No'**
  String get sessionLogOff;

  /// No description provided for @sessionLogOn.
  ///
  /// In es, this message translates to:
  /// **'Sí, lo que sale en pantalla'**
  String get sessionLogOn;

  /// No description provided for @sessionResumed.
  ///
  /// In es, this message translates to:
  /// **'sesión de tmux recuperada'**
  String get sessionResumed;

  /// No description provided for @setHereHint.
  ///
  /// In es, this message translates to:
  /// **'Un clic lo cambia solo aquí'**
  String get setHereHint;

  /// No description provided for @setHereIdentitySays.
  ///
  /// In es, this message translates to:
  /// **'Cambiado aquí; la identidad dice {value}'**
  String setHereIdentitySays(String value);

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

  /// No description provided for @settingsLogs.
  ///
  /// In es, this message translates to:
  /// **'Registros'**
  String get settingsLogs;

  /// No description provided for @settingsTerminal.
  ///
  /// In es, this message translates to:
  /// **'Terminal'**
  String get settingsTerminal;

  /// No description provided for @settingsWindow.
  ///
  /// In es, this message translates to:
  /// **'Ventana'**
  String get settingsWindow;

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

  /// No description provided for @shiftPrefix.
  ///
  /// In es, this message translates to:
  /// **'Mayús+'**
  String get shiftPrefix;

  /// No description provided for @shortcutAll.
  ///
  /// In es, this message translates to:
  /// **'todos los atajos'**
  String get shortcutAll;

  /// No description provided for @shortcutConnectTyped.
  ///
  /// In es, this message translates to:
  /// **'Conectar a lo escrito, en el inicio'**
  String get shortcutConnectTyped;

  /// No description provided for @shortcutFindNewer.
  ///
  /// In es, this message translates to:
  /// **'Coincidencia siguiente, más abajo'**
  String get shortcutFindNewer;

  /// No description provided for @shortcutFindOlder.
  ///
  /// In es, this message translates to:
  /// **'Coincidencia anterior, más arriba'**
  String get shortcutFindOlder;

  /// No description provided for @shortcutGoToPane.
  ///
  /// In es, this message translates to:
  /// **'Ir al panel en esa dirección'**
  String get shortcutGoToPane;

  /// No description provided for @shortcutGoToTab.
  ///
  /// In es, this message translates to:
  /// **'Ir a la pestaña 1 a 8'**
  String get shortcutGoToTab;

  /// No description provided for @shortcutHosts.
  ///
  /// In es, this message translates to:
  /// **'Todos los hosts, en su página'**
  String get shortcutHosts;

  /// No description provided for @shortcutLastTab.
  ///
  /// In es, this message translates to:
  /// **'Ir a la última pestaña'**
  String get shortcutLastTab;

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

  /// No description provided for @shortcutNextTab.
  ///
  /// In es, this message translates to:
  /// **'Pestaña siguiente'**
  String get shortcutNextTab;

  /// No description provided for @shortcutPalette.
  ///
  /// In es, this message translates to:
  /// **'Buscar en todo: hosts, pestañas y acciones'**
  String get shortcutPalette;

  /// No description provided for @shortcutPermissions.
  ///
  /// In es, this message translates to:
  /// **'Permisos'**
  String get shortcutPermissions;

  /// No description provided for @shortcutPreviousTab.
  ///
  /// In es, this message translates to:
  /// **'Pestaña anterior'**
  String get shortcutPreviousTab;

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

  /// No description provided for @shortcutSidebar.
  ///
  /// In es, this message translates to:
  /// **'barra lateral'**
  String get shortcutSidebar;

  /// No description provided for @shortcutSwitchSide.
  ///
  /// In es, this message translates to:
  /// **'Pasar al otro lado'**
  String get shortcutSwitchSide;

  /// No description provided for @shortcutTextBigger.
  ///
  /// In es, this message translates to:
  /// **'Texto más grande en la pestaña'**
  String get shortcutTextBigger;

  /// No description provided for @shortcutTextReset.
  ///
  /// In es, this message translates to:
  /// **'Tamaño del texto de siempre'**
  String get shortcutTextReset;

  /// No description provided for @shortcutTextSmaller.
  ///
  /// In es, this message translates to:
  /// **'Texto más pequeño en la pestaña'**
  String get shortcutTextSmaller;

  /// No description provided for @shortcutsForms.
  ///
  /// In es, this message translates to:
  /// **'Editores y diálogos'**
  String get shortcutsForms;

  /// No description provided for @shortcutsNone.
  ///
  /// In es, this message translates to:
  /// **'Ningún atajo con «{query}»'**
  String shortcutsNone(String query);

  /// No description provided for @shortcutsPanes.
  ///
  /// In es, this message translates to:
  /// **'Paneles'**
  String get shortcutsPanes;

  /// No description provided for @shortcutsSearch.
  ///
  /// In es, this message translates to:
  /// **'Buscar una acción o una tecla'**
  String get shortcutsSearch;

  /// No description provided for @shortcutsTabs.
  ///
  /// In es, this message translates to:
  /// **'Pestañas'**
  String get shortcutsTabs;

  /// No description provided for @shortcutsTerminal.
  ///
  /// In es, this message translates to:
  /// **'Terminal'**
  String get shortcutsTerminal;

  /// No description provided for @shortcutsTitle.
  ///
  /// In es, this message translates to:
  /// **'Atajos de teclado'**
  String get shortcutsTitle;

  /// No description provided for @shortcutsWindow.
  ///
  /// In es, this message translates to:
  /// **'Ventana'**
  String get shortcutsWindow;

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

  /// No description provided for @showSidebar.
  ///
  /// In es, this message translates to:
  /// **'Abrir la barra lateral'**
  String get showSidebar;

  /// No description provided for @sidebarHelp.
  ///
  /// In es, this message translates to:
  /// **'Se recuerda al cerrar OpenWard. Oculta, se asoma al dejar el ratón en el borde izquierdo de la ventana.'**
  String get sidebarHelp;

  /// No description provided for @sidebarHidden.
  ///
  /// In es, this message translates to:
  /// **'Oculta'**
  String get sidebarHidden;

  /// No description provided for @sidebarOnSession.
  ///
  /// In es, this message translates to:
  /// **'Con un terminal delante'**
  String get sidebarOnSession;

  /// No description provided for @sidebarOnSessionHelp.
  ///
  /// In es, this message translates to:
  /// **'Con un terminal o un SFTP delante, la barra puede plegarse sola. En el inicio y en las páginas vuelve a como esté arriba.'**
  String get sidebarOnSessionHelp;

  /// No description provided for @sidebarOpen.
  ///
  /// In es, this message translates to:
  /// **'Abierta'**
  String get sidebarOpen;

  /// No description provided for @sidebarRail.
  ///
  /// In es, this message translates to:
  /// **'Raíl'**
  String get sidebarRail;

  /// No description provided for @sidebarSearchHint.
  ///
  /// In es, this message translates to:
  /// **'Buscar o conectar…'**
  String get sidebarSearchHint;

  /// No description provided for @sidebarSetting.
  ///
  /// In es, this message translates to:
  /// **'Barra lateral'**
  String get sidebarSetting;

  /// No description provided for @sidebarWidth.
  ///
  /// In es, this message translates to:
  /// **'Ancho de la barra'**
  String get sidebarWidth;

  /// No description provided for @sidebarWidthHelp.
  ///
  /// In es, this message translates to:
  /// **'Arrastra el borde de la barra para cambiarlo, entre 220 y 420 px. Un doble clic en el borde lo restablece.'**
  String get sidebarWidthHelp;

  /// No description provided for @sinceSeconds.
  ///
  /// In es, this message translates to:
  /// **'desde hace {seconds} s'**
  String sinceSeconds(int seconds);

  /// No description provided for @skLocked.
  ///
  /// In es, this message translates to:
  /// **'la llave está bloqueada por demasiados PIN incorrectos: desconéctala y vuelve a conectarla'**
  String get skLocked;

  /// No description provided for @skNoAccess.
  ///
  /// In es, this message translates to:
  /// **'Windows no deja a OpenWard hablar con la llave: usa el agente de OpenSSH de Windows (ssh-add) para las llaves de seguridad'**
  String get skNoAccess;

  /// No description provided for @skNoAccessLinux.
  ///
  /// In es, this message translates to:
  /// **'Linux no deja a OpenWard abrir la llave: falta la regla de udev que da acceso a /dev/hidraw* (la instalan los paquetes libfido2 o u2f-udev)'**
  String get skNoAccessLinux;

  /// No description provided for @skNoKey.
  ///
  /// In es, this message translates to:
  /// **'no hay ninguna llave de seguridad conectada'**
  String get skNoKey;

  /// No description provided for @skNotThisKey.
  ///
  /// In es, this message translates to:
  /// **'la llave conectada no es la de esta clave'**
  String get skNotThisKey;

  /// No description provided for @skNotTouched.
  ///
  /// In es, this message translates to:
  /// **'no se tocó la llave a tiempo'**
  String get skNotTouched;

  /// No description provided for @skOther.
  ///
  /// In es, this message translates to:
  /// **'la llave de seguridad ha fallado (más en «Detalles»)'**
  String get skOther;

  /// No description provided for @skPinRequired.
  ///
  /// In es, this message translates to:
  /// **'la llave pide su PIN'**
  String get skPinRequired;

  /// No description provided for @skTooManyKeys.
  ///
  /// In es, this message translates to:
  /// **'hay más de una llave de seguridad conectada: deja solo la de esta clave'**
  String get skTooManyKeys;

  /// No description provided for @skWrongPin.
  ///
  /// In es, this message translates to:
  /// **'el PIN no es el de la llave'**
  String get skWrongPin;

  /// No description provided for @skipGuide.
  ///
  /// In es, this message translates to:
  /// **'Saltar la guía'**
  String get skipGuide;

  /// No description provided for @snippetDeleted.
  ///
  /// In es, this message translates to:
  /// **'Snippet «{name}» eliminado'**
  String snippetDeleted(String name);

  /// No description provided for @snippetEditorHint.
  ///
  /// In es, this message translates to:
  /// **'Comandos que envías a un terminal; lo que va entre llaves se pregunta.'**
  String get snippetEditorHint;

  /// No description provided for @snippetNeedsCommand.
  ///
  /// In es, this message translates to:
  /// **'Escribe el comando.'**
  String get snippetNeedsCommand;

  /// No description provided for @snippetNeedsName.
  ///
  /// In es, this message translates to:
  /// **'Ponle un nombre.'**
  String get snippetNeedsName;

  /// No description provided for @snippetNoSecrets.
  ///
  /// In es, this message translates to:
  /// **'Se guarda sin secretos, como el resto del vault. Lo que escribas al ejecutarlo no se guarda.'**
  String get snippetNoSecrets;

  /// No description provided for @snippetScriptExample.
  ///
  /// In es, this message translates to:
  /// **'sudo systemctl restart {open}servicio{close}'**
  String snippetScriptExample(String open, String close);

  /// No description provided for @snippetTypeOnlyNote.
  ///
  /// In es, this message translates to:
  /// **'Se deja escrito, sin pulsar Intro.'**
  String get snippetTypeOnlyNote;

  /// No description provided for @snippetWithEnter.
  ///
  /// In es, this message translates to:
  /// **'Con Intro al final.'**
  String get snippetWithEnter;

  /// No description provided for @snippets.
  ///
  /// In es, this message translates to:
  /// **'Snippets'**
  String get snippets;

  /// No description provided for @snippetsCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 snippet} other{{count} snippets}}'**
  String snippetsCount(int count);

  /// No description provided for @snippetsEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Snippets…'**
  String get snippetsEllipsis;

  /// No description provided for @snippetsHowToRun.
  ///
  /// In es, this message translates to:
  /// **'En un terminal: {shortcut} o el botón «Snippets» de la barra de estado. Con broadcast, van a todos los paneles que reciben.'**
  String snippetsHowToRun(String shortcut);

  /// No description provided for @snippetsIntro.
  ///
  /// In es, this message translates to:
  /// **'Comandos guardados que envías a un terminal con un atajo. Lo que va entre {braces} se pregunta al ejecutarlo.'**
  String snippetsIntro(String braces);

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

  /// No description provided for @splitWith.
  ///
  /// In es, this message translates to:
  /// **'Dividir con {name}'**
  String splitWith(String name);

  /// No description provided for @splitWithNote.
  ///
  /// In es, this message translates to:
  /// **'a la derecha del panel activo'**
  String get splitWithNote;

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

  /// No description provided for @stageTouchKey.
  ///
  /// In es, this message translates to:
  /// **'Toca la llave de seguridad ({key})…'**
  String stageTouchKey(String key);

  /// No description provided for @start.
  ///
  /// In es, this message translates to:
  /// **'Empezar'**
  String get start;

  /// No description provided for @startAction.
  ///
  /// In es, this message translates to:
  /// **'Empezar'**
  String get startAction;

  /// No description provided for @startColDuration.
  ///
  /// In es, this message translates to:
  /// **'Duración'**
  String get startColDuration;

  /// No description provided for @startHere.
  ///
  /// In es, this message translates to:
  /// **'Empieza aquí'**
  String get startHere;

  /// No description provided for @startShortcutHosts.
  ///
  /// In es, this message translates to:
  /// **'todos los hosts'**
  String get startShortcutHosts;

  /// No description provided for @startShortcutLocal.
  ///
  /// In es, this message translates to:
  /// **'terminal local'**
  String get startShortcutLocal;

  /// No description provided for @startShortcutNewHost.
  ///
  /// In es, this message translates to:
  /// **'host nuevo'**
  String get startShortcutNewHost;

  /// No description provided for @startShortcutSearch.
  ///
  /// In es, this message translates to:
  /// **'buscar'**
  String get startShortcutSearch;

  /// No description provided for @startTitle.
  ///
  /// In es, this message translates to:
  /// **'Inicio'**
  String get startTitle;

  /// No description provided for @starting.
  ///
  /// In es, this message translates to:
  /// **'Arrancando…'**
  String get starting;

  /// No description provided for @startupElsewhereBody.
  ///
  /// In es, this message translates to:
  /// **'Otro OpenWard tiene abiertos estos datos (otra copia de la app, o una compilación de desarrollo). Ciérralo y vuelve a abrir este; no se ha cambiado nada en {folder}.'**
  String startupElsewhereBody(String folder);

  /// No description provided for @startupErrorBody.
  ///
  /// In es, this message translates to:
  /// **'Puede que los escribiera una versión más nueva de OpenWard, que la carpeta no tenga permisos o que el archivo esté dañado. No se ha borrado ni cambiado nada en {folder}.'**
  String startupErrorBody(String folder);

  /// No description provided for @startupErrorDetails.
  ///
  /// In es, this message translates to:
  /// **'Detalles'**
  String get startupErrorDetails;

  /// No description provided for @startupErrorTitle.
  ///
  /// In es, this message translates to:
  /// **'OpenWard no ha podido abrir sus datos'**
  String get startupErrorTitle;

  /// No description provided for @startupNewerBody.
  ///
  /// In es, this message translates to:
  /// **'Tus datos los guardó una versión más nueva de OpenWard. Vuelve a abrirlos con esa versión: no se ha borrado ni cambiado nada en {folder}.'**
  String startupNewerBody(String folder);

  /// No description provided for @startupQuit.
  ///
  /// In es, this message translates to:
  /// **'Salir'**
  String get startupQuit;

  /// No description provided for @startupShowFolder.
  ///
  /// In es, this message translates to:
  /// **'Mostrar la carpeta de datos'**
  String get startupShowFolder;

  /// No description provided for @state.
  ///
  /// In es, this message translates to:
  /// **'Estado'**
  String get state;

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

  /// No description provided for @statusStalled.
  ///
  /// In es, this message translates to:
  /// **'Sin respuesta · comprobando…'**
  String get statusStalled;

  /// No description provided for @statusUnencrypted.
  ///
  /// In es, this message translates to:
  /// **'Sin cifrar'**
  String get statusUnencrypted;

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

  /// No description provided for @stepTouchKey.
  ///
  /// In es, this message translates to:
  /// **'toca la llave de seguridad…'**
  String get stepTouchKey;

  /// No description provided for @stopAction.
  ///
  /// In es, this message translates to:
  /// **'Detener'**
  String get stopAction;

  /// No description provided for @swapWith.
  ///
  /// In es, this message translates to:
  /// **'Intercambiar con {name}'**
  String swapWith(String name);

  /// No description provided for @systemByBanner.
  ///
  /// In es, this message translates to:
  /// **'Por el banner del servidor:'**
  String get systemByBanner;

  /// No description provided for @systemByOsRelease.
  ///
  /// In es, this message translates to:
  /// **'Por /etc/os-release:'**
  String get systemByOsRelease;

  /// No description provided for @systemDetectAgain.
  ///
  /// In es, this message translates to:
  /// **'Volver a deducirlo al conectar'**
  String get systemDetectAgain;

  /// No description provided for @systemIcon.
  ///
  /// In es, this message translates to:
  /// **'Icono del sistema'**
  String get systemIcon;

  /// No description provided for @systemManual.
  ///
  /// In es, this message translates to:
  /// **'Elegido a mano'**
  String get systemManual;

  /// No description provided for @systemNotTold.
  ///
  /// In es, this message translates to:
  /// **'«{name}» no dice su sistema al conectar.'**
  String systemNotTold(String name);

  /// No description provided for @systemNotYet.
  ///
  /// In es, this message translates to:
  /// **'Se sabrá al conectar, por el banner del servidor.'**
  String get systemNotYet;

  /// No description provided for @systemOnNextConnection.
  ///
  /// In es, this message translates to:
  /// **'Se leerá al conectar a «{name}».'**
  String systemOnNextConnection(String name);

  /// No description provided for @systemStillUnknown.
  ///
  /// In es, this message translates to:
  /// **'«{name}» tampoco lo dice en /etc/os-release.'**
  String systemStillUnknown(String name);

  /// No description provided for @systemTold.
  ///
  /// In es, this message translates to:
  /// **'«{name}» es {system}.'**
  String systemTold(String name, String system);

  /// No description provided for @systemUnknown.
  ///
  /// In es, this message translates to:
  /// **'Desconocido'**
  String get systemUnknown;

  /// No description provided for @systemUnknownYet.
  ///
  /// In es, this message translates to:
  /// **'Aún sin saber'**
  String get systemUnknownYet;

  /// No description provided for @tabMenuHint.
  ///
  /// In es, this message translates to:
  /// **'También puedes arrastrar la pestaña sobre un terminal para dividirlo, o a otro sitio de la barra para ordenarla.'**
  String get tabMenuHint;

  /// No description provided for @tags.
  ///
  /// In es, this message translates to:
  /// **'Etiquetas'**
  String get tags;

  /// No description provided for @telnetUnencrypted.
  ///
  /// In es, this message translates to:
  /// **'Telnet, sin cifrar'**
  String get telnetUnencrypted;

  /// No description provided for @telnetUnencryptedNote.
  ///
  /// In es, this message translates to:
  /// **'Telnet no cifra nada: lo que escribes, contraseñas incluidas, viaja tal cual por la red. Para los equipos que no admiten SSH.'**
  String get telnetUnencryptedNote;

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

  /// No description provided for @terminalCursorLine.
  ///
  /// In es, this message translates to:
  /// **'Línea del cursor'**
  String get terminalCursorLine;

  /// No description provided for @terminalFont.
  ///
  /// In es, this message translates to:
  /// **'Fuente del terminal'**
  String get terminalFont;

  /// No description provided for @terminalMenuHint.
  ///
  /// In es, this message translates to:
  /// **'Arrastra aquí una pestaña o un host para abrirlo en una mitad de este panel.'**
  String get terminalMenuHint;

  /// No description provided for @terminalPadding.
  ///
  /// In es, this message translates to:
  /// **'Margen del terminal'**
  String get terminalPadding;

  /// No description provided for @terminalPaddingHelp.
  ///
  /// In es, this message translates to:
  /// **'Espacio alrededor del texto, en cada panel.'**
  String get terminalPaddingHelp;

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

  /// No description provided for @termiusBrings.
  ///
  /// In es, this message translates to:
  /// **'Se trae'**
  String get termiusBrings;

  /// No description provided for @termiusBringsHosts.
  ///
  /// In es, this message translates to:
  /// **'Hosts y grupos anidados, con sus ajustes'**
  String get termiusBringsHosts;

  /// No description provided for @termiusBringsIdentities.
  ///
  /// In es, this message translates to:
  /// **'Identidades: usuario y clave'**
  String get termiusBringsIdentities;

  /// No description provided for @termiusBringsSnippets.
  ///
  /// In es, this message translates to:
  /// **'Snippets, etiquetas y hosts conocidos'**
  String get termiusBringsSnippets;

  /// No description provided for @termiusBringsTunnels.
  ///
  /// In es, this message translates to:
  /// **'Túneles y proxy'**
  String get termiusBringsTunnels;

  /// No description provided for @termiusIntro.
  ///
  /// In es, this message translates to:
  /// **'Termius guarda tus hosts cifrados en este equipo, con la clave en el llavero. Para leerlos, el sistema te va a pedir permiso: con «Permitir» basta para esta vez.'**
  String get termiusIntro;

  /// No description provided for @termiusLeaves.
  ///
  /// In es, this message translates to:
  /// **'No se trae'**
  String get termiusLeaves;

  /// No description provided for @termiusLeavesChains.
  ///
  /// In es, this message translates to:
  /// **'Cadenas de saltos (host chaining): añádelas a mano'**
  String get termiusLeavesChains;

  /// No description provided for @termiusLeavesKeys.
  ///
  /// In es, this message translates to:
  /// **'Claves privadas: se busca la misma en ~/.ssh, o se guarda allí si lo pides'**
  String get termiusLeavesKeys;

  /// No description provided for @termiusLeavesPasswords.
  ///
  /// In es, this message translates to:
  /// **'Contraseñas y frases de paso'**
  String get termiusLeavesPasswords;

  /// No description provided for @termiusLeavesTelnet.
  ///
  /// In es, this message translates to:
  /// **'Hosts de Telnet o serie; los de Mosh entran como SSH'**
  String get termiusLeavesTelnet;

  /// No description provided for @termiusReadOnly.
  ///
  /// In es, this message translates to:
  /// **'Es una lectura sin cambios: Termius no se modifica y puede seguir abierto.'**
  String get termiusReadOnly;

  /// No description provided for @termiusTitle.
  ///
  /// In es, this message translates to:
  /// **'Leer los datos de Termius'**
  String get termiusTitle;

  /// No description provided for @termiusUnofficial.
  ///
  /// In es, this message translates to:
  /// **'No es una función de Termius: OpenWard entiende su formato, y una versión nueva de Termius puede cambiarlo. Si algo no se entiende, no se importa nada a medias y te lo decimos.'**
  String get termiusUnofficial;

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

  /// No description provided for @theHost.
  ///
  /// In es, this message translates to:
  /// **'el host'**
  String get theHost;

  /// No description provided for @theLocalNetwork.
  ///
  /// In es, this message translates to:
  /// **'Toda la red local'**
  String get theLocalNetwork;

  /// No description provided for @theServerNetwork.
  ///
  /// In es, this message translates to:
  /// **'La red del servidor'**
  String get theServerNetwork;

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

  /// No description provided for @tmuxMissing.
  ///
  /// In es, this message translates to:
  /// **'sin tmux'**
  String get tmuxMissing;

  /// No description provided for @tmuxMissingTip.
  ///
  /// In es, this message translates to:
  /// **'tmux no está en este servidor: el terminal no sobrevive a un corte. Instálalo para tener la sesión persistente.'**
  String get tmuxMissingTip;

  /// No description provided for @tmuxTip.
  ///
  /// In es, this message translates to:
  /// **'El terminal está en tmux en el servidor: sigue tras un corte. La rueda recorre su historial; Mayús y arrastrar selecciona texto.'**
  String get tmuxTip;

  /// No description provided for @toStart.
  ///
  /// In es, this message translates to:
  /// **'Para empezar'**
  String get toStart;

  /// No description provided for @todayAt.
  ///
  /// In es, this message translates to:
  /// **'hoy {time}'**
  String todayAt(String time);

  /// No description provided for @toggleSidebar.
  ///
  /// In es, this message translates to:
  /// **'Plegar o abrir la barra lateral'**
  String get toggleSidebar;

  /// No description provided for @touchKeyNow.
  ///
  /// In es, this message translates to:
  /// **'Toca la llave de seguridad…'**
  String get touchKeyNow;

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

  /// No description provided for @trustedOn.
  ///
  /// In es, this message translates to:
  /// **'confiada el {date}'**
  String trustedOn(String date);

  /// No description provided for @tryAgain.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get tryAgain;

  /// No description provided for @tryAnother.
  ///
  /// In es, this message translates to:
  /// **'Probar otro'**
  String get tryAnother;

  /// No description provided for @tunnelBadAddress.
  ///
  /// In es, this message translates to:
  /// **'Esa dirección no existe en este equipo.'**
  String get tunnelBadAddress;

  /// No description provided for @tunnelClosed.
  ///
  /// In es, this message translates to:
  /// **'Detenido'**
  String get tunnelClosed;

  /// No description provided for @tunnelDeleted.
  ///
  /// In es, this message translates to:
  /// **'Túnel «{name}» eliminado'**
  String tunnelDeleted(String name);

  /// No description provided for @tunnelDidNotOpen.
  ///
  /// In es, this message translates to:
  /// **'No se abrió «{name}» al conectar: {why}'**
  String tunnelDidNotOpen(String name, String why);

  /// No description provided for @tunnelEditorHint.
  ///
  /// In es, this message translates to:
  /// **'Un puerto de este equipo que lleva a un servicio que solo ve el servidor, o al revés.'**
  String get tunnelEditorHint;

  /// No description provided for @tunnelFailed.
  ///
  /// In es, this message translates to:
  /// **'No se abrió'**
  String get tunnelFailed;

  /// No description provided for @tunnelLost.
  ///
  /// In es, this message translates to:
  /// **'Se cortó'**
  String get tunnelLost;

  /// No description provided for @tunnelLostBody.
  ///
  /// In es, this message translates to:
  /// **'Se perdió la conexión con {host}. Vuelve a abrirlo cuando haya conexión.'**
  String tunnelLostBody(String host);

  /// No description provided for @tunnelNeedsDest.
  ///
  /// In es, this message translates to:
  /// **'Falta el destino o su puerto.'**
  String get tunnelNeedsDest;

  /// No description provided for @tunnelNeedsHost.
  ///
  /// In es, this message translates to:
  /// **'Elige el host por el que va.'**
  String get tunnelNeedsHost;

  /// No description provided for @tunnelNeedsName.
  ///
  /// In es, this message translates to:
  /// **'Ponle un nombre.'**
  String get tunnelNeedsName;

  /// No description provided for @tunnelOpen.
  ///
  /// In es, this message translates to:
  /// **'Abierto'**
  String get tunnelOpen;

  /// No description provided for @tunnelOpenWith.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Abierto · 1 conexión} other{Abierto · {count} conexiones}}'**
  String tunnelOpenWith(int count);

  /// No description provided for @tunnelOpening.
  ///
  /// In es, this message translates to:
  /// **'Abriendo…'**
  String get tunnelOpening;

  /// No description provided for @tunnelPortBusy.
  ///
  /// In es, this message translates to:
  /// **'el puerto {port} de este equipo está ocupado.'**
  String tunnelPortBusy(int port);

  /// No description provided for @tunnelRemotePortBusy.
  ///
  /// In es, this message translates to:
  /// **'{host} no abrió el puerto {port} (en uso o no permitido).'**
  String tunnelRemotePortBusy(int port, String host);

  /// No description provided for @tunnelType.
  ///
  /// In es, this message translates to:
  /// **'Tipo'**
  String get tunnelType;

  /// No description provided for @tunnelVia.
  ///
  /// In es, this message translates to:
  /// **'por {host}'**
  String tunnelVia(String host);

  /// No description provided for @tunnels.
  ///
  /// In es, this message translates to:
  /// **'Túneles'**
  String get tunnels;

  /// No description provided for @tunnelsCount.
  ///
  /// In es, this message translates to:
  /// **'{total, plural, =1{1 túnel} other{{total} túneles}} · {open, plural, =1{1 abierto} other{{open} abiertos}}'**
  String tunnelsCount(int total, int open);

  /// No description provided for @tunnelsIntro.
  ///
  /// In es, this message translates to:
  /// **'Reenvíos de puertos guardados, cada uno con un host. Se abren a mano o al conectar al host, por la misma conexión que el terminal.'**
  String get tunnelsIntro;

  /// No description provided for @tunnelsKeepConnection.
  ///
  /// In es, this message translates to:
  /// **'Un túnel abierto mantiene la conexión con su host aunque cierres la pestaña. Se cierra al cerrarlo aquí o al salir de OpenWard.'**
  String get tunnelsKeepConnection;

  /// No description provided for @tunnelsOf.
  ///
  /// In es, this message translates to:
  /// **'Túneles de {host}'**
  String tunnelsOf(String host);

  /// No description provided for @tunnelsOpenCount.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 túnel abierto} other{{count} túneles abiertos}}'**
  String tunnelsOpenCount(int count);

  /// No description provided for @tunnelsStayOpen.
  ///
  /// In es, this message translates to:
  /// **'Siguen abiertos si cierras esta pestaña. Todos en Biblioteca › Túneles.'**
  String get tunnelsStayOpen;

  /// No description provided for @twoNames.
  ///
  /// In es, this message translates to:
  /// **'{a} y {b}'**
  String twoNames(String a, String b);

  /// No description provided for @typeAndFingerprint.
  ///
  /// In es, this message translates to:
  /// **'Tipo y huella'**
  String get typeAndFingerprint;

  /// No description provided for @typeOnly.
  ///
  /// In es, this message translates to:
  /// **'Solo escribe'**
  String get typeOnly;

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

  /// No description provided for @undo.
  ///
  /// In es, this message translates to:
  /// **'Deshacer'**
  String get undo;

  /// No description provided for @unknownKeyType.
  ///
  /// In es, this message translates to:
  /// **'Tipo desconocido'**
  String get unknownKeyType;

  /// No description provided for @unreadableItems.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Un elemento lo guardó una versión más nueva de OpenWard: no se ve aquí, pero sigue en tus datos tal cual.} other{{count} elementos los guardó una versión más nueva de OpenWard: no se ven aquí, pero siguen en tus datos tal cual.}}'**
  String unreadableItems(int count);

  /// No description provided for @upOneLevel.
  ///
  /// In es, this message translates to:
  /// **'Subir un nivel'**
  String get upOneLevel;

  /// No description provided for @updateWithOpenTabs.
  ///
  /// In es, this message translates to:
  /// **'Cambiar por las pestañas abiertas'**
  String get updateWithOpenTabs;

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

  /// No description provided for @useIdentityHint.
  ///
  /// In es, this message translates to:
  /// **'Marca grupos o hosts. Un grupo la pasa a todos sus hosts, también a los que añadas después.'**
  String get useIdentityHint;

  /// No description provided for @useIdentityOn.
  ///
  /// In es, this message translates to:
  /// **'Usar «{name}» en…'**
  String useIdentityOn(String name);

  /// No description provided for @useIdentitySummary.
  ///
  /// In es, this message translates to:
  /// **'{changed, plural, =0{No cambia ningún host} =1{Cambia 1 host} other{Cambian {changed} hosts}} · {using, plural, =0{no la usará ninguno} =1{la usará 1} other{la usarán {using}}}'**
  String useIdentitySummary(int changed, int using);

  /// No description provided for @useOn.
  ///
  /// In es, this message translates to:
  /// **'Usar en…'**
  String get useOn;

  /// No description provided for @usePort.
  ///
  /// In es, this message translates to:
  /// **'Usar el {port}'**
  String usePort(int port);

  /// No description provided for @usedBy.
  ///
  /// In es, this message translates to:
  /// **'La usan'**
  String get usedBy;

  /// No description provided for @usedByNobody.
  ///
  /// In es, this message translates to:
  /// **'Nadie la usa todavía'**
  String get usedByNobody;

  /// No description provided for @usedNotSaved.
  ///
  /// In es, this message translates to:
  /// **'ya te conectaste, sin guardar · {ago}'**
  String usedNotSaved(String ago);

  /// No description provided for @user.
  ///
  /// In es, this message translates to:
  /// **'Usuario'**
  String get user;

  /// No description provided for @usualKeys.
  ///
  /// In es, this message translates to:
  /// **'las habituales'**
  String get usualKeys;

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

  /// No description provided for @verifyRequired.
  ///
  /// In es, this message translates to:
  /// **'Pedir el PIN cada vez que se use'**
  String get verifyRequired;

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

  /// No description provided for @warnDenied.
  ///
  /// In es, this message translates to:
  /// **'No hay permiso para leer {file}.'**
  String warnDenied(String file);

  /// No description provided for @warnFeature.
  ///
  /// In es, this message translates to:
  /// **'{host}: no se ha traído {feature}.'**
  String warnFeature(String host, String feature);

  /// No description provided for @warnFeatureGeneral.
  ///
  /// In es, this message translates to:
  /// **'No se ha traído {feature}.'**
  String warnFeatureGeneral(String feature);

  /// No description provided for @warnHostChain.
  ///
  /// In es, this message translates to:
  /// **'Las cadenas de saltos de Termius no se han traído: añade los saltos a mano en cada host.'**
  String get warnHostChain;

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

  /// No description provided for @warnMosh.
  ///
  /// In es, this message translates to:
  /// **'{host} usaba Mosh: se conectará por SSH.'**
  String warnMosh(String host);

  /// No description provided for @warnPartlyUnreadable.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Un elemento de los datos no se ha podido leer.} other{{count} elementos de los datos no se han podido leer.}}'**
  String warnPartlyUnreadable(int count);

  /// No description provided for @warnProxyCommand.
  ///
  /// In es, this message translates to:
  /// **'{host} usaba un ProxyCommand, que ejecuta un programa en este equipo; no se ha importado para no ejecutar lo que dice el archivo de otro programa. Si confías en él, ponlo en el host a mano: {command}'**
  String warnProxyCommand(String host, String command);

  /// No description provided for @warnShared.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 elemento compartido de un equipo no se puede leer en este ordenador.} other{{count} elementos compartidos de un equipo no se pueden leer en este ordenador.}}'**
  String warnShared(int count);

  /// No description provided for @warnStartupCommand.
  ///
  /// In es, this message translates to:
  /// **'{host} ejecutaba un comando al conectar; OpenWard aún no lo hace solo.'**
  String warnStartupCommand(String host);

  /// No description provided for @warnStricter.
  ///
  /// In es, this message translates to:
  /// **'StrictHostKeyChecking no{at}: se importa como «aceptar nuevas»; una clave que cambia nunca se acepta sin preguntar.'**
  String warnStricter(String at);

  /// No description provided for @warnUnreadable.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido leer {file}.'**
  String warnUnreadable(String file);

  /// No description provided for @warnUnsupported.
  ///
  /// In es, this message translates to:
  /// **'{subject}: no se importa{at}.'**
  String warnUnsupported(String subject, String at);

  /// No description provided for @warnValue.
  ///
  /// In es, this message translates to:
  /// **'{host}: el valor «{value}» de {field} no es válido y no se ha traído.'**
  String warnValue(String host, String field, String value);

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

  /// No description provided for @whatsNew.
  ///
  /// In es, this message translates to:
  /// **'Qué hay de nuevo'**
  String get whatsNew;

  /// No description provided for @whatsNewIntro.
  ///
  /// In es, this message translates to:
  /// **'Todo lo que hacías con tu cliente anterior, ya aquí. Lo verás una vez; está también en Ajustes › General.'**
  String get whatsNewIntro;

  /// No description provided for @whatsNewReport.
  ///
  /// In es, this message translates to:
  /// **'¿Algo no va? Ajustes › General › Informar de un problema copia lo que hace falta para contarlo.'**
  String get whatsNewReport;

  /// No description provided for @whereItIs.
  ///
  /// In es, this message translates to:
  /// **'Dónde está'**
  String get whereItIs;

  /// No description provided for @whoCanUse.
  ///
  /// In es, this message translates to:
  /// **'Quién puede usarlo'**
  String get whoCanUse;

  /// No description provided for @withCertificate.
  ///
  /// In es, this message translates to:
  /// **'con certificado'**
  String get withCertificate;

  /// No description provided for @withEnter.
  ///
  /// In es, this message translates to:
  /// **'Intro al final'**
  String get withEnter;

  /// No description provided for @withPassphrase.
  ///
  /// In es, this message translates to:
  /// **'Con frase de paso'**
  String get withPassphrase;

  /// No description provided for @withoutPassphrase.
  ///
  /// In es, this message translates to:
  /// **'Sin frase de paso'**
  String get withoutPassphrase;

  /// No description provided for @workspaceNumbered.
  ///
  /// In es, this message translates to:
  /// **'Espacio {number}'**
  String workspaceNumbered(int number);

  /// No description provided for @workspaceSaved.
  ///
  /// In es, this message translates to:
  /// **'«{name}» guardado.'**
  String workspaceSaved(String name);

  /// No description provided for @workspaceSessions.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 sesión} other{{count} sesiones}}'**
  String workspaceSessions(int count);

  /// No description provided for @workspaceTabs.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 pestaña} other{{count} pestañas}}'**
  String workspaceTabs(int count);

  /// No description provided for @workspaceUpdated.
  ///
  /// In es, this message translates to:
  /// **'«{name}» tiene ahora las pestañas abiertas.'**
  String workspaceUpdated(String name);

  /// No description provided for @workspaces.
  ///
  /// In es, this message translates to:
  /// **'Espacios de trabajo'**
  String get workspaces;

  /// No description provided for @workspacesIntro.
  ///
  /// In es, this message translates to:
  /// **'Pestañas y paneles guardados con un nombre, para abrirlos otra vez juntos. Se guarda a qué se conecta cada panel, nunca lo que mostraba.'**
  String get workspacesIntro;

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

  /// No description provided for @wrongPin.
  ///
  /// In es, this message translates to:
  /// **'El PIN no es el de la llave.'**
  String get wrongPin;

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
