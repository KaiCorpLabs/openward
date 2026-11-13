// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get about => 'Acerca de';

  @override
  String aboutVersion(String version) {
    return 'OpenWard $version';
  }

  @override
  String get accessibility => 'Accesibilidad';

  @override
  String get add => 'Añadir';

  @override
  String get addCertificate => '+ Añadir certificado';

  @override
  String get addFavorite => 'Añadir a favoritos';

  @override
  String get addKeyEllipsis => 'Añadir clave…';

  @override
  String get addSavedHost => 'Añadir un host guardado';

  @override
  String get addTag => 'Añadir';

  @override
  String get address => 'Dirección';

  @override
  String get addressHint => 'servidor.example.com o 10.0.0.5';

  @override
  String get advanced => 'Avanzado';

  @override
  String get advancedList =>
      'proxy, claves del host, sesión persistente, Mosh, terminal, snippet al conectar, comprobación y agente';

  @override
  String get advancedListSerial =>
      'terminal, snippet al conectar y registro de sesión';

  @override
  String get advancedListTelnet =>
      'proxy, terminal, snippet al conectar, registro de sesión y tiempo para conectar';

  @override
  String advancedSetHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cambiados aquí',
      one: '1 cambiado aquí',
    );
    return '$_temp0';
  }

  @override
  String get agent => 'Agente SSH';

  @override
  String get agentNone => 'Ninguno';

  @override
  String get agentOtherSocket => 'Otro socket';

  @override
  String get agentShort => 'Agente';

  @override
  String get agentSocket => 'Otro socket…';

  @override
  String get agentSystem => 'El del sistema';

  @override
  String agoDays(int count) {
    return 'hace $count d';
  }

  @override
  String agoHours(int count) {
    return 'hace $count h';
  }

  @override
  String agoMinutes(int count) {
    return 'hace $count min';
  }

  @override
  String get agoNow => 'ahora';

  @override
  String allCount(int count) {
    return 'Todas · $count';
  }

  @override
  String get alreadyImported => 'ya importado';

  @override
  String get alreadyUses => 'Ya la usa';

  @override
  String get alsoOnThisComputer => 'También en este equipo';

  @override
  String announceClosed(String name) {
    return '$name: desconectado';
  }

  @override
  String announceConnected(String name) {
    return '$name: conectado';
  }

  @override
  String announceFailed(String name, String why) {
    return '$name: no se pudo conectar. $why';
  }

  @override
  String announcePrompt(String name) {
    return '$name pregunta algo antes de seguir';
  }

  @override
  String announceReconnecting(String name) {
    return '$name: se cortó, reconectando';
  }

  @override
  String announceTunnelFailed(String name, String why) {
    return 'El túnel «$name» no se abrió: $why';
  }

  @override
  String announceTunnelLost(String name) {
    return 'Se cortó el túnel «$name»';
  }

  @override
  String announceTunnelOpen(String name, int port) {
    return 'Túnel «$name» abierto en el puerto $port';
  }

  @override
  String get anyDestination => 'Cualquier destino';

  @override
  String get appearanceStepBody =>
      'Puedes cambiarlo cuando quieras en Ajustes.';

  @override
  String get appearanceStepTitle => '¿Cómo la quieres ver?';

  @override
  String get apply => 'Aplicar';

  @override
  String get asSystem => 'Como el sistema';

  @override
  String get asTyped => 'tal cual, sin guardarlo';

  @override
  String get askedWhenRun => 'Se pregunta al ejecutarlo';

  @override
  String get askedWhenRunHint => 'Sale de lo que escribes entre llaves.';

  @override
  String get asks => 'Pregunta';

  @override
  String asksNothing(String example) {
    return 'No pregunta nada. Escribe $example donde quieras que pregunte.';
  }

  @override
  String get autocomplete => 'Sugerir mientras escribes';

  @override
  String get autocompleteHelp =>
      'En gris, lo que sigue: del historial de este host, de los snippets y de unos comandos comunes. → o Fin lo acepta. Todo en este equipo, sin red; nada en los editores ni cuando se pide una contraseña.';

  @override
  String get autocompleteNeedsHistory =>
      'Necesita el historial de comandos (Ajustes › Registros).';

  @override
  String awayFor(String time) {
    return '$time fuera';
  }

  @override
  String get back => 'Atrás';

  @override
  String backAgain(String host) {
    return 'Conectado de nuevo a $host';
  }

  @override
  String get backspaceControlH => 'Control-H (^H)';

  @override
  String get backspaceDelete => 'DEL (^?), el de hoy';

  @override
  String get backspaceLabel => 'Retroceso';

  @override
  String get backspaceNote =>
      'Si al borrar el servidor escribe ^? o ^H en vez de borrar, cambia este.';

  @override
  String get badgeChanges => 'cambia';

  @override
  String get badgeLeaves => 'la deja';

  @override
  String get badgeNew => 'nueva';

  @override
  String get bellFlash => 'Destello con la campana';

  @override
  String get bellFlashHelp =>
      'Cuando un programa hace sonar la campana. Si la pestaña no está delante, se marca igualmente.';

  @override
  String get bellRang => 'Ha sonado la campana';

  @override
  String get bracesWord => 'llaves';

  @override
  String bringsTunnels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'trae $count túneles',
      one: 'trae 1 túnel',
    );
    return '$_temp0';
  }

  @override
  String broadcastBanner(int count, int total, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Broadcast: lo que escribas va a $count de $total paneles ($names).',
      one: 'Broadcast: lo que escribas va a 1 de $total paneles ($names).',
    );
    return '$_temp0';
  }

  @override
  String broadcastExit(String keys) {
    return 'Salir $keys';
  }

  @override
  String get broadcastOff => 'Apagar el broadcast';

  @override
  String get broadcastOn => 'Broadcast en esta pestaña';

  @override
  String get broadcastPasteAlways =>
      'Con broadcast, pegar siempre lo pregunta, aunque sea una línea.';

  @override
  String broadcastPasteBody(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Va a $names. Son $count líneas, y cada una puede ejecutarse al llegar.',
      one: 'Va a $names. Es 1 línea.',
    );
    return '$_temp0';
  }

  @override
  String broadcastPasteTitle(int total) {
    return '¿Pegar en $total paneles a la vez?';
  }

  @override
  String broadcastStatus(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Broadcast · $count paneles',
      one: 'Broadcast · 1 panel',
    );
    return '$_temp0';
  }

  @override
  String get bySsh => 'por SSH';

  @override
  String get cancel => 'Cancelar';

  @override
  String cancelThese(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'No copiar estos $count',
      one: 'No copiar este',
    );
    return '$_temp0';
  }

  @override
  String get cancelled => 'Cancelado.';

  @override
  String cannotConnect(String label) {
    return 'No se ha podido conectar con $label';
  }

  @override
  String certExpiredOn(String date) {
    return 'caducó el $date';
  }

  @override
  String certExpiresIn(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days días',
      one: '1 día',
    );
    return 'caduca en $_temp0';
  }

  @override
  String get certForever => 'sin caducidad';

  @override
  String get certNextToKey =>
      'Junto a la clave (-cert.pub): se usa sin añadirlo.';

  @override
  String get certNoAuthority =>
      'ninguna @cert-authority de known_hosts cubre este host';

  @override
  String get certNotForHost => 'no se emitió para este nombre';

  @override
  String get certNotHost => 'no es un certificado de host';

  @override
  String get certOutOfDate => 'ha caducado o aún no es válido';

  @override
  String certUntil(String date) {
    return 'hasta el $date';
  }

  @override
  String get certUntrusted => 'no lo firma una autoridad de confianza';

  @override
  String get certificate => 'certificado';

  @override
  String get certificateExpired => 'certificado caducado';

  @override
  String get certificateTitle => 'Certificado';

  @override
  String get change => 'Cambiar';

  @override
  String get changedMeanwhile =>
      'Otro cambio ha llegado antes: cierra y vuelve a abrir el editor.';

  @override
  String checkNotImported(String label, String protocol) {
    return '$label usa $protocol y no se ha importado.';
  }

  @override
  String checkTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Revisa $count cosas',
      one: 'Revisa 1 cosa',
    );
    return '$_temp0';
  }

  @override
  String checkWithoutKey(String label) {
    return '«$label» se ha quedado sin clave: la suya no está en ~/.ssh.';
  }

  @override
  String get checkedFingerprint => 'He comprobado la huella nueva';

  @override
  String get checking => 'comprobando…';

  @override
  String get choiceKeepBoth => 'Mantener los dos';

  @override
  String get choiceNewer => 'Solo si el mío es más nuevo';

  @override
  String get choiceReplace => 'Reemplazar';

  @override
  String get choiceSkip => 'Saltar';

  @override
  String get chooseExportedFile => 'Elige el archivo exportado';

  @override
  String get chooseFile => 'Elegir…';

  @override
  String get cipher => 'Cifrado';

  @override
  String get clear => 'Quitar';

  @override
  String get clearAction => 'Borrar';

  @override
  String get clearFilter => 'Quitar el filtro';

  @override
  String get clearFinished => 'Quitar las terminadas';

  @override
  String clearHistory(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Borrar $count comandos',
      one: 'Borrar 1 comando',
      zero: 'Borrar el historial',
    );
    return '$_temp0';
  }

  @override
  String get clearHistoryBody =>
      'Los comandos que la paleta recuerda se olvidan, en todos los hosts.';

  @override
  String get clearHistoryTitle => '¿Borrar el historial de comandos?';

  @override
  String clearRecent(int count) {
    return 'Borrar ($count)';
  }

  @override
  String get clearRecentBody =>
      'La lista de la página de inicio y de la paleta queda vacía. Los hosts guardados no cambian.';

  @override
  String get clearRecentTitle => '¿Borrar las conexiones recientes?';

  @override
  String get clearScrollback => 'Limpiar el búfer';

  @override
  String get clearSelection => 'Quitar la selección';

  @override
  String get close => 'Cerrar';

  @override
  String get closeAction => 'Cerrar';

  @override
  String closeMarkedMany(int count) {
    return '¿Cerrar $count sesiones conectadas?';
  }

  @override
  String closeMarkedManyBody(String names) {
    return 'Son de entornos marcados: $names.';
  }

  @override
  String closeMarkedOne(String label) {
    return '¿Cerrar «$label»?';
  }

  @override
  String closeMarkedOneBody(String env) {
    return 'Está conectada a un host de $env: lo que esté en marcha en ella se corta.';
  }

  @override
  String get closeOtherTabs => 'Cerrar las demás';

  @override
  String get closePane => 'Cerrar el panel';

  @override
  String get closeTab => 'Cerrar la pestaña';

  @override
  String closeTabs(int count) {
    return 'Cerrar las $count';
  }

  @override
  String get closeTheTab => 'Cerrar la pestaña';

  @override
  String get colModified => 'Modificado';

  @override
  String get colName => 'Nombre';

  @override
  String get colPermissions => 'Permisos';

  @override
  String get colSize => 'Tamaño';

  @override
  String get collapse => 'Plegar';

  @override
  String get colorBlue => 'Azul';

  @override
  String get colorBrightBlue => 'Azul claro';

  @override
  String get colorBrightCyan => 'Cian claro';

  @override
  String get colorBrightGreen => 'Verde claro';

  @override
  String get colorBrightMagenta => 'Magenta claro';

  @override
  String get colorBrightRed => 'Rojo claro';

  @override
  String get colorBrightYellow => 'Amarillo claro';

  @override
  String get colorCyan => 'Cian';

  @override
  String get colorGray => 'Gris';

  @override
  String get colorGreen => 'Verde';

  @override
  String get colorMagenta => 'Magenta';

  @override
  String get colorOrange => 'Naranja';

  @override
  String get colorPink => 'Rosa';

  @override
  String get colorRed => 'Rojo';

  @override
  String get colorViolet => 'Violeta';

  @override
  String get colorYellow => 'Amarillo';

  @override
  String comebackLine(String time, String away) {
    return 'conectado de nuevo a las $time · estuvo fuera $away · terminal nuevo';
  }

  @override
  String get comingFromOther => '¿Vienes de PuTTY, MobaXterm o SecureCRT?';

  @override
  String get command => 'Comando';

  @override
  String commandHint(String open, String escaped) {
    return 'Cada línea se envía como si la escribieras. Para escribir $open tal cual, pon $escaped.';
  }

  @override
  String get commandHistory => 'Historial de comandos';

  @override
  String commandHistoryHelp(String keys) {
    return 'Lo que ejecutas en los terminales se guarda en este equipo (nunca en el vault) para buscarlo y repetirlo con $keys. Nunca se guarda lo que la pantalla no muestra, como una contraseña, ni lo que empieza por un espacio.';
  }

  @override
  String get commandPalette => 'Paleta de comandos';

  @override
  String get conflictChoose => '. Elige qué hacer con cada uno:';

  @override
  String get conflictFile => 'Fichero';

  @override
  String get conflictFolder => 'carpeta';

  @override
  String get conflictIn => 'En ';

  @override
  String get conflictMerge => 'las dos carpetas se juntan';

  @override
  String conflictRest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '. Los otros $count se copian ya. Elige qué hacer con cada uno:',
      one: '. El otro se copia ya. Elige qué hacer con cada uno:',
    );
    return '$_temp0';
  }

  @override
  String get conflictSame => 'igual tamaño y fecha';

  @override
  String conflictTheirs(String where) {
    return 'En $where';
  }

  @override
  String conflictTheirsNewer(String where) {
    return 'el de $where es más nuevo';
  }

  @override
  String conflictTitle(int count, int total, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count de los $total ya existen en $where',
      one: '1 de los $total ya existe en $where',
    );
    return '$_temp0';
  }

  @override
  String conflictTitleOne(String where) {
    return 'Ya existe en $where';
  }

  @override
  String get conflictWhat => 'Qué hacer';

  @override
  String get conflictYours => 'El tuyo';

  @override
  String get conflictYoursNewer => 'el tuyo es más nuevo';

  @override
  String get connect => 'Conectar';

  @override
  String connectTimeoutAfter(int seconds) {
    return 'Se rinde a los $seconds s sin respuesta';
  }

  @override
  String get connectTimeoutLabel => 'Tiempo para conectar';

  @override
  String connectToAddress(String address) {
    return 'Conectar a $address';
  }

  @override
  String get connectingEllipsis => 'Conectando…';

  @override
  String connectingTo(String label) {
    return 'Conectando con $label';
  }

  @override
  String get connectionDetails => 'Detalles de la conexión';

  @override
  String get connectionHint =>
      'Lo que no cambies aquí se hereda. Manda lo del host, luego su identidad, luego sus grupos y, al final, los valores por defecto.';

  @override
  String connectionLost(String label, String why) {
    return 'Se perdió la conexión con $label$why.';
  }

  @override
  String connectionLostTitle(String host) {
    return 'Se perdió la conexión con $host';
  }

  @override
  String get continueAction => 'Seguir';

  @override
  String get continueLabel => 'Continuar';

  @override
  String contrastFails(String ratio) {
    return 'Contraste del texto $ratio:1. No llega a AA (4,5:1).';
  }

  @override
  String contrastPasses(String ratio) {
    return 'Contraste del texto $ratio:1. Cumple AA.';
  }

  @override
  String contrastWarning(String ratio) {
    return 'Con esta combinación, parte del texto no llega al contraste recomendado (queda en $ratio:1).';
  }

  @override
  String get copy => 'Copiar';

  @override
  String get copyAction => 'Copiar';

  @override
  String get copyAddress => 'Copiar dirección';

  @override
  String get copyFingerprint => 'Copiar la huella';

  @override
  String copyOfName(String name) {
    return '$name (copia)';
  }

  @override
  String get copyOnSelect => 'Copiar al seleccionar';

  @override
  String get copyOnSelectHelp =>
      'Lo que seleccionas con el ratón va al portapapeles, sin pulsar copiar.';

  @override
  String get copyPath => 'Copiar la ruta';

  @override
  String get copyPublicKey => 'Copiar la clave pública';

  @override
  String get copyReport => 'Copiar el informe';

  @override
  String get create => 'Crear';

  @override
  String get csvSpreadsheet => 'CSV (hoja de cálculo)';

  @override
  String get ctrlShiftPrefix => 'Ctrl+Mayús+';

  @override
  String get currentPassphrase => 'Frase de paso actual';

  @override
  String get cursor => 'Cursor';

  @override
  String get cursorBar => 'Barra';

  @override
  String get cursorBlink => 'Cursor parpadeante';

  @override
  String get cursorBlock => 'Bloque';

  @override
  String get cursorHelp => 'Mientras el programa no pida otro.';

  @override
  String get cursorUnderline => 'Línea';

  @override
  String customize(String name) {
    return 'Personalizar $name';
  }

  @override
  String get customizeHint =>
      'Cambia una capa y el resto se queda igual. Los cambios son solo de este tema.';

  @override
  String get defaultKeys =>
      '~/.ssh/id_ed25519, id_ecdsa, id_rsa (las habituales)';

  @override
  String get defaultValueOptional => 'Valor por defecto (opcional)';

  @override
  String get delete => 'Eliminar';

  @override
  String get deleteEllipsis => 'Eliminar…';

  @override
  String deleteFailed(String error) {
    return 'No se ha podido eliminar: $error';
  }

  @override
  String get deleteGroup => 'Eliminar grupo…';

  @override
  String get deleteGroupBody => 'Lo que contiene pasa a su grupo padre.';

  @override
  String deleteGroupTitle(String name) {
    return '¿Eliminar el grupo «$name»?';
  }

  @override
  String get deleteHostBody =>
      'Desaparece de la lista. Esto no se puede deshacer.';

  @override
  String deleteHostTitle(String name) {
    return '¿Eliminar el host «$name»?';
  }

  @override
  String deleteIdentityBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Los $count hosts que la usan volverán a heredar el usuario y las claves de sus grupos.',
      one: 'El host que la usa volverá a heredar el usuario y las claves de su grupo.',
    );
    return '$_temp0';
  }

  @override
  String deleteIdentityTitle(String name) {
    return '¿Eliminar «$name»?';
  }

  @override
  String get deleteIdentityUnused =>
      'Nadie la usa. Las claves siguen en su sitio: solo se borra la identidad.';

  @override
  String deleteKeyBody(String path) {
    return 'Se borran $path y su .pub de este equipo. No se puede deshacer: si no tienes otra copia, no podrás volver a entrar con ella.';
  }

  @override
  String deleteKeyTitle(String name) {
    return '¿Eliminar $name?';
  }

  @override
  String deleteKeyUsed(String who) {
    return 'La usan $who: seguirán nombrándola y no podrán entrar con ella.';
  }

  @override
  String get deleteLocalBody =>
      'Se eliminan de este equipo sin pasar por la papelera: no se puede deshacer.';

  @override
  String deleteMany(int count) {
    return '¿Eliminar $count elementos?';
  }

  @override
  String deleteOne(String name) {
    return '¿Eliminar $name?';
  }

  @override
  String deleteRemoteBody(String host) {
    return 'Se eliminan en $host. En el servidor no hay papelera: no se puede deshacer.';
  }

  @override
  String get deleteWorkspaceBody =>
      'Solo se elimina la distribución guardada: los hosts, y lo que esté abierto, se quedan.';

  @override
  String deleteWorkspaceTitle(String name) {
    return '¿Eliminar «$name»?';
  }

  @override
  String get deletedHost => '(host eliminado)';

  @override
  String get deletedIdentity => '(identidad eliminada)';

  @override
  String get destination => 'Destino';

  @override
  String get details => 'Detalles';

  @override
  String get discardChanges => 'Descartar';

  @override
  String get discardChangesBody =>
      'Lo que has cambiado en este panel no se ha guardado.';

  @override
  String get discardChangesTitle => '¿Descartar los cambios?';

  @override
  String get dividerHint =>
      'Arrastra para cambiar el tamaño · doble clic: mitad y mitad';

  @override
  String get dontTrust => 'No confiar';

  @override
  String get download => 'Descarga';

  @override
  String get downloadArrow => '← Descargar';

  @override
  String downloadTo(String path) {
    return 'Descargar a $path';
  }

  @override
  String get dragPaneHint =>
      'Arrastra para mover el panel: a otro panel o a la barra de pestañas';

  @override
  String get dragToOrder => 'arrastra para ordenar';

  @override
  String dropAbove(String pane) {
    return 'encima de $pane';
  }

  @override
  String get dropAskFirst =>
      'Si alguno ya existe, te preguntamos antes de tocarlo.';

  @override
  String dropBelow(String pane) {
    return 'debajo de $pane';
  }

  @override
  String get dropBottom => 'abajo';

  @override
  String get dropHereToMove => 'Suéltalo para moverlo aquí';

  @override
  String dropHostNewTab(String name) {
    return 'Soltar aquí: abrir $name en una pestaña nueva';
  }

  @override
  String get dropLeft => 'a la izquierda';

  @override
  String dropLeftOf(String pane) {
    return 'a la izquierda de $pane';
  }

  @override
  String dropMove(String name, String where) {
    return 'Soltar: $name $where';
  }

  @override
  String dropNewTab(String name) {
    return 'Soltar aquí: $name en una pestaña nueva';
  }

  @override
  String dropOpenHost(String name, String where) {
    return 'Soltar: abrir $name $where';
  }

  @override
  String get dropRight => 'a la derecha';

  @override
  String dropRightOf(String pane) {
    return 'a la derecha de $pane';
  }

  @override
  String dropSplitAround(String name, String where, String other) {
    return 'Soltar: $name $where; $other, un panel nuevo';
  }

  @override
  String dropTabLast(String name) {
    return 'Soltar aquí: $name al final';
  }

  @override
  String get dropToDownload => 'Suelta para descargar aquí';

  @override
  String get dropToImport =>
      'O arrastra aquí el archivo o la carpeta: se reconoce solo.';

  @override
  String get dropToUpload => 'Suelta para subir aquí';

  @override
  String get dropTop => 'arriba';

  @override
  String get duplicate => 'Duplicar';

  @override
  String get duplicateTab => 'Duplicar';

  @override
  String durationHours(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String durationMinSec(int minutes, int seconds) {
    return '$minutes min $seconds s';
  }

  @override
  String durationMinutes(int count) {
    return '$count min';
  }

  @override
  String durationSec(int seconds) {
    return '$seconds s';
  }

  @override
  String get durationUnderMinute => 'menos de 1 min';

  @override
  String dynamicSentence(String here, String host) {
    return 'Usa $here como proxy SOCKS5: las conexiones salen de $host.';
  }

  @override
  String get editEllipsis => 'Editar…';

  @override
  String get editGroup => 'Editar grupo…';

  @override
  String get editGroupTitle => 'Editar grupo';

  @override
  String get editHostTitle => 'Editar host';

  @override
  String get editIdentity => 'Editar identidad';

  @override
  String get editSnippet => 'Editar snippet';

  @override
  String get editTheIdentity => 'Editar la identidad';

  @override
  String get editTunnel => 'Editar túnel';

  @override
  String get emptyFolder => 'Esta carpeta está vacía';

  @override
  String get emptyPane => 'panel vacío';

  @override
  String get encodingLabel => 'Codificación';

  @override
  String get encodingNote =>
      'Para equipos y sistemas antiguos que no escriben en UTF-8: si salen letras raras en vez de tildes o líneas, prueba Latin-1 o CP437.';

  @override
  String get encodingNoteMosh =>
      'Para equipos y sistemas antiguos que no escriben en UTF-8: si salen letras raras en vez de tildes o líneas, prueba Latin-1 o CP437. Por Mosh siempre es UTF-8.';

  @override
  String get envColor => 'Color';

  @override
  String get envDialogTitle => 'Otro entorno';

  @override
  String get envHint =>
      'Marca las pestañas y los terminales de estos hosts con un color y un nombre corto, para no confundir un servidor con otro.';

  @override
  String envInheritors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Lo heredan los $count hosts del grupo y sus subgrupos; cada host puede cambiarlo.',
      one: 'Lo hereda el host del grupo; puede cambiarlo.',
    );
    return '$_temp0';
  }

  @override
  String get envName => 'Nombre';

  @override
  String get envNeedsName => 'Ponle un nombre al entorno.';

  @override
  String get envNone => 'Ninguno';

  @override
  String get envNoneNote => 'sin marca';

  @override
  String get envOther => 'Otro, con su nombre y color…';

  @override
  String get envPersonal => 'Personal';

  @override
  String get envPersonalShort => 'casa';

  @override
  String envPreview(String name) {
    return 'Vista previa: una pestaña y un terminal marcados como $name';
  }

  @override
  String get envPreviewHost => 'web-1';

  @override
  String get envProduction => 'Producción';

  @override
  String get envProductionShort => 'prod';

  @override
  String get envShort => 'Nombre corto';

  @override
  String get envShortHelp => 'En las pestañas y en la barra lateral';

  @override
  String get envStaging => 'Preproducción';

  @override
  String get envStagingShort => 'pre';

  @override
  String get envTesting => 'Pruebas';

  @override
  String get envTestingShort => 'pruebas';

  @override
  String get envUse => 'Usar';

  @override
  String get environment => 'Entorno';

  @override
  String get equalizePanes => 'Igualar tamaños';

  @override
  String get errConflict => 'ha cambiado mientras tanto';

  @override
  String get errCycle => 'un grupo no puede estar dentro de sí mismo';

  @override
  String get errFileChanged => 'el archivo ha cambiado mientras tanto';

  @override
  String get errInUse => 'otros hosts saltan por él';

  @override
  String get errInternal =>
      'algo ha fallado dentro de OpenWard (más en «Detalles»)';

  @override
  String get errInvalid => 'lo que dice no encaja';

  @override
  String get errNewerFormat =>
      'tus datos los escribió una versión más nueva de OpenWard';

  @override
  String get errNotFound => 'ya no existe';

  @override
  String get errOpenElsewhere => 'otro OpenWard tiene abiertos estos datos';

  @override
  String get errStorage => 'el disco no lo ha aceptado';

  @override
  String get errorDetailsHint =>
      'En inglés, tal como lo dice el núcleo: cópialo si nos informas del problema.';

  @override
  String get errorDetailsTitle => 'Detalles del error';

  @override
  String get exampleVariable => 'nombre';

  @override
  String get expand => 'Desplegar';

  @override
  String get exportEllipsis => 'Exportar…';

  @override
  String failureAuth(String user, String label) {
    return '$user@$label no ha podido autenticarse.';
  }

  @override
  String failureAuthCertExpired(String user, String host, String path) {
    return 'No se pudo entrar como $user en $host: el certificado $path ha caducado; pide uno nuevo.';
  }

  @override
  String failureAuthMethods(String user, String label, String methods) {
    return '$user@$label no ha podido autenticarse (el servidor acepta: $methods).';
  }

  @override
  String failureAuthSecurityKey(String user, String host, String why) {
    return 'No se pudo entrar como $user en $host: $why.';
  }

  @override
  String failureBadCertificate(String label, String reason) {
    return 'El certificado de $label no es válido: $reason.';
  }

  @override
  String failureHostKeyChanged(String label, String fingerprint) {
    return 'La clave de $label ha cambiado (ahora $fingerprint). Puede ser un ataque: no se ha conectado.';
  }

  @override
  String failureHostKeyRejected(String label) {
    return 'No se ha confiado en la clave de $label.';
  }

  @override
  String failureHostKeyRevoked(String label, String fingerprint) {
    return '$label usa una clave revocada ($fingerprint): se rechaza siempre. Si es un error, quítala de la lista de hosts conocidos.';
  }

  @override
  String failureNoSftp(String label) {
    return '$label no tiene SFTP: al servidor le falta sftp-server.';
  }

  @override
  String get failureOther => 'Algo ha fallado (más en «Detalles»).';

  @override
  String failureSerialBusy(String port) {
    return '$port está abierto en otro programa, o en otra pestaña.';
  }

  @override
  String failureSerialDenied(String port) {
    return 'Tu usuario no puede abrir $port.';
  }

  @override
  String failureSerialDeniedLinux(String port) {
    return 'Tu usuario no puede abrir $port: añádelo al grupo dialout (sudo usermod -aG dialout, con tu usuario) y vuelve a entrar en la sesión.';
  }

  @override
  String failureSerialGone(String port) {
    return 'Se ha desconectado $port: ¿se ha soltado el cable?';
  }

  @override
  String failureSerialMissing(String port) {
    return 'No hay ningún puerto $port: ¿está conectado el cable?';
  }

  @override
  String failureSerialOther(String port) {
    return 'No se ha podido abrir $port (más en «Detalles»).';
  }

  @override
  String failureSerialSettings(String port) {
    return '$port no admite esa velocidad o ese formato.';
  }

  @override
  String get favorite => 'Favorito';

  @override
  String get favoriteLower => 'favorito';

  @override
  String get favoriteNote => 'arriba en la barra, en el raíl y en el inicio';

  @override
  String get favorites => 'Favoritos';

  @override
  String get favoritesEmpty =>
      'Marca con ★ los hosts que más usas (en su página, al pasar el ratón, o en su editor) y aparecerán aquí, en el orden que les des.';

  @override
  String get favoritesEmptyShort => 'Marca con ★ en Hosts los que más uses.';

  @override
  String featureFirewall(String name) {
    return 'el firewall «$name» de SecureCRT';
  }

  @override
  String get featureHardwareKey => 'una llave de seguridad';

  @override
  String get featureIncompleteProxy => 'un proxy sin dirección o sin puerto';

  @override
  String get featureJumpNotSsh => 'un salto por un perfil que no es SSH';

  @override
  String featureJumpThrough(String target) {
    return 'un salto por $target, que no está';
  }

  @override
  String get featureMobaCredential => 'una credencial guardada en MobaXterm';

  @override
  String featureProxy(String kind) {
    return 'un proxy $kind';
  }

  @override
  String get featureSecureCrtGlobalKey => 'la clave global de SecureCRT';

  @override
  String get featureSocks4 => 'un proxy SOCKS4';

  @override
  String get featureTabbyVault => 'una clave del almacén de Tabby';

  @override
  String get featureTelnetProxy => 'un proxy Telnet';

  @override
  String get featureX11 => 'el reenvío de X11';

  @override
  String fileChanged(String path) {
    return '$path cambió mientras se copiaba.';
  }

  @override
  String fileDenied(String path) {
    return 'Sin permiso: $path';
  }

  @override
  String fileExists(String path) {
    return 'Ya existe: $path';
  }

  @override
  String get fileLost => 'Se perdió la conexión.';

  @override
  String get fileName => 'Archivo';

  @override
  String fileNotFound(String path) {
    return 'No existe: $path';
  }

  @override
  String get fileOther => 'Algo ha fallado con el archivo (más en «Detalles»).';

  @override
  String get filledInEachPane => 'También se rellenan solas, en cada panel:';

  @override
  String get filterFolder => 'Filtrar en esta carpeta';

  @override
  String get filterHostsAndGroups => 'Filtrar hosts y grupos';

  @override
  String get filterIdentities => 'Filtrar por nombre, usuario o clave';

  @override
  String get filterSnippets => 'Filtrar por nombre o comando';

  @override
  String get filterTunnels => 'Filtrar por nombre, host o puerto';

  @override
  String get findASnippet => 'Buscar un snippet';

  @override
  String get findClose => 'Cerrar la búsqueda (Esc)';

  @override
  String findCount(int selected, int total) {
    return '$selected de $total';
  }

  @override
  String get findEllipsis => 'Buscar…';

  @override
  String get findHint => 'Buscar en el terminal';

  @override
  String get findInTerminal => 'Buscar en el terminal';

  @override
  String get findNewer => 'Siguiente, más abajo (Mayús+Intro)';

  @override
  String get findOlder => 'Anterior, más arriba (Intro)';

  @override
  String get findOutSystem => 'Averiguar el sistema';

  @override
  String get findSearching => 'Buscando…';

  @override
  String findTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados',
      one: '1 resultado',
      zero: 'Sin resultados',
    );
    return '$_temp0';
  }

  @override
  String get fingerprint => 'Huella';

  @override
  String get fingerprintNeedsPublic => 'Sin .pub: huella desconocida';

  @override
  String firstConnectionTo(String label) {
    return 'Primera conexión con $label';
  }

  @override
  String get flowHardware => 'RTS/CTS (hardware)';

  @override
  String get flowNone => 'Ninguno';

  @override
  String get flowSoftware => 'XON/XOFF (software)';

  @override
  String get foldSidebar => 'Plegar la barra lateral';

  @override
  String get fontFromTheme => 'La del tema';

  @override
  String get fontOther => 'Otra fuente instalada…';

  @override
  String get fontOtherHint => 'Su nombre exacto, como «Fira Code»';

  @override
  String get fontOtherTitle => 'Otra fuente instalada';

  @override
  String get fontSize => 'Tamaño de letra';

  @override
  String get fontSystem => 'La del sistema';

  @override
  String get forAll => 'A todos:';

  @override
  String get forgetAction => 'Olvidar';

  @override
  String get forgetFileKeyBody =>
      'Se borra esa línea del fichero, que también usa el ssh de tu sistema, y antes se guarda una copia en known_hosts.old, como hace ssh-keygen -R.';

  @override
  String forgetFileKeyTitle(String name, String file) {
    return '¿Quitar la clave de $name de $file?';
  }

  @override
  String get forgetKeyBody => 'OpenWard deja de confiar en esta clave.';

  @override
  String get forgetKeyThen =>
      'La próxima vez que conectes se preguntará otra vez por su clave, salvo que haya otra en la que confíes.';

  @override
  String forgetKeyTitle(String name) {
    return '¿Olvidar la clave de $name?';
  }

  @override
  String get forward => 'Reenvío';

  @override
  String foundMobaXterm(String path) {
    return 'Sesiones en $path';
  }

  @override
  String foundSessions(String path) {
    return 'Sesiones guardadas en $path';
  }

  @override
  String foundSshConfig(int count, int existing) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts',
      one: '1 host',
    );
    String _temp1 = intl.Intl.pluralLogic(
      existing,
      locale: localeName,
      other: ' · $existing ya importados',
      zero: '',
    );
    return '$_temp0$_temp1';
  }

  @override
  String foundTabby(String path) {
    return 'Su configuración, en $path';
  }

  @override
  String get foundTermius =>
      'Instalado: se leen sus datos directamente, sin exportar nada';

  @override
  String get fromDefault => 'Valor por defecto';

  @override
  String get fromExportedFile => 'Desde un archivo exportado';

  @override
  String fromGroup(String name) {
    return 'Del grupo $name';
  }

  @override
  String get fromHere => 'desde aquí';

  @override
  String fromIdentity(String name) {
    return 'De la identidad $name';
  }

  @override
  String get fromNowhere => 'Sin valor: lo decide la conexión';

  @override
  String get fromSshConfig => 'de ~/.ssh/config';

  @override
  String get fromThere => 'desde allí';

  @override
  String goToPage(String page) {
    return 'Ir a $page';
  }

  @override
  String get group => 'Grupo';

  @override
  String get groupInsideItself => 'Un grupo no puede estar dentro de sí mismo.';

  @override
  String groupNamed(String name) {
    return 'Grupo $name';
  }

  @override
  String get groupNeedsName => 'El grupo necesita un nombre.';

  @override
  String get groupSettingsSection => 'Ajustes para todo lo que contiene';

  @override
  String get groups => 'Grupos';

  @override
  String get hashedName => 'Nombre cifrado';

  @override
  String get hideHiddenFiles => 'No mostrar los ocultos';

  @override
  String get hideQueue => 'Ocultar';

  @override
  String get highlightAdd => 'Añadir una regla…';

  @override
  String get highlightCase => 'Distinguir mayúsculas';

  @override
  String get highlightColor => 'Color';

  @override
  String get highlightColorNote =>
      'Los colores son los del terminal: cambian con su tema.';

  @override
  String get highlightEdit => 'Cambiar';

  @override
  String get highlightError => 'Errores (error, failed, denied…)';

  @override
  String get highlightIp => 'Direcciones IP';

  @override
  String get highlightMac => 'Direcciones MAC';

  @override
  String get highlightName => 'Nombre';

  @override
  String get highlightNewTitle => 'Nueva regla de resaltado';

  @override
  String get highlightOk => 'Bien (ok, success, done…)';

  @override
  String get highlightOn => 'Resaltar palabras y direcciones';

  @override
  String get highlightOnHelp =>
      'Solo al pintar, y solo en el texto que el programa deja sin color: no cambia lo que llega, lo que copias ni los registros. En los editores y en less, nada.';

  @override
  String get highlightPattern => 'Qué resaltar';

  @override
  String get highlightPatternBad =>
      'No se lee como expresión regular, o no resaltaría nada.';

  @override
  String get highlightPatternHelp =>
      'Una palabra o una expresión regular. \\b marca el borde de una palabra.';

  @override
  String get highlightRemove => 'Quitar';

  @override
  String get highlightReset => 'Volver a las de la app';

  @override
  String get highlightWarning => 'Avisos (warning, deprecated, timeout)';

  @override
  String get host => 'Host';

  @override
  String hostCountText(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts',
      one: '1 host',
      zero: 'ningún host',
    );
    return '$_temp0';
  }

  @override
  String hostInUse(String name) {
    return 'Otros hosts saltan por «$name»: cámbialos antes de eliminarlo.';
  }

  @override
  String get hostKey => 'Clave del host';

  @override
  String hostKeyOtherTypeBody(String where, String known, String offered) {
    return 'OpenWard conoce $where por su clave $known, pero ahora ofrece una $offered que no conoce. Puede que el servidor haya cambiado sus claves, o que otro equipo se haga pasar por él: confía en ella solo si sabes por qué ha cambiado.';
  }

  @override
  String hostKeyOtherTypeTitle(String label) {
    return 'Otra clave para $label';
  }

  @override
  String hostKeyUnknownBody(String where) {
    return 'OpenWard aún no conoce la clave de $where. Compara la huella con la que te dé quien administra el servidor antes de confiar en ella.';
  }

  @override
  String get hostKeys => 'Claves de host nuevas';

  @override
  String get hostNeedsName => 'El host necesita un nombre.';

  @override
  String get hosts => 'Hosts';

  @override
  String get hostsAll => 'Todos';

  @override
  String get hostsClearFilters => 'Quitar los filtros';

  @override
  String get hostsColAddress => 'Dirección';

  @override
  String get hostsColEnvironment => 'Entorno';

  @override
  String get hostsColLast => 'Última conexión';

  @override
  String get hostsColName => 'Nombre';

  @override
  String get hostsColSystem => 'Sistema';

  @override
  String get hostsFilters => 'Filtros';

  @override
  String get hostsHintConnect => 'conectar';

  @override
  String get hostsHintDrag =>
      'arrastra uno a la barra de pestañas para abrirlo ahí';

  @override
  String get hostsHintEdit => 'editar';

  @override
  String get hostsHintFavorite => 'favorito';

  @override
  String get hostsNoGroup => 'Sin grupo';

  @override
  String get hostsOpenNow => 'abierto ahora';

  @override
  String get hostsSearchHint =>
      'Busca por nombre, dirección, etiqueta o sistema';

  @override
  String get hostsSection => 'Hosts';

  @override
  String hostsSummary(int hosts, int groups) {
    String _temp0 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups grupos',
      one: '1 grupo',
      zero: 'sin grupos',
    );
    return '$hosts · $_temp0';
  }

  @override
  String get hostsViewCards => 'Tarjetas';

  @override
  String get hostsViewList => 'Lista';

  @override
  String get howCsv =>
      'Un host por fila, con cabecera: la plantilla de Termius o columnas como nombre, host, puerto, usuario y grupo.';

  @override
  String get howMobaXterm =>
      'Sessions › Export all sessions to file: un archivo .mxtsessions';

  @override
  String get howPutty =>
      'Un .reg exportado del registro (reg export HKCU\\Software\\SimonTatham\\PuTTY\\Sessions putty.reg)';

  @override
  String get howSecureCrt => 'Tools › Export Settings…: un archivo .xml';

  @override
  String get howTabby => 'Su config.yaml, si no está en este equipo';

  @override
  String get identities => 'Identidades';

  @override
  String identitiesCount(int total, int used) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total identidades',
      one: '1 identidad',
    );
    return '$_temp0 · $used en uso';
  }

  @override
  String get identitiesIntro =>
      'Usuario, claves y agente con un nombre, para usarlos en varios hosts y grupos. Cambiar una identidad cambia todos los que la usan.';

  @override
  String get identitiesNoSecrets =>
      'No se guardan contraseñas ni frases de paso: se piden al conectar, como hasta ahora. De cada clave solo se lee su parte pública (.pub).';

  @override
  String get identity => 'Identidad';

  @override
  String get identityEditorHint =>
      'Usuario, claves y agente con un nombre, para usarlos en varios hosts.';

  @override
  String identityKeyMissingHere(String user) {
    return '$user · falta su clave en este equipo';
  }

  @override
  String get identityNeedsName => 'Ponle un nombre.';

  @override
  String get identityNewNote =>
      'Úsala desde el editor de un host o de un grupo, o con «Usar en…» en la lista de identidades.';

  @override
  String get identityNone => 'Ninguna';

  @override
  String get identityNoneNote => 'Aunque se herede una de más arriba';

  @override
  String identitySaveChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Al guardar cambian los $count hosts que la usan.',
      one: 'Al guardar cambia el host que la usa.',
    );
    return '$_temp0 Un host que pone su propio usuario o sus claves mantiene los suyos.';
  }

  @override
  String identityUsedBy(String who) {
    return 'La usan: $who';
  }

  @override
  String get ignore => 'Ignorar';

  @override
  String get importAction => 'Importar';

  @override
  String get importAnything => 'Importar de otro programa o de ~/.ssh/config';

  @override
  String get importEllipsis => 'Importar…';

  @override
  String importFailed(String error) {
    return 'No se ha podido importar: $error';
  }

  @override
  String importFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hemos encontrado $count hosts en tu ~/.ssh/config.',
      one: 'Hemos encontrado 1 host en tu ~/.ssh/config.',
    );
    return '$_temp0';
  }

  @override
  String get importFrom => 'Importar de ~/.ssh/config';

  @override
  String get importFromSshConfig => 'Importar de ~/.ssh/config';

  @override
  String get importHostsTitle => 'Importar hosts';

  @override
  String get importIntoGroup =>
      'Se guardan en el grupo «~/.ssh/config». Un host trae consigo los hosts por los que salta.';

  @override
  String get importIntro =>
      'Trae tus hosts de otro programa. Solo se leen: el original no cambia.';

  @override
  String get importKeepsFile =>
      'El fichero no se toca, y las claves se quedan donde están: OpenWard guarda la ruta, nunca la clave.';

  @override
  String get importKey => 'Importar una clave';

  @override
  String get importKeyAction => 'Importar…';

  @override
  String get importKeyIntro =>
      'Pega una clave privada o elige su archivo. Se guarda como un archivo nuevo en ~/.ssh; el original no cambia.';

  @override
  String get importLater => 'Puedes importar más tarde desde la barra lateral.';

  @override
  String importN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Importar $count hosts',
      one: 'Importar 1 host',
      zero: 'Importar',
    );
    return '$_temp0';
  }

  @override
  String get importNothing =>
      'No hay hosts nuevos en ~/.ssh/config (o no existe).';

  @override
  String get importReportCopied => 'Informe copiado';

  @override
  String get importScheme => 'Importar de iTerm2 o Ghostty…';

  @override
  String importSchemeDone(String name) {
    return '«$name» importado y puesto en el terminal.';
  }

  @override
  String get importSchemeFailed =>
      'Ese fichero no es un tema de iTerm2 (.itermcolors) ni de Ghostty.';

  @override
  String get importTitle => 'Importar ~/.ssh/config';

  @override
  String get inDark => 'En oscuro';

  @override
  String inGroup(String name) {
    return 'en el grupo $name';
  }

  @override
  String get inLight => 'En claro';

  @override
  String inWhere(String where) {
    return 'en $where';
  }

  @override
  String get inheritAgain => 'Volver a heredar';

  @override
  String inheritsFrom(String group) {
    return 'La hereda de $group';
  }

  @override
  String get inputNotSent => 'Lo que escribas ahora no se envía.';

  @override
  String get inside => 'Dentro de';

  @override
  String get installKeyAction => 'Subir a un servidor…';

  @override
  String installKeyAdded(String host) {
    return 'Clave añadida en $host';
  }

  @override
  String installKeyFailed(String host) {
    return 'No se ha podido subir a $host';
  }

  @override
  String get installKeyIntro =>
      'Su parte pública se añade al ~/.ssh/authorized_keys del servidor, como hace ssh-copy-id. Entras una vez con lo que uses ahora.';

  @override
  String get installKeyNext =>
      'Para entrar con ella, elígela en el host o en su identidad.';

  @override
  String get installKeyNoHosts =>
      'Ningún host coincide. Escribe una dirección para usarla sin guardarla.';

  @override
  String get installKeySearch => 'Busca un host o escribe usuario@dirección';

  @override
  String installKeyTitle(String name) {
    return 'Subir $name a un servidor';
  }

  @override
  String installKeyToAddress(String address) {
    return 'Subir a $address';
  }

  @override
  String installKeyWasThere(String host) {
    return '$host ya tenía esta clave';
  }

  @override
  String installKeyWriteFailed(String error) {
    return 'El servidor no dejó escribir ~/.ssh/authorized_keys: $error';
  }

  @override
  String installingKey(String host) {
    return 'Añadiendo la clave en $host…';
  }

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get itsPort => 'Su puerto';

  @override
  String get jobCancelled => 'Cancelada';

  @override
  String get jobCounting => 'Contando…';

  @override
  String jobDone(String size) {
    return 'Hecho · $size';
  }

  @override
  String get jobFailed => 'Ha fallado';

  @override
  String jobFolder(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'carpeta, $count ficheros',
      one: 'carpeta, 1 fichero',
    );
    return '$_temp0';
  }

  @override
  String jobLost(String done, String total) {
    return 'Se cortó la conexión con $done de $total copiados';
  }

  @override
  String jobPaused(String done, String total) {
    return 'En pausa · $done de $total';
  }

  @override
  String jobProgress(String done, String total) {
    return '$done de $total';
  }

  @override
  String jobQueued(String size) {
    return 'En cola · $size';
  }

  @override
  String get jobQueuedNoSize => 'En cola';

  @override
  String jobSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ya estaban',
      one: '1 ya estaba',
    );
    return '$_temp0';
  }

  @override
  String get jumpThrough => 'Saltar por, en orden';

  @override
  String jumpVia(String hosts) {
    return 'Saltando por $hosts';
  }

  @override
  String jumpsVia(String hosts) {
    return 'salta por $hosts';
  }

  @override
  String keepaliveEvery(int every, int lost) {
    return 'Cada $every s · perdida a los $lost s';
  }

  @override
  String get keepaliveLabel => 'Comprobar la conexión';

  @override
  String get keepaliveOff => 'Nunca';

  @override
  String keyAdded(String path) {
    return 'Guardada en $path.';
  }

  @override
  String get keyBackspace => 'Retroceso';

  @override
  String get keyBefore => 'Antes';

  @override
  String get keyChangedBody =>
      'Puede ser una reinstalación del servidor o alguien interceptando la conexión. No se ha enviado ninguna contraseña ni clave.';

  @override
  String keyChangedDialogBody(String where) {
    return '$where se presenta con una clave distinta de la que tenías como buena. Puede que el servidor se haya reinstalado o haya cambiado de clave, pero también que alguien esté interceptando la conexión. No sigas sin comprobar la huella nueva con quien administra el servidor.';
  }

  @override
  String keyChangedTitle(String label) {
    return 'La clave de $label ha cambiado';
  }

  @override
  String get keyColumn => 'Clave';

  @override
  String get keyCommentLabel => 'Comentario';

  @override
  String get keyDelete => 'Supr';

  @override
  String keyDeleted(String name) {
    return '$name eliminada.';
  }

  @override
  String get keyExchange => 'Intercambio';

  @override
  String keyExported(String name, String path) {
    return '$name copiada a $path.';
  }

  @override
  String get keyFailed => 'No se ha podido (más en «Detalles»).';

  @override
  String get keyInKnownHosts => 'en ~/.ssh/known_hosts';

  @override
  String get keyInOpenWard => 'guardada en OpenWard';

  @override
  String get keyMissing => 'No está en este equipo';

  @override
  String keyMissingWarning(String path, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Los $count hosts que la usan no podrán usar esa clave hasta que la copies o cambies la ruta.',
      one: 'El host que la usa no podrá usar esa clave hasta que la copies o cambies la ruta.',
      zero: 'Cópiala o cambia la ruta antes de usarla.',
    );
    return '$path no está en este equipo. $_temp0';
  }

  @override
  String get keyNameInvalid =>
      'Ese nombre no vale para un archivo de clave: usa letras, números, «-», «_», «.» o «@».';

  @override
  String keyNameTaken(String name) {
    return 'Ya hay un archivo $name en ~/.ssh. Elige otro nombre.';
  }

  @override
  String get keyNoPublicHalf =>
      'Sin .pub al lado: su tipo se sabrá al conectar';

  @override
  String get keyNotOpenSsh =>
      'Esta clave no es de OpenSSH: su frase de paso se cambia con el programa que la hizo.';

  @override
  String get keyNotReadable =>
      'Eso no es una clave privada que OpenWard pueda leer (OpenSSH, PEM o PuTTY).';

  @override
  String keyNow(String algorithm) {
    return 'Ahora ($algorithm)';
  }

  @override
  String keyPassphraseChanged(String name) {
    return 'La frase de paso de $name ha cambiado.';
  }

  @override
  String get keyPassphraseEllipsis => 'Cambiar la frase de paso…';

  @override
  String get keyPassphraseEmpty =>
      'Vacía, la clave queda sin frase de paso: quien tenga el archivo podrá usarla.';

  @override
  String keyPassphraseTitle(String name) {
    return 'Frase de paso de $name';
  }

  @override
  String get keyPerHost => 'Una por host (lleva %h, %r…)';

  @override
  String keyProtected(String key) {
    return 'La clave $key está protegida.';
  }

  @override
  String get keyReceived => 'Recibida';

  @override
  String get keyRenameNote =>
      'Su .pub y su certificado van con ella, y los hosts, grupos e identidades que la usan pasan a nombrarla así.';

  @override
  String keyRenameTitle(String name) {
    return 'Renombrar $name';
  }

  @override
  String get keySaved => 'Guardada';

  @override
  String get keyType => 'Tipo';

  @override
  String get keyTypeEcdsa => 'Para servidores o normas que piden curvas NIST.';

  @override
  String get keyTypeEd25519 =>
      'La recomendada: corta, rápida, y la aceptan los servidores de los últimos diez años.';

  @override
  String get keyTypeRsa =>
      'Para servidores antiguos que no aceptan nada más nuevo. Tarda unos segundos en crearse.';

  @override
  String get keyTypeSecurityEcdsa =>
      'ECDSA P-256 en la llave: la tienen todas las llaves FIDO2.';

  @override
  String get keyTypeSecurityEd25519 =>
      'Ed25519 en la llave: la mejor opción si tu llave la tiene (casi todas desde 2020).';

  @override
  String get keys => 'Claves';

  @override
  String get keysHelp =>
      'Una ruta por línea. OpenWard guarda la ruta, nunca la clave.';

  @override
  String get keysInOrder =>
      'Se prueban en este orden; arrastra para cambiarlo.';

  @override
  String get keysIntro =>
      'Las claves privadas de ~/.ssh. Se quedan ahí: el vault solo guarda qué clave usa cada host. Aquí puedes crear claves, traer las que tengas y subir la parte pública a un servidor.';

  @override
  String get kindDynamic => 'Dinámico (-D)';

  @override
  String get kindDynamicShort => 'Dinámico';

  @override
  String get kindLocal => 'Local (-L)';

  @override
  String get kindLocalShort => 'Local';

  @override
  String get kindRemote => 'Remoto (-R)';

  @override
  String get kindRemoteShort => 'Remoto';

  @override
  String get knownHosts => 'Hosts conocidos';

  @override
  String get knownHostsFileChanged =>
      'El fichero ha cambiado desde que se mostró. Vuelve a mirarlo antes de quitar nada.';

  @override
  String knownHostsIntro(String file) {
    return 'Las claves de servidor en las que confías. Al conectar se miran las de OpenWard y las de $file; las nuevas se guardan en OpenWard.';
  }

  @override
  String lanDynamicNote(String host) {
    return 'Es un proxy SOCKS sin contraseña: cualquiera de tu red podrá entrar por él en todo lo que alcanza $host mientras esté abierto.';
  }

  @override
  String get lanLocalNote =>
      'Cualquiera de tu red podrá usarlo mientras esté abierto.';

  @override
  String get lanRemoteNote =>
      'El servidor tiene que permitirlo (GatewayPorts en sshd); si no, escucha solo en sí mismo.';

  @override
  String get language => 'Idioma';

  @override
  String get languageSystem => 'Como el sistema';

  @override
  String latencyChecks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'las últimas $count comprobaciones',
      one: 'la última comprobación',
    );
    return '$_temp0';
  }

  @override
  String get latencyClick =>
      'Un clic abre los detalles de la conexión y su huella.';

  @override
  String latencyHigh(int ms, int times) {
    return '$ms ms: $times veces lo habitual';
  }

  @override
  String latencyHighLabel(int ms) {
    return 'Latencia alta: $ms ms';
  }

  @override
  String latencyLabel(int ms) {
    return 'Latencia: $ms ms';
  }

  @override
  String latencyUsual(int ms) {
    return 'habitual $ms ms';
  }

  @override
  String latencyWith(String host) {
    return 'Latencia con $host';
  }

  @override
  String get legacyHostKeys => 'Claves antiguas (ssh-rsa)';

  @override
  String get legacyHostKeysNote =>
      'Solo para servidores anteriores a OpenSSH 7.2, que firman su clave con SHA-1. OpenSSH dejó de aceptarlo en la 8.8.';

  @override
  String get legacyHostKeysOff => 'No';

  @override
  String get legacyHostKeysOn => 'Aceptar ssh-rsa con SHA-1';

  @override
  String get legendInheritAgain => 'vuelve a heredar';

  @override
  String get legendInherited => 'heredado';

  @override
  String get legendSetHere => 'cambiado aquí';

  @override
  String get library => 'Biblioteca';

  @override
  String get licenses => 'Licencias';

  @override
  String get lightAndDark => 'Claro y oscuro';

  @override
  String get lineHeight => 'Interlineado del terminal';

  @override
  String lineNumber(int line) {
    return 'línea $line';
  }

  @override
  String linesCount(int count) {
    return '$count líneas';
  }

  @override
  String linkLeadsElsewhere(String url) {
    return 'Cuidado: el texto dice otra cosa, pero lleva a $url';
  }

  @override
  String linkNotOpened(String scheme) {
    return 'Los enlaces «$scheme:» no se abren desde el terminal.';
  }

  @override
  String localSentence(String here, String dest, String host) {
    return 'Lo que conecte a $here llega a $dest como si saliera de $host.';
  }

  @override
  String get localShell => 'Local';

  @override
  String get localTerminal => 'Terminal local';

  @override
  String get localUser => 'tu usuario local';

  @override
  String get logCommands => 'Comandos';

  @override
  String get logCopied => 'Copiado.';

  @override
  String get logCopyCommand => 'Copiar el comando elegido y su salida';

  @override
  String get logCopyText => 'Copiar como texto';

  @override
  String get logDelete => 'Borrar el registro…';

  @override
  String get logDeleteBody =>
      'Se borra lo que se vio en esta sesión y su entrada. No se puede deshacer.';

  @override
  String get logDeleteTitle => '¿Borrar este registro?';

  @override
  String get logEditNote => 'Editar la nota';

  @override
  String get logEndedTooltip => 'El registro de esta conexión';

  @override
  String get logExportCast => 'Asciicast (.cast)';

  @override
  String get logExportCastHelp =>
      'Con tiempos y colores; se reproduce con asciinema.';

  @override
  String get logExportText => 'Texto (.txt)';

  @override
  String get logExportTextHelp => 'Lo que se vio, sin colores ni tiempos.';

  @override
  String logExported(String path) {
    return 'Guardado en $path.';
  }

  @override
  String logFailed(String reason) {
    return 'El registro se detuvo: $reason';
  }

  @override
  String get logIncomplete =>
      'Se corta antes del final: OpenWard se cerró de golpe.';

  @override
  String get logMarkBack => 'Volvió la conexión';

  @override
  String get logMarkFull => 'Registro lleno';

  @override
  String get logMarkLost => 'Se cortó la conexión';

  @override
  String get logMarkOmitted => 'Salida omitida';

  @override
  String get logMarkPause => 'En pausa';

  @override
  String get logMenuEnded => 'El registro de esta conexión';

  @override
  String get logMenuNeverTyped => 'nunca lo que escribes';

  @override
  String get logMenuPaused => 'En pausa';

  @override
  String get logMenuPausedSub => 'Lo que sale ahora no se guarda';

  @override
  String logMenuSince(String time) {
    return 'Desde las $time';
  }

  @override
  String get logMenuTitle => 'Se guarda lo que sale en pantalla';

  @override
  String get logMoreActions => 'Más acciones';

  @override
  String get logNeverExpires => 'No caduca';

  @override
  String get logNoteHelp => 'No caduca: se guarda hasta que lo quites.';

  @override
  String get logNoteHint => 'Por qué lo guardas (opcional)';

  @override
  String get logNoteTitle => 'Guardar este registro';

  @override
  String get logOpenThis => 'Abrir el registro de esta sesión';

  @override
  String get logPause => 'Pausar el registro';

  @override
  String get logPauseHelp => 'Lo que salga mientras, no se guarda';

  @override
  String get logPausePlayback => 'Pausar';

  @override
  String logPausedFor(String duration) {
    return 'En pausa · $duration';
  }

  @override
  String logPausedTotal(String duration) {
    return '$duration en pausa';
  }

  @override
  String get logPlay => 'Reproducir';

  @override
  String get logPosition => 'Momento de la sesión';

  @override
  String get logReadOnly => 'Solo lectura';

  @override
  String get logRecordingTooltip => 'Se guarda lo que sale en pantalla';

  @override
  String get logResume => 'Seguir grabando';

  @override
  String get logResumeHelp =>
      'El registro guarda un hueco con lo que duró la pausa';

  @override
  String get logSaved => 'Guardado';

  @override
  String get logSeeIt => 'Ver el registro';

  @override
  String logSpeed(String speed) {
    return 'Velocidad: $speed';
  }

  @override
  String get logStillRecording =>
      'Sigue grabando: lo de los últimos segundos aún no está aquí.';

  @override
  String get logStopEverywhere =>
      'Activado en todos los hosts; se cambia en Ajustes';

  @override
  String logStopFromGroup(String group) {
    return 'Lo hereda de $group; se cambia en su editor';
  }

  @override
  String logStopHost(String host) {
    return 'No guardar registros de $host…';
  }

  @override
  String get logStopOwn => 'Activado en este host; se cambia en su editor';

  @override
  String get logTab => 'Registro';

  @override
  String logTabTitle(String label, String when) {
    return '$label · $when';
  }

  @override
  String get logUnsave => 'Dejar de guardar';

  @override
  String get logViewerEmpty => 'Abre un registro desde la página Registros.';

  @override
  String get logs => 'Registros';

  @override
  String get logsAll => 'Todas';

  @override
  String get logsAlsoHere => 'También en este equipo';

  @override
  String get logsAppQuit => 'Se cerró la app';

  @override
  String logsAppQuitAt(String time) {
    return 'OpenWard se cerró a las $time sin acabar la sesión. Esto es lo último que se guardó.';
  }

  @override
  String logsCommands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comandos',
      one: '1 comando',
    );
    return '$_temp0';
  }

  @override
  String get logsConnectAgain => 'Conectar otra vez';

  @override
  String logsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count registros',
      one: '1 registro',
    );
    return '$_temp0';
  }

  @override
  String get logsCut => 'Se cortó';

  @override
  String logsCutAt(String time) {
    return 'La conexión se cortó a las $time. Esto es lo último que se vio.';
  }

  @override
  String get logsDeleteAll => 'Borrar todos los registros';

  @override
  String get logsDeleteAllAction => 'Borrar todos';

  @override
  String get logsDeleteAllEllipsis => 'Borrar todos…';

  @override
  String logsDeleteAllHelp(String count, String size) {
    return '$count y $size, también los guardados y las grabaciones que no aparecen en la lista. Las sesiones abiertas se conservan. No se puede deshacer.';
  }

  @override
  String get logsDeleteAllTitle => '¿Borrar todos los registros?';

  @override
  String get logsEmptyBody =>
      'Cada conexión deja aquí cuándo fue y cuánto duró. Para guardar también lo que se vio, activa el registro de sesión en un host, en un grupo o en Ajustes.';

  @override
  String get logsEmptyTitle => 'Aún no hay sesiones';

  @override
  String get logsEverywhere => 'Guardar el registro en todos los hosts';

  @override
  String get logsEverywhereHelp =>
      'Lo que sale en pantalla, con sus tiempos, para volver a verlo, buscar en él y exportarlo. Nunca lo que escribes: una contraseña que no se ve no queda; un cat .env, sí. Solo en este equipo.';

  @override
  String get logsExceptIn => 'Desactivado en:';

  @override
  String get logsFolder => 'Carpeta';

  @override
  String get logsGroup => 'grupo';

  @override
  String logsHitAt(String time) {
    return 'A los $time de la sesión';
  }

  @override
  String logsHits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count coincidencias',
      one: '1 coincidencia',
    );
    return '$_temp0';
  }

  @override
  String logsHitsIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'en $count registros',
      one: 'en 1 registro',
    );
    return '$_temp0';
  }

  @override
  String get logsHost => 'host';

  @override
  String get logsKeep => 'Borrar los registros pasados';

  @override
  String get logsKeepAlways => 'Nunca';

  @override
  String logsKeepDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'A los $days días',
      one: 'Al día',
    );
    return '$_temp0';
  }

  @override
  String get logsKeepHelp => 'Los guardados no caducan nunca.';

  @override
  String get logsLastCommands => 'Últimos comandos';

  @override
  String get logsLive => 'Grabando';

  @override
  String get logsLocal => 'Locales';

  @override
  String get logsLocalHelp => 'Tu propio equipo. Por defecto no.';

  @override
  String get logsLocalTerminals => 'También los terminales locales';

  @override
  String logsMoreHits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'y $count más',
      one: 'y 1 más',
    );
    return '$_temp0';
  }

  @override
  String get logsNoLimit => 'Sin límite';

  @override
  String get logsNoRecording =>
      'Esta sesión no tiene registro: solo cuándo y cuánto duró.';

  @override
  String get logsNoneOff => 'Ningún host ni grupo lo desactiva.';

  @override
  String get logsNoneOn => 'Ningún host ni grupo lo activa por su cuenta.';

  @override
  String get logsNotRecorded => 'Sin registro';

  @override
  String get logsNothing => 'Ninguna sesión con estos filtros.';

  @override
  String get logsNow => 'ahora';

  @override
  String get logsOnlyIn => 'Activado solo en:';

  @override
  String get logsOpen => 'Abrir el registro';

  @override
  String get logsOpenEntry => 'Abierta';

  @override
  String get logsOpenHere => 'Abrir aquí';

  @override
  String get logsPick => 'Elige una sesión para ver lo último que se vio.';

  @override
  String get logsRecorded => 'Con registro';

  @override
  String get logsSaved => 'Guardadas';

  @override
  String logsSavedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count guardados',
      one: '1 guardado',
    );
    return '$_temp0';
  }

  @override
  String get logsSearchHint => 'Busca en lo que se vio: comandos y salida';

  @override
  String get logsSearchNone => 'Nada en lo grabado.';

  @override
  String get logsSearchNote =>
      'Se busca en lo que quedó grabado. Las sesiones sin registro solo guardan cuándo y cuánto duraron.';

  @override
  String get logsSearching => 'Buscando…';

  @override
  String get logsSessionTitle => 'Registros de sesión';

  @override
  String get logsSettings => 'Ajustes de registros';

  @override
  String get logsSettingsEllipsis => 'Ajustes de registros…';

  @override
  String get logsSpace => 'Espacio máximo';

  @override
  String get logsSpaceHelp =>
      'Al llegar, se borran primero los más antiguos sin guardar.';

  @override
  String get logsToday => 'Hoy';

  @override
  String get logsUnencrypted =>
      'De momento se guardan sin cifrar, en una carpeta que solo puede leer tu usuario, igual que el historial de comandos. Cuando el vault vaya cifrado, los registros irán cifrados con él y esta nota desaparecerá.';

  @override
  String logsUsage(String size, String max, int days) {
    return '$size de $max · se guardan $days días';
  }

  @override
  String get logsWhereNote =>
      'En el editor de cada host o grupo, «Registro de sesión» › Avanzado: se hereda como el resto, de los grupos al host.';

  @override
  String get logsYesterday => 'Ayer';

  @override
  String get lostInLog =>
      'Lo que se vio hasta ahora está en su registro, aunque cierres esta pestaña.';

  @override
  String lostKeptInTmux(String host) {
    return 'Tu sesión sigue en tmux en $host: al volver la encontrarás como estaba. Lo que escribas ahora no se envía.';
  }

  @override
  String lostNewShell(String host) {
    return 'Lo que escribas ahora no se envía. Al volver se abre un terminal nuevo: lo que corría en $host no sigue.';
  }

  @override
  String madeGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count grupos, con sus ajustes',
      one: '1 grupo, con sus ajustes',
    );
    return '$_temp0';
  }

  @override
  String madeIdentities(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count identidades',
      one: '1 identidad',
    );
    return '$_temp0';
  }

  @override
  String madeKey(String path) {
    return 'Clave guardada en $path';
  }

  @override
  String madeKnownHosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count claves de host de confianza, en Biblioteca › Hosts conocidos',
      one: '1 clave de host de confianza, en Biblioteca › Hosts conocidos',
    );
    return '$_temp0';
  }

  @override
  String madeSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts ya estaban de antes y se han dejado como estaban',
      one: '1 host ya estaba de antes y se ha dejado como estaba',
    );
    return '$_temp0';
  }

  @override
  String madeSnippets(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippets, en Biblioteca › Snippets',
      one: '1 snippet, en Biblioteca › Snippets',
    );
    return '$_temp0';
  }

  @override
  String madeTunnels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count túneles, en Biblioteca › Túneles',
      one: '1 túnel, en Biblioteca › Túneles',
    );
    return '$_temp0';
  }

  @override
  String get makeKey => 'Crear la clave';

  @override
  String get makingKey => 'Creando…';

  @override
  String get manageSnippets => 'Gestionar snippets…';

  @override
  String get markerCertAuthority =>
      'Autoridad de certificados: confía en los hosts que firma';

  @override
  String get markerRevoked => 'Revocada: se rechaza siempre';

  @override
  String matchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count coinciden',
      one: '1 coincide',
      zero: 'ninguna coincide',
    );
    return '$_temp0';
  }

  @override
  String matchesHost(String host) {
    return 'Coincide con $host';
  }

  @override
  String get maximizePane => 'Maximizar el panel';

  @override
  String milliseconds(int ms) {
    return '$ms ms';
  }

  @override
  String get minimumContrast => 'Contraste mínimo';

  @override
  String get minimumContrastHelp =>
      'Aclara u oscurece el texto del terminal que no se lee sobre su fondo.';

  @override
  String get missingAddress => 'Falta la dirección.';

  @override
  String get missingJump => 'Añade al menos un host por el que saltar.';

  @override
  String get missingProxy => 'Falta el servidor o el puerto del proxy.';

  @override
  String get missingProxyCommand => 'Falta el ProxyCommand.';

  @override
  String get missingSocket => 'Falta la ruta del socket del agente.';

  @override
  String get monthsShort => 'ene,feb,mar,abr,may,jun,jul,ago,sept,oct,nov,dic';

  @override
  String get moreActions => 'Más acciones';

  @override
  String get moreOptions => 'Más opciones';

  @override
  String get moshFallbackNoClient =>
      'sin Mosh: falta mosh-client en este equipo (brew install mosh, o apt install mosh) · sigue por SSH';

  @override
  String get moshFallbackNoServer =>
      'sin Mosh: el servidor no tiene mosh-server · sigue por SSH';

  @override
  String get moshFallbackNoUdp =>
      'sin Mosh: no llega el UDP del servidor (un cortafuegos, o una red que no lo deja pasar) · sigue por SSH, en tmux';

  @override
  String moshFallbackOther(String said) {
    return 'sin Mosh: $said · sigue por SSH';
  }

  @override
  String get moshFallbackWindows =>
      'sin Mosh: en Windows todavía no · sigue por SSH';

  @override
  String get moshNote =>
      'Hace falta mosh-server en el servidor y mosh-client en este equipo (macOS: brew install mosh; Linux: apt o dnf install mosh). El UDP va directo: los saltos solo sirven para arrancarlo. Si no llega, la sesión sigue por SSH, en tmux.';

  @override
  String get moshOff => 'Apagado: SSH';

  @override
  String get moshOn => 'Encendido: por Mosh cuando se pueda';

  @override
  String get moshServer => 'Servidor de Mosh';

  @override
  String get moshServerHelp =>
      'Dónde está mosh-server en el servidor, si no está en su PATH: /opt/homebrew/bin/mosh-server';

  @override
  String get moveEarlier => 'Mover antes';

  @override
  String get moveLater => 'Mover después';

  @override
  String get moveToNewTab => 'Mover a una pestaña nueva';

  @override
  String movedToGroup(String host, String group) {
    return '$host está ahora en $group.';
  }

  @override
  String get name => 'Nombre';

  @override
  String nameAndMore(String name, int count) {
    return '$name y $count más';
  }

  @override
  String get nameNoSlash => 'Un nombre no puede llevar «/».';

  @override
  String namesAndMore(String names, int count) {
    return '$names y $count más';
  }

  @override
  String get netLost => 'se ha perdido la conexión.';

  @override
  String netNoAnswer(int seconds) {
    return 'no responde ($seconds s sin respuesta).';
  }

  @override
  String get netNotFound => 'no se encuentra el host.';

  @override
  String get netOther => 'ha fallado la red (más en «Detalles»).';

  @override
  String netProxyCommand(String said) {
    return 'el ProxyCommand ha fallado: $said';
  }

  @override
  String get netRefused => 'conexión rechazada.';

  @override
  String get netTimeout => 'tiempo de espera agotado.';

  @override
  String get netUnreachable => 'no se llega al host.';

  @override
  String get netUnreachableMac =>
      'no se llega al host. Si está en tu red local, mira que OpenWard tenga permiso en Ajustes del Sistema › Privacidad y seguridad › Red local.';

  @override
  String get newEllipsis => 'Nuevo…';

  @override
  String get newFolder => 'Nueva carpeta';

  @override
  String get newGroup => 'Nuevo grupo';

  @override
  String get newGroupTitle => 'Nuevo grupo';

  @override
  String get newHost => 'Nuevo host';

  @override
  String get newHostHere => 'Nuevo host aquí';

  @override
  String get newHostTitle => 'Nuevo host';

  @override
  String get newIdentity => 'Nueva identidad';

  @override
  String get newIdentityEllipsis => 'Nueva identidad…';

  @override
  String get newKey => 'Nueva clave';

  @override
  String get newKeyAction => 'Nueva clave…';

  @override
  String newKeyWhere(String private, String public) {
    return 'Se guarda en $private (solo tú puedes leerla) y su parte pública en $public.';
  }

  @override
  String get newLocalTerminal => 'Terminal local nuevo';

  @override
  String get newPane => 'Panel nuevo';

  @override
  String get newPassphrase => 'Frase de paso nueva';

  @override
  String get newSnippet => 'Nuevo snippet';

  @override
  String get newSubgroup => 'Nuevo subgrupo';

  @override
  String get newTunnel => 'Nuevo túnel';

  @override
  String get newsConnectionBody =>
      'Si el servidor se va, se nota en segundos y la conexión vuelve sola; con la sesión persistente, vuelves al mismo terminal en tmux. Al conectar y al reconectar, el camino hasta el host, animado.';

  @override
  String get newsConnectionTitle => 'Conexión viva';

  @override
  String get newsEditorBody =>
      'Lo heredado se ve con borde discontinuo y de dónde viene; se cambia escribiendo encima, y ↺ vuelve a heredarlo. Lo avanzado, plegado. Igual en grupos, y la misma rejilla en identidades.';

  @override
  String get newsEditorTitle => 'Un editor de hosts más claro';

  @override
  String get newsEnvBody =>
      'Marca un grupo como Producción, Pruebas o con un nombre y color propios: sus pestañas y terminales lo dicen, para no escribir en el servidor equivocado.';

  @override
  String get newsEnvTitle => 'El entorno de cada servidor, a la vista';

  @override
  String get newsFavoritesBody =>
      'La estrella al pasar el ratón por un host: arriba en la barra, en el raíl, en la paleta y en el inicio, en el orden que les des.';

  @override
  String get newsFavoritesTitle => 'Favoritos';

  @override
  String newsFocusBody(String keys) {
    return 'La barra lateral se pliega en iconos o se oculta ($keys), sola al abrir una sesión si quieres, y oculta se asoma al dejar el ratón en el borde. Su ancho se cambia arrastrando el borde, y el terminal tiene más margen. Todo en Ajustes › General.';
  }

  @override
  String get newsFocusTitle => 'Más sitio para el terminal';

  @override
  String get newsFresh => 'nuevo';

  @override
  String get newsHopsBody =>
      'Con un bastion por medio, la tarjeta de la latencia dice cuánto tarda cada salto, para ver qué parte del camino va lenta.';

  @override
  String get newsHopsTitle => 'La latencia de cada salto';

  @override
  String get newsIdentitiesBody =>
      'Usuario, claves y agente con un nombre, para un grupo entero o varios hosts a la vez.';

  @override
  String get newsIdentitiesTitle => 'Identidades';

  @override
  String get newsImportBody =>
      'Hosts, grupos, identidades y túneles de Termius, PuTTY, KiTTY, MobaXterm, Tabby o SecureCRT, y hosts de un CSV, desde «…» › Importar… en la barra lateral. Las contraseñas no se traen.';

  @override
  String get newsImportTitle => 'Importar desde tu cliente anterior';

  @override
  String get newsKeysBody =>
      'Crea claves Ed25519, ECDSA o RSA, importa las tuyas, mira sus huellas y súbelas a un servidor sin salir de OpenWard, como ssh-copy-id.';

  @override
  String get newsKeysTitle => 'Claves';

  @override
  String get newsLatencyBody =>
      'La barra de estado dice cuánto tarda el servidor en responder, con una gráfica de las últimas comprobaciones; en ámbar si sube mucho sobre lo habitual. Al pasar el ratón, la ruta y el cifrado.';

  @override
  String get newsLatencyTitle => 'La latencia, siempre a la vista';

  @override
  String get newsLinesBody =>
      'Un host puede ser SSH, Telnet o un puerto serie de este equipo, para la consola de un switch o un router. «Puerto serie» en el inicio abre uno a mano. Telnet avisa de que no cifra.';

  @override
  String get newsLinesTitle => 'Telnet y puerto serie';

  @override
  String get newsLogoBody =>
      'Umbral, una O abierta con un chevrón: en el icono de la app y, dentro, en la bienvenida, el inicio, Acerca de y aquí, en el color de tu tema.';

  @override
  String get newsLogoTitle => 'Logo nuevo';

  @override
  String newsLogsBody(String shortcut) {
    return 'Cada conexión deja su entrada en Registros ($shortcut): dónde, cuándo y cómo acabó. Donde lo actives (Ajustes › Registros, o en un grupo o un host), también lo que salió en pantalla, para buscar en él, volver a verlo comando a comando y exportarlo. Nunca lo que escribes; viene apagado mientras no vaya cifrado.';
  }

  @override
  String get newsLogsTitle => 'Registros de sesión';

  @override
  String get newsManyHostsBody =>
      'Un snippet en los hosts que elijas, cada uno en su panel; un snippet al conectar, heredable; y en SFTP, «Abrir con…»: lo editas aquí y se sube al guardarlo.';

  @override
  String get newsManyHostsTitle => 'Snippets en varios hosts';

  @override
  String get newsMoreThemesBody =>
      'Monitor, con letras verdes de verdad; Berenjena, con el terminal morado; Búnker, todo en un solo fósforo; Marino, verde sobre azul marino; y Catppuccin, Dracula y Tokyo Night para toda la ventana. En Ajustes › Apariencia.';

  @override
  String get newsMoreThemesTitle => 'Siete familias de temas más';

  @override
  String get newsMoshBody =>
      'En «Avanzado» de un host: la sesión sigue aunque cambies de red o duermas el portátil. Usa el mosh-client que tengas instalado, y si no llega el UDP, sigue por SSH.';

  @override
  String get newsMoshTitle => 'Mosh, si lo quieres';

  @override
  String newsPaletteBody(String shortcut) {
    return 'Todo lo que hace la ventana, tus hosts, snippets y los comandos que ya ejecutaste, a unas letras ($shortcut). El historial se queda en este equipo y nunca guarda contraseñas.';
  }

  @override
  String get newsPaletteTitle => 'Paleta de comandos e historial';

  @override
  String newsPanesBody(String split, String broadcast) {
    return 'Divide una pestaña ($split) o arrastra otra, o un host, sobre un terminal; escribe en varios paneles a la vez ($broadcast). Con exit, la pestaña se cierra sola.';
  }

  @override
  String newsPanesBody2(String keys) {
    return 'Arrastrar una pestaña sobre un terminal ya no mueve la ventana. El menú de cada panel lo mueve a su pestaña, lo intercambia o iguala tamaños ($keys); el panel nuevo ofrece las pestañas abiertas, cada panel tiene su nombre y el borde entre ellos se ve y se agarra.';
  }

  @override
  String get newsPanesTitle => 'Paneles y broadcast';

  @override
  String get newsPanesTitle2 => 'Paneles sin adivinar';

  @override
  String newsSearchBody(String keys) {
    return '$keys abre la paleta con las pestañas abiertas, las conexiones recientes, los hosts, las acciones y lo que ya ejecutaste. Empieza por > para ver solo las acciones.';
  }

  @override
  String get newsSearchTitle => 'Un atajo para buscarlo todo';

  @override
  String get newsSecurityKeysBody =>
      'Claves en una YubiKey u otra llave FIDO2: se crean en «Nueva clave», y al conectar la app pide el toque y el PIN. Los certificados que caducan avisan la última semana.';

  @override
  String get newsSecurityKeysTitle => 'Llaves de seguridad';

  @override
  String newsSftpBody(String shortcut) {
    return 'Arrastra entre este equipo y el servidor, con cola, reanudación y lo que ya existe resuelto a tu manera ($shortcut).';
  }

  @override
  String get newsSftpTitle => 'SFTP de doble panel';

  @override
  String newsShortcutsBody(String keys) {
    return '$keys abre la lista de atajos, con búsqueda, y los botones dicen el suyo al pasar el ratón.';
  }

  @override
  String get newsShortcutsTitle => 'Todos los atajos, a mano';

  @override
  String newsSidebarBody(String keys) {
    return 'Todos los hosts están en Hosts ($keys), con filtros por entorno, etiqueta y sistema. La barra lateral se queda con lo de cada día: lo abierto, los favoritos y los recientes, con la Biblioteca en una fila; plegada en raíl, lo abierto cabe en un contador.';
  }

  @override
  String get newsSidebarTitle => 'Los hosts, en su página';

  @override
  String newsSnippetsBody(String shortcut) {
    return 'Comandos con variables a un atajo ($shortcut), y las claves en las que confías, con las de ~/.ssh/known_hosts.';
  }

  @override
  String get newsSnippetsTitle => 'Snippets y hosts conocidos';

  @override
  String get newsStartBody =>
      'La conexión rápida completa con tus hosts y las direcciones que ya usaste; debajo, las conexiones recientes con cuánto duraron y los túneles abiertos.';

  @override
  String get newsStartTitle => 'Un inicio para volver a lo de siempre';

  @override
  String get newsSuggestBody =>
      'Lo que sigue sale en gris, del historial de ese host, de tus snippets y de comandos comunes; → lo escribe. Todo en este equipo.';

  @override
  String get newsSuggestTitle => 'Sugerencias mientras escribes';

  @override
  String get newsSystemBody2 =>
      'Debian, Ubuntu, Fedora, Alpine y 22 sistemas más, con su logo del color de su entorno; macOS y Windows, con un icono propio. Para los que no lo dicen al conectar, como los de Tailscale SSH, «Averiguar el sistema» en su menú lee /etc/os-release; o en todos, desde Ajustes › General.';

  @override
  String get newsSystemTitle2 => 'El sistema de cada servidor, con su logo';

  @override
  String get newsTerminalBody =>
      'Copiar al seleccionar, pegar con clic derecho, errores y direcciones en color, atajos de Mac o de PC. Por host: la codificación (Latin-1, CP437…), el retroceso y sus propios colores.';

  @override
  String get newsTerminalTitle => 'El terminal a tu manera';

  @override
  String get newsThemesBody =>
      'Cinco temas en claro y oscuro, capas que se combinan, tamaño del texto, contraste mínimo y reducir movimiento.';

  @override
  String get newsThemesTitle => 'Temas y accesibilidad visual';

  @override
  String get newsTunnelsBody =>
      'Local, remoto y SOCKS5, que se abren al conectar; también proxy HTTP y SOCKS5 para llegar al servidor.';

  @override
  String get newsTunnelsTitle => 'Túneles guardados y proxy';

  @override
  String get newsWorkspacesBody =>
      'Guarda tus pestañas y paneles con un nombre y ábrelos otra vez, ya conectados, desde la biblioteca o la paleta.';

  @override
  String get newsWorkspacesTitle => 'Espacios de trabajo';

  @override
  String get next => 'Siguiente';

  @override
  String get no => 'No';

  @override
  String noAnswerFor(int seconds) {
    return 'Sin respuesta desde hace $seconds s.';
  }

  @override
  String get noGroup => 'Sin grupo';

  @override
  String get noHostsBody => 'Añade uno o tráelos de tu ~/⁠.ssh/⁠config.';

  @override
  String get noHostsTitle => 'Aún no tienes hosts';

  @override
  String get noIdentities => 'Aún no hay identidades';

  @override
  String get noIdentitiesBody =>
      'Una identidad junta un usuario, sus claves y el agente con un nombre («deploy en producción»). Ponla en un grupo y todos sus hosts entran igual; cámbiala una vez y cambian todos.';

  @override
  String get noIdentityInherited => 'Ningún grupo pone una';

  @override
  String get noIdentityNow => 'Sin identidad';

  @override
  String get noJumpsYet => 'Ninguno todavía.';

  @override
  String get noKeys => 'No hay claves en ~/.ssh';

  @override
  String get noKeysBody =>
      'Crea una con «Nueva clave…» o trae la que ya tengas con «Importar…».';

  @override
  String get noKeysYet =>
      'Sin claves: se prueban las habituales de ~/.ssh y las del agente.';

  @override
  String get noKnownHosts => 'Aún no confías en ninguna clave';

  @override
  String get noKnownHostsBody =>
      'Las claves de los servidores aparecen aquí cuando conectas y confías en ellas.';

  @override
  String noMatches(String filter) {
    return 'Nada coincide con «$filter»';
  }

  @override
  String get noParent => 'Ningún grupo';

  @override
  String get noPostQuantumNote =>
      'El servidor no ofrece un intercambio poscuántico (mlkem768x25519; OpenSSH lo trae desde la 10.0).';

  @override
  String noPublicKey(String name) {
    return '$name no tiene .pub y está cifrada: sin su frase de paso no se puede leer la parte pública.';
  }

  @override
  String get noResponse => 'sin respuesta';

  @override
  String get noResults => 'Ningún host coincide.';

  @override
  String get noSnippetMatches => 'Ningún snippet coincide';

  @override
  String get noSnippets => 'Aún no hay snippets';

  @override
  String noSnippetsBody(String braces) {
    return 'Un snippet es un comando guardado que envías a un terminal con un atajo. Lo que escribas entre $braces se pregunta al ejecutarlo.';
  }

  @override
  String get noSnippetsYet =>
      'Aún no hay snippets. Crea uno en Biblioteca › Snippets.';

  @override
  String get noTunnels => 'Aún no hay túneles';

  @override
  String get noTunnelsBody =>
      'Un túnel lleva un puerto de este equipo a un servicio que solo ve el servidor (una base de datos, un panel), o al revés. Crea uno o tráelos de tu ~/.ssh/config.';

  @override
  String get noWorkspaces => 'Aún no hay espacios de trabajo';

  @override
  String get noWorkspacesBody =>
      'Abre las pestañas y divide los paneles como los quieras, y guárdalos con «Guardar las pestañas abiertas…» (también en el menú de una pestaña y en la paleta de comandos).';

  @override
  String get notNow => 'Ahora no';

  @override
  String notResponding(String host) {
    return '$host no responde';
  }

  @override
  String get notSaved => 'sin guardar';

  @override
  String get notes => 'Notas';

  @override
  String nowIdentity(String identity) {
    return 'Ahora: $identity';
  }

  @override
  String nowIdentityFromGroup(String identity, String group) {
    return 'Ahora: $identity, del grupo $group';
  }

  @override
  String get nowNoIdentity => 'ahora: ninguna';

  @override
  String get offerOnlyTheseKeys => 'Ofrecer solo estas claves';

  @override
  String get offerOnlyTheseKeysNote =>
      'No probar las demás claves del agente (IdentitiesOnly). Útil si el servidor corta tras varios intentos.';

  @override
  String get ok => 'Aceptar';

  @override
  String get onConnect => 'Al conectar';

  @override
  String get onExit => 'Al salir del shell';

  @override
  String get onExitAlways => 'Cerrar siempre';

  @override
  String get onExitClean => 'Cerrar si sale bien';

  @override
  String get onExitHelp =>
      'Con exit o logout, el panel (o la pestaña, si es el último) se cierra solo. Si el programa acaba con un error, se queda abierto para que leas qué pasó, salvo con «Cerrar siempre». Una conexión que se corta nunca se cierra sola: sigue reconectando.';

  @override
  String get onExitNever => 'Dejarla abierta';

  @override
  String get onSecurityKey => 'En una llave de seguridad (FIDO2)';

  @override
  String get onSecurityKeyNote =>
      'Toca la llave cuando parpadee. El archivo no guarda ningún secreto: sin la llave no sirve, y nadie puede sacarla de ella.';

  @override
  String get onSend => 'Al enviar';

  @override
  String get onSessionHide => 'Oculta';

  @override
  String get onSessionKeep => 'Como esté';

  @override
  String get onSessionRail => 'En raíl';

  @override
  String get onThisComputer => 'En este equipo';

  @override
  String get onlyTheServer => 'Solo el servidor';

  @override
  String get onlyThisComputer => 'Solo este equipo (127.0.0.1)';

  @override
  String get open => 'Abrir';

  @override
  String get openATerminalFirst => 'Abre un terminal para ejecutarlo';

  @override
  String get openAction => 'Abrir';

  @override
  String openCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count abiertos',
      one: '1 abierto',
    );
    return '$_temp0';
  }

  @override
  String get openLocal => 'Abrir un terminal local';

  @override
  String openOnConnect(String host) {
    return 'Abrir al conectar a $host';
  }

  @override
  String get openOnConnectNote =>
      'Desde un terminal o un SFTP. Si el puerto está ocupado, la conexión sigue y el túnel avisa.';

  @override
  String get openOtherHere => 'Abrir otra cosa aquí…';

  @override
  String get openRemote => 'Abrir';

  @override
  String openRemoteFollowing(String name) {
    return '$name abierto aquí: se sube al servidor cada vez que lo guardes.';
  }

  @override
  String get openRemoteWith => 'Abrir con…';

  @override
  String get openSection => 'Abiertas';

  @override
  String get openSftp => 'Abrir SFTP';

  @override
  String openSshStillWarns(String command) {
    return 'OpenWard no modifica ~/.ssh/known_hosts: ssh seguirá avisando hasta que quites la clave vieja de allí ($command).';
  }

  @override
  String openTabsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pestañas abiertas',
      one: '1 pestaña abierta',
    );
    return '$_temp0';
  }

  @override
  String get openTunnels => 'Túneles abiertos';

  @override
  String get openRunsAction => 'Ejecutarlo';

  @override
  String openRunsBody(String type) {
    return 'Este ordenador ejecuta los archivos .$type al abrirlos, y lo que hace este lo decidió quien lo puso en el servidor. Ábrelo solo si te fías; para leerlo, usa «Abrir con…».';
  }

  @override
  String openRunsTitle(String name) {
    return '«$name» no se abre: se ejecuta';
  }

  @override
  String get openWithHelp =>
      'Un comando, como code, gedit o kate; se le pasa el archivo al final.';

  @override
  String get openWithHelpMac =>
      'El nombre de una app (TextEdit, Visual Studio Code) o un comando (/usr/local/bin/subl).';

  @override
  String get openWithProgram => 'Programa';

  @override
  String openWithTitle(String name) {
    return 'Abrir «$name» con';
  }

  @override
  String get optionAltBoth => 'Las dos';

  @override
  String get optionAltLeft => 'La izquierda';

  @override
  String get optionAltOff => 'Ninguna';

  @override
  String get optionAltRight => 'La derecha';

  @override
  String get optionAsAlt => 'Opción como Alt';

  @override
  String get optionAsAltHelp =>
      'La Opción que sea Alt envía Esc + tecla, como esperan emacs y readline; la otra sigue escribiendo símbolos como @ o €.';

  @override
  String get orAnAddress => 'o una dirección: usuario@host:puerto';

  @override
  String get orTypeAPath => 'o escribe una ruta: admite ~, %h, %r y %u';

  @override
  String ownUserWins(String user) {
    return 'Pone su propio usuario ($user), que seguirá mandando.';
  }

  @override
  String get paletteActions => 'Acciones';

  @override
  String get paletteBroadcast =>
      'Broadcast en esta pestaña (encender o apagar)';

  @override
  String get paletteChoose => 'elegir';

  @override
  String get paletteDo => 'hacer';

  @override
  String get paletteForget => 'quitar del historial';

  @override
  String get paletteHere => 'aquí';

  @override
  String get paletteHint =>
      'Busca un host, una pestaña, una acción o un comando que ya usaste…';

  @override
  String get paletteHistory => 'Historial';

  @override
  String get paletteHosts => 'Hosts';

  @override
  String get paletteNothing => 'Nada coincide.';

  @override
  String get paletteOnlyActions => 'solo acciones';

  @override
  String get paletteRecent => 'Recientes';

  @override
  String get paletteRun => 'ejecutar';

  @override
  String get paletteTabs => 'Pestañas abiertas';

  @override
  String get paletteTypeOnly => 'solo escribir';

  @override
  String get paneOpenTabs => 'Pestañas abiertas';

  @override
  String get paneOpenTabsNote => 'pasan a este panel';

  @override
  String get paneOptions => 'Opciones del panel';

  @override
  String get paneSearch => 'Busca una pestaña o un host';

  @override
  String get paneWhat => '¿Qué abres en este panel?';

  @override
  String get parityEven => 'Par';

  @override
  String get parityNone => 'Ninguna';

  @override
  String get parityOdd => 'Impar';

  @override
  String get partNote =>
      'Se copia con un nombre temporal (.part) y se renombra al terminar: si se corta, el fichero bueno no queda a medias y la copia se puede reanudar.';

  @override
  String get passphraseField => 'Frase';

  @override
  String get passphraseOptional => 'Frase de paso (opcional)';

  @override
  String get passphraseTitle => 'Frase de la clave';

  @override
  String get passphrasesDiffer => 'Las dos frases de paso no coinciden.';

  @override
  String get passwordTitle => 'Contraseña';

  @override
  String get passwordsNever =>
      'Las contraseñas no se traen nunca: OpenWard las pide al conectar.';

  @override
  String get paste => 'Pegar';

  @override
  String get pasteHasHidden =>
      'Lleva caracteres que no se ven, en ámbar: un terminal los obedece aunque no los enseñe.';

  @override
  String get pasteHiddenTitle => '¿Pegar con caracteres que no se ven?';

  @override
  String pasteInPanes(int total) {
    return 'Pegar en $total paneles';
  }

  @override
  String get pasteMultiBody =>
      'El texto contiene saltos de línea u otras secuencias que pueden ejecutar comandos al pegarlo.';

  @override
  String get pasteMultiTitle => '¿Pegar varias líneas?';

  @override
  String pasteOnlyHere(String name) {
    return 'Pegar solo en $name';
  }

  @override
  String get pause => 'Pausar';

  @override
  String get pauseAll => 'Pausar todo';

  @override
  String percent(int number) {
    return '$number %';
  }

  @override
  String permApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Permisos cambiados en $count elementos',
      one: 'Permisos cambiados en 1 elemento',
    );
    return '$_temp0';
  }

  @override
  String permBefore(String mode) {
    return 'Antes: $mode';
  }

  @override
  String get permEnter => 'Entrar';

  @override
  String get permExecute => 'Ejecutar';

  @override
  String get permGroup => 'Grupo';

  @override
  String get permOctal => 'En octal';

  @override
  String get permUnavailable => 'No se han podido leer los permisos actuales.';

  @override
  String get permLinkTarget => 'Los cambios se aplican al destino del enlace.';

  @override
  String get permSpecialNote =>
      'Tres dígitos conservan los bits especiales; cuatro los fijan en este elemento. Al aplicar recursivamente se conservan los bits especiales de cada hijo.';

  @override
  String get permOthers => 'Otros';

  @override
  String get permOwner => 'Propietario';

  @override
  String get permOwnerNote =>
      'El propietario y el grupo no se cambian desde aquí.';

  @override
  String get permRead => 'Leer';

  @override
  String get permRecursive => 'Aplicar también a lo que hay dentro';

  @override
  String get permRecursiveNote =>
      'A los ficheros solo se les deja «Ejecutar» si ya lo tenían.';

  @override
  String get permWrite => 'Escribir';

  @override
  String get permissionsEllipsis => 'Permisos…';

  @override
  String permissionsOf(String name) {
    return 'Permisos de $name';
  }

  @override
  String get persistentOff => 'No';

  @override
  String get persistentOn => 'Sí, en tmux: sigue tras un corte';

  @override
  String get persistentSession => 'Sesión persistente';

  @override
  String get pickIdentity => 'Elige una identidad o «Ninguna».';

  @override
  String get pinField => 'PIN';

  @override
  String get pinSidebar => 'Dejar la barra abierta';

  @override
  String pixels(int size) {
    return '$size px';
  }

  @override
  String get policyAcceptNew => 'Aceptar nuevas';

  @override
  String get policyAsk => 'Preguntar';

  @override
  String get policyStrict => 'Estricta';

  @override
  String get port => 'Puerto';

  @override
  String get portBusyNow => 'ocupado ahora';

  @override
  String get portHere => 'Puerto aquí';

  @override
  String portOnHost(String host) {
    return 'Puerto en $host';
  }

  @override
  String get portRange => 'El puerto va de 1 a 65535.';

  @override
  String get postQuantum => 'poscuántico';

  @override
  String postQuantumKex(String kex) {
    return '$kex (poscuántico)';
  }

  @override
  String get pressEnterAtTheEnd => 'Pulsar Intro al final';

  @override
  String get pressEnterAtTheEndNote =>
      'Apágalo para dejar el comando escrito y revisarlo antes de ejecutarlo.';

  @override
  String get preview => 'Vista previa';

  @override
  String previewCannotImport(String protocol) {
    return '$protocol: aún no se puede usar';
  }

  @override
  String previewHostsOf(int selected, int total) {
    return '$selected de $total hosts';
  }

  @override
  String previewIdentities(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count identidades',
      one: '1 identidad',
    );
    return '$_temp0';
  }

  @override
  String previewIntoExisting(String name) {
    return 'En «$name», el grupo de la importación anterior';
  }

  @override
  String get previewIntoGroup => 'Dentro del grupo';

  @override
  String get previewTrustTitle => 'Claves de host: revisar antes de confiar';

  @override
  String get previewTrustHelp =>
      'Selecciona solo las claves que hayas verificado. Esta confianza se aplica a todo el vault, incluso a hosts que no importes. Una autoridad o un patrón con comodines puede dar confianza a muchos servidores.';

  @override
  String previewKeyFound(String path) {
    return '→ $path · la misma clave pública';
  }

  @override
  String previewKeyMissing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'No está en ~/.ssh. Sin ella, los $count que la usan se quedan sin clave.',
      one: 'No está en ~/.ssh. Sin ella, quien la usa se queda sin clave.',
      zero: 'No está en ~/.ssh.',
    );
    return '$_temp0';
  }

  @override
  String get previewKeys => 'Claves';

  @override
  String previewKnownHosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts conocidos',
      one: '1 host conocido',
    );
    return '$_temp0';
  }

  @override
  String get previewLive => 'Los cambios se ven al momento en toda la ventana.';

  @override
  String previewNoPasswords(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'No se traen las $count contraseñas y frases de paso guardadas: OpenWard las pide al conectar.',
      one: 'No se trae la contraseña o frase de paso guardada: OpenWard la pide al conectar.',
    );
    return '$_temp0';
  }

  @override
  String previewSaveKey(String path) {
    return 'Guardarla en $path, que solo podrás leer tú';
  }

  @override
  String previewSnippets(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippets',
      one: '1 snippet',
    );
    return '$_temp0';
  }

  @override
  String previewSubtitle(int hosts, int groups) {
    String _temp0 = intl.Intl.pluralLogic(
      hosts,
      locale: localeName,
      other: '$hosts hosts',
      one: '1 host',
    );
    String _temp1 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: ' en $groups grupos',
      one: ' en 1 grupo',
      zero: '',
    );
    return '$_temp0$_temp1';
  }

  @override
  String previewTitle(String program) {
    return 'Importar de $program';
  }

  @override
  String previewTunnels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count túneles',
      one: '1 túnel',
    );
    return '$_temp0';
  }

  @override
  String get privateKey => 'Clave privada';

  @override
  String get protection => 'Protección';

  @override
  String get protocol => 'Protocolo';

  @override
  String get protocolSerial => 'Puerto serie';

  @override
  String get proxy => 'Proxy';

  @override
  String get proxyHttpNote =>
      'Con un proxy HTTP, la petición CONNECT va sin cifrar: el proxy ve a qué host y puerto te conectas, pero no lo que pasa por SSH.';

  @override
  String proxyLoginBody(String proxy) {
    return '$proxy pide usuario y contraseña para dejarte pasar. No se guardan.';
  }

  @override
  String get proxyLoginTitle => 'El proxy pide entrar';

  @override
  String get proxyNone => 'Sin proxy';

  @override
  String get proxyNotWithCommand => 'Con ProxyCommand no se usa el proxy.';

  @override
  String get proxyRouteTitle => 'La ruta queda así';

  @override
  String get proxyServer => 'Servidor proxy';

  @override
  String get proxyUser => 'Usuario del proxy';

  @override
  String get proxyUserHelp =>
      'Opcional. La contraseña se pide al conectar y no se guarda.';

  @override
  String publicKeyCopied(String name) {
    return 'Clave pública de $name copiada.';
  }

  @override
  String get queueAllDone => 'Todo terminado';

  @override
  String queueFailed(int count) {
    return '$count con error';
  }

  @override
  String queuePaused(int count) {
    return '$count en pausa';
  }

  @override
  String queueQueued(int count) {
    return '$count en cola';
  }

  @override
  String queueRunning(int count) {
    return '$count en curso';
  }

  @override
  String get quickConnectHint =>
      'usuario@servidor:puerto o el nombre de un host';

  @override
  String get quickConnectInvalid =>
      'Escribe una dirección como usuario@servidor:puerto.';

  @override
  String get quit => 'Salir';

  @override
  String quitBody(String what) {
    return 'Se corta: $what.';
  }

  @override
  String quitSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sesiones abiertas',
      one: '1 sesión abierta',
    );
    return '$_temp0';
  }

  @override
  String get quitTitle => '¿Salir de OpenWard?';

  @override
  String quitTransfers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transferencias en curso',
      one: '1 transferencia en curso',
    );
    return '$_temp0';
  }

  @override
  String quitTunnels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count túneles abiertos',
      one: '1 túnel abierto',
    );
    return '$_temp0';
  }

  @override
  String get readFailedTitle => 'No se ha podido leer';

  @override
  String readFormat(String program) {
    return 'Es de $program, pero no está como se esperaba (más en «Detalles»).';
  }

  @override
  String get readNotRecognized =>
      'No se reconoce de qué programa es. Elige el que exporta PuTTY (.reg), MobaXterm (.mxtsessions), SecureCRT (.xml) o el config.yaml de Tabby.';

  @override
  String get readOsRelease => 'Leer /etc/os-release';

  @override
  String get readOsReleaseEverywhere =>
      'Leer /etc/os-release en todos los hosts';

  @override
  String get readOsReleaseEverywhereHelp =>
      'Para saber el sistema de los servidores que no lo dicen al conectar. Ejecuta un comando en cada uno; un host o un grupo puede apagarlo. Solo en este equipo.';

  @override
  String get readOsReleaseNote =>
      'Para afinar el sistema; ejecuta un comando en el servidor. Apagado, no se ejecuta nada.';

  @override
  String get readOsReleaseOff => 'No';

  @override
  String get readOsReleaseOn => 'Sí, al conectar';

  @override
  String get readTermius => 'Leer Termius';

  @override
  String get readTermiusKeychain =>
      'El sistema no dejó usar la clave de Termius del llavero. Vuelve a intentarlo y elige «Permitir».';

  @override
  String get readTermiusNoKey =>
      'La clave de Termius no está en el llavero. Abre Termius una vez en este equipo y vuelve a intentarlo.';

  @override
  String get readTermiusNotFound => 'No hay datos de Termius en este equipo.';

  @override
  String get readTermiusWrongKey =>
      'La clave del llavero no abre los datos de Termius; puede que Termius haya cambiado su formato. No se ha importado nada.';

  @override
  String get readUnreadable =>
      'No se ha podido leer el archivo (más en «Detalles»).';

  @override
  String get readingFile => 'Leyendo el archivo…';

  @override
  String readingProgram(String program) {
    return 'Leyendo los datos de $program…';
  }

  @override
  String get readyBody => 'Estos atajos te llevan a casi todo:';

  @override
  String get readyTitle => 'Todo listo';

  @override
  String get receives => 'Recibe';

  @override
  String get recentConnections => 'Conexiones recientes';

  @override
  String get recentConnectionsHelp =>
      'Las conexiones que abres se guardan en este equipo (nunca en el vault) para volver a ellas desde la paleta. Los terminales locales no.';

  @override
  String get recentEmptyBody =>
      'Lo que abras saldrá aquí, con cuándo y cuánto duró, para volver con un clic.';

  @override
  String get recentEmptyTitle => 'Aún no te has conectado';

  @override
  String get reconnect => 'Reconectar';

  @override
  String get reconnectingEllipsis => 'Reconectando…';

  @override
  String reconnectingStage(String stage) {
    return 'Reconectando: $stage';
  }

  @override
  String get reduceMotion => 'Reducir movimiento';

  @override
  String get reimportNote =>
      'Si vuelves a importar, lo que ya trajiste se queda como está, con tus cambios. Solo entra lo nuevo.';

  @override
  String get reload => 'Recargar';

  @override
  String get remoteChangedBody =>
      'Alguien lo cambió desde que lo abriste aquí. Si subes tu versión, lo que cambiaron se pierde; si cancelas, tu copia sigue aquí y se vuelve a preguntar al guardar.';

  @override
  String remoteChangedTitle(String name) {
    return '«$name» cambió en el servidor';
  }

  @override
  String get remoteChangedUpload => 'Subir el mío encima';

  @override
  String remoteEditFailed(String name) {
    return '$name: no se pudo subir (más en la cola)';
  }

  @override
  String get remoteEditStop => 'Dejar de subirlo';

  @override
  String remoteEditUploaded(String name, String time) {
    return '$name: subido a las $time';
  }

  @override
  String remoteEditWatching(String name) {
    return '$name: se sube al guardarlo';
  }

  @override
  String remoteSentence(String host, String port, String dest) {
    return 'Lo que se conecte en $host al puerto $port llega a $dest de este equipo.';
  }

  @override
  String get remove => 'Quitar';

  @override
  String get removeCertificate => 'Quitar el certificado';

  @override
  String get removeFavorite => 'Quitar de favoritos';

  @override
  String get removeKey => 'Quitar la clave';

  @override
  String removeTag(String tag) {
    return 'Quitar $tag';
  }

  @override
  String get removeTheLine => 'Quitar la línea';

  @override
  String get rename => 'Renombrar';

  @override
  String get renameEllipsis => 'Renombrar…';

  @override
  String get renameTab => 'Renombrar…';

  @override
  String get renameTabHelp => 'Vacío para volver al nombre del host';

  @override
  String get renameTabTitle => 'Renombrar pestaña';

  @override
  String renameTitle(String name) {
    return 'Renombrar $name';
  }

  @override
  String get renameWorkspace => 'Renombrar el espacio de trabajo';

  @override
  String get reopenTab => 'Reabrir la pestaña cerrada';

  @override
  String get repeatPassphrase => 'Repítela';

  @override
  String get reportCopied => 'Copiado. Pégalo en tu informe.';

  @override
  String get reportCore => 'núcleo';

  @override
  String reportCounts(
    int hosts,
    int groups,
    int tunnels,
    int identities,
    int snippets,
  ) {
    return 'Hosts: $hosts · grupos: $groups · túneles: $tunnels · identidades: $identities · snippets: $snippets';
  }

  @override
  String reportCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts nuevos',
      one: '1 host nuevo',
    );
    return '$_temp0';
  }

  @override
  String get reportHow =>
      'Pégalo en la issue junto con qué hacías, qué esperabas y qué pasó, como pide la guía de prueba.';

  @override
  String get reportNotEverything => 'No todo se ha podido traer:';

  @override
  String get reportProblem => 'Informar de un problema';

  @override
  String get reportProblemEllipsis => 'Informar de un problema…';

  @override
  String get reportProblemHint =>
      'Copia la versión y el sistema para pegarlos en tu informe.';

  @override
  String reportSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ya estaban importados y no se han tocado',
      one: '1 ya estaba importado y no se ha tocado',
    );
    return '$_temp0';
  }

  @override
  String get reportText => 'texto';

  @override
  String get reportTheme => 'Tema';

  @override
  String reportTitle(int count, String program) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts importados de $program',
      one: '1 host importado de $program',
      zero: 'Nada nuevo de $program',
    );
    return '$_temp0';
  }

  @override
  String reportTunnels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count túneles nuevos',
      one: '1 túnel nuevo',
    );
    return '$_temp0';
  }

  @override
  String get reportWhat =>
      'Esto es lo que se copia. No incluye hosts, direcciones, usuarios ni claves.';

  @override
  String get reportWhere => 'Están en el grupo «~/.ssh/config».';

  @override
  String reportWhere2(String group) {
    return 'Están en el grupo «$group» de la barra lateral, con sus subgrupos.';
  }

  @override
  String get resetTheme => 'Restablecer';

  @override
  String get restart => 'Reiniciar';

  @override
  String get restorePanes => 'Volver a los paneles';

  @override
  String get resume => 'Reanudar';

  @override
  String get retry => 'Reintentar';

  @override
  String retryIn(int attempt, int max, int secs) {
    return 'Reintento $attempt de $max en $secs s.';
  }

  @override
  String get retryNow => 'Reintentar ahora';

  @override
  String get revealInExplorer => 'Mostrar en el Explorador';

  @override
  String get revealInFinder => 'Mostrar en el Finder';

  @override
  String get revealInFolder => 'Mostrar la carpeta';

  @override
  String get review => 'Revisar';

  @override
  String get reviewKey => 'Revisar la clave…';

  @override
  String get rightClickPaste => 'Pegar con clic derecho';

  @override
  String get rightClickPasteHelp =>
      'Como en PuTTY. El menú del terminal sigue con Ctrl y clic derecho.';

  @override
  String get route => 'Cómo llegar';

  @override
  String get routeDirect => 'Directo';

  @override
  String get routeJump => 'Saltando por otro host';

  @override
  String get routeStart => 'este equipo';

  @override
  String get runEllipsis => 'Ejecutar…';

  @override
  String get runIn => 'Ejecutar en…';

  @override
  String runOnHostsAction(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n hosts',
      one: '1 host',
      zero: 'ningún host',
    );
    return 'Ejecutar en $_temp0';
  }

  @override
  String get runOnHostsAll => 'Todos los mostrados';

  @override
  String get runOnHostsFilter =>
      'Filtrar por nombre, dirección, grupo o etiqueta';

  @override
  String runOnHostsMax(int max) {
    return 'Hasta $max a la vez.';
  }

  @override
  String get runOnHostsMenu => 'En varios hosts…';

  @override
  String get runOnHostsNone => 'Ninguno';

  @override
  String get runOnHostsNote =>
      'Cada host en su panel de una pestaña nueva, donde se ve su resultado. Los que ya están conectados no vuelven a iniciar sesión.';

  @override
  String runOnHostsTitle(String snippet) {
    return '«$snippet» en varios hosts';
  }

  @override
  String runSnippetBroadcast(int count) {
    return 'Va a los $count paneles que reciben el broadcast';
  }

  @override
  String get runSnippetHint => 'Rellena lo que pregunta. No se guarda.';

  @override
  String runSnippetIn(String where) {
    return 'En $where';
  }

  @override
  String runSnippetTitle(String name) {
    return 'Ejecutar «$name»';
  }

  @override
  String get snippetReviewHelp =>
      'Se enviará exactamente este texto. Revisa todas las líneas y el destino antes de continuar.';

  @override
  String get snippetStartupReview => 'Snippet al conectar';

  @override
  String get sameHost => 'el mismo host';

  @override
  String get sampleComment => 'comentario en gris';

  @override
  String get sampleError => 'error:';

  @override
  String get sampleErrorText => 'no se pudo leer .env';

  @override
  String get sampleWarning => 'aviso:';

  @override
  String get sampleWarningText => '2 migraciones pendientes';

  @override
  String get save => 'Guardar';

  @override
  String get saveAndConnect => 'Guardar y conectar';

  @override
  String get saveAndOpen => 'Guardar y abrir';

  @override
  String get saveAs => 'Guardar como';

  @override
  String get saveAsHost => 'Guardar como host…';

  @override
  String saveFailed(String error) {
    return 'No se ha podido guardar: $error';
  }

  @override
  String saveKeyFailed(String error) {
    return 'No se ha podido guardar la clave: $error';
  }

  @override
  String get saveNewHost => 'Guardar un host nuevo';

  @override
  String get saveOpenTabs => 'Guardar las pestañas abiertas…';

  @override
  String get saveTabsNeedsTabs => 'Abre alguna pestaña para poder guardarla.';

  @override
  String get saveWorkspaceIntro =>
      'Las pestañas de terminal y de archivos abiertas, con sus paneles. Al abrirlo, cada panel se conecta de nuevo.';

  @override
  String get saveWorkspaceTitle => 'Guardar como espacio de trabajo';

  @override
  String get savedHost => 'Host guardado';

  @override
  String get scrollback => 'Historial';

  @override
  String get scrollbackHelp => 'Para las pestañas nuevas.';

  @override
  String scrollbackLines(String lines) {
    return '$lines líneas';
  }

  @override
  String get search => 'Buscar';

  @override
  String get searchHosts => 'Buscar hosts';

  @override
  String get searchKeys => 'Buscar por nombre, huella o host';

  @override
  String get searchKnownHosts => 'Buscar un host, una huella…';

  @override
  String get sectionConnection => 'Conexión';

  @override
  String get sectionEnvironment => 'Entorno';

  @override
  String get sectionGeneral => 'General';

  @override
  String get sectionSystem => 'Sistema';

  @override
  String get securityKeyPill => 'Llave de seguridad';

  @override
  String securityKeyPinBody(String key) {
    return 'La clave $key pide el PIN de su llave.';
  }

  @override
  String get securityKeyPinOptional => 'PIN de la llave (si tiene)';

  @override
  String get securityKeyPinTitle => 'PIN de la llave de seguridad';

  @override
  String seenFrom(String host) {
    return 'visto desde $host';
  }

  @override
  String get seenFromHere => 'visto desde este equipo';

  @override
  String get selectAll => 'Todos';

  @override
  String get selectAllText => 'Seleccionar todo';

  @override
  String selectedCount(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seleccionados ($size)',
      one: '1 seleccionado ($size)',
    );
    return '$_temp0';
  }

  @override
  String selectedCountOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seleccionados',
      one: '1 seleccionado',
    );
    return '$_temp0';
  }

  @override
  String selectedOf(int selected, int total) {
    return '$selected de $total';
  }

  @override
  String get sendAction => 'Enviar';

  @override
  String sendToPanes(int count) {
    return 'Enviar a $count paneles';
  }

  @override
  String get separatePanes => 'Separar los paneles en pestañas';

  @override
  String get serialBaud => 'Velocidad';

  @override
  String get serialBaudMissing => 'Pon una velocidad.';

  @override
  String serialBaudUnit(int baud) {
    return '$baud baudios';
  }

  @override
  String get serialDataBits => 'Bits de datos';

  @override
  String get serialFlow => 'Control de flujo';

  @override
  String get serialLine => 'Velocidad y formato';

  @override
  String get serialOpenEllipsis => 'Abrir un puerto serie…';

  @override
  String get serialOpenNote =>
      'Para la consola de un router o un switch, con su cable: casi siempre 9600 baudios, 8N1.';

  @override
  String get serialOpenTitle => 'Abrir un puerto serie';

  @override
  String get serialParity => 'Paridad';

  @override
  String get serialPortMissing => 'Elige el puerto.';

  @override
  String get serialPortsAgain => 'Buscar otra vez';

  @override
  String get serialPortsNone => 'No hay ningún puerto serie conectado.';

  @override
  String get serialPortsTooltip => 'Los puertos de este equipo';

  @override
  String get serialSendBreak => 'Enviar un break por el puerto serie';

  @override
  String get serialShort => 'Serie';

  @override
  String get serialStopBits => 'Bits de parada';

  @override
  String serialSummary(int baud, String frame, String flow) {
    return '$baud baudios, $frame, $flow';
  }

  @override
  String get serialSummaryNoFlow => 'sin control de flujo';

  @override
  String get sessionClosed => 'Sesión cerrada.';

  @override
  String sessionClosedCode(int code) {
    return 'Sesión cerrada (código $code).';
  }

  @override
  String get sessionLog => 'Registro de sesión';

  @override
  String get sessionLogNote =>
      'Nunca lo que escribes. Se ve y se busca en Registros.';

  @override
  String get sessionLogOff => 'No';

  @override
  String get sessionLogOn => 'Sí, lo que sale en pantalla';

  @override
  String get sessionResumed => 'sesión de tmux recuperada';

  @override
  String get setHereHint => 'Un clic lo cambia solo aquí';

  @override
  String setHereIdentitySays(String value) {
    return 'Cambiado aquí; la identidad dice $value';
  }

  @override
  String setHereWouldInherit(String value) {
    return 'Cambiado aquí; heredaría $value';
  }

  @override
  String get settings => 'Ajustes';

  @override
  String get settingsAppearance => 'Apariencia';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsHighlight => 'Resaltado';

  @override
  String get settingsLogs => 'Registros';

  @override
  String get settingsMouse => 'Ratón';

  @override
  String get settingsShortcuts => 'Atajos';

  @override
  String get settingsTerminal => 'Terminal';

  @override
  String get settingsWindow => 'Ventana';

  @override
  String sftpConnected(String label) {
    return 'SFTP en $label';
  }

  @override
  String get sftpKeysApple =>
      'Intro abre · ⌘↑ sube · Tab cambia de lado · F2 renombra · ⌘⌫ elimina';

  @override
  String get sftpKeysOther =>
      'Intro abre · Retroceso sube · Tab cambia de lado · F2 renombra · Supr elimina';

  @override
  String sftpTabTitle(String label) {
    return 'SFTP · $label';
  }

  @override
  String get shape => 'Forma';

  @override
  String get shiftPrefix => 'Mayús+';

  @override
  String get shortcutAll => 'todos los atajos';

  @override
  String get shortcutConnectTyped => 'Conectar a lo escrito, en el inicio';

  @override
  String get shortcutFindNewer => 'Coincidencia siguiente, más abajo';

  @override
  String get shortcutFindOlder => 'Coincidencia anterior, más arriba';

  @override
  String get shortcutGoToPane => 'Ir al panel en esa dirección';

  @override
  String get shortcutGoToTab => 'Ir a la pestaña 1 a 8';

  @override
  String get shortcutHosts => 'Todos los hosts, en su página';

  @override
  String get shortcutLastTab => 'Ir a la última pestaña';

  @override
  String get shortcutLocal => 'Abre un terminal local';

  @override
  String get shortcutNewHost => 'Guarda un host nuevo';

  @override
  String get shortcutNextTab => 'Pestaña siguiente';

  @override
  String get shortcutPalette => 'Buscar en todo: hosts, pestañas y acciones';

  @override
  String get shortcutPermissions => 'Permisos';

  @override
  String get shortcutPreviousTab => 'Pestaña anterior';

  @override
  String get shortcutProfile => 'Atajos de';

  @override
  String get shortcutProfileHelp =>
      'Los de Mac van con ⌘ (en Windows y Linux, la tecla del sistema); los de PC, con Ctrl+Mayús.';

  @override
  String get shortcutProfileMac => 'Mac';

  @override
  String get shortcutProfilePc => 'PC';

  @override
  String get shortcutProfileSystem => 'Este equipo';

  @override
  String get shortcutSearch => 'Busca entre tus hosts';

  @override
  String get shortcutSettings => 'Abre los ajustes';

  @override
  String get shortcutSidebar => 'barra lateral';

  @override
  String get shortcutSwitchSide => 'Pasar al otro lado';

  @override
  String get shortcutTextBigger => 'Texto más grande en la pestaña';

  @override
  String get shortcutTextReset => 'Tamaño del texto de siempre';

  @override
  String get shortcutTextSmaller => 'Texto más pequeño en la pestaña';

  @override
  String get shortcutsForms => 'Editores y diálogos';

  @override
  String shortcutsNone(String query) {
    return 'Ningún atajo con «$query»';
  }

  @override
  String get shortcutsPanes => 'Paneles';

  @override
  String get shortcutsSearch => 'Buscar una acción o una tecla';

  @override
  String get shortcutsTabs => 'Pestañas';

  @override
  String get shortcutsTerminal => 'Terminal';

  @override
  String get shortcutsTitle => 'Atajos de teclado';

  @override
  String get shortcutsWindow => 'Ventana';

  @override
  String get showHiddenFiles => 'Mostrar los ocultos';

  @override
  String get showQueue => 'Ver la cola';

  @override
  String showRest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ver los $count restantes',
      one: 'Ver el que falta',
    );
    return '$_temp0';
  }

  @override
  String get showSidebar => 'Abrir la barra lateral';

  @override
  String get sidebarHelp =>
      'Se recuerda al cerrar OpenWard. Oculta, se asoma al dejar el ratón en el borde izquierdo de la ventana.';

  @override
  String get sidebarHidden => 'Oculta';

  @override
  String get sidebarOnSession => 'Con un terminal delante';

  @override
  String get sidebarOnSessionHelp =>
      'Con un terminal o un SFTP delante, la barra puede plegarse sola. En el inicio y en las páginas vuelve a como esté arriba.';

  @override
  String get sidebarOpen => 'Abierta';

  @override
  String get sidebarRail => 'Raíl';

  @override
  String get sidebarSearchHint => 'Buscar o conectar…';

  @override
  String get sidebarSetting => 'Barra lateral';

  @override
  String get sidebarWidth => 'Ancho de la barra';

  @override
  String get sidebarWidthHelp =>
      'Arrastra el borde de la barra para cambiarlo, entre 220 y 420 px. Un doble clic en el borde lo restablece.';

  @override
  String sinceSeconds(int seconds) {
    return 'desde hace $seconds s';
  }

  @override
  String get skLocked =>
      'la llave está bloqueada por demasiados PIN incorrectos: desconéctala y vuelve a conectarla';

  @override
  String get skNoAccess =>
      'Windows no deja a OpenWard hablar con la llave: usa el agente de OpenSSH de Windows (ssh-add) para las llaves de seguridad';

  @override
  String get skNoAccessLinux =>
      'Linux no deja a OpenWard abrir la llave: falta la regla de udev que da acceso a /dev/hidraw* (la instalan los paquetes libfido2 o u2f-udev)';

  @override
  String get skNoKey => 'no hay ninguna llave de seguridad conectada';

  @override
  String get skNotThisKey => 'la llave conectada no es la de esta clave';

  @override
  String get skNotTouched => 'no se tocó la llave a tiempo';

  @override
  String get skOther => 'la llave de seguridad ha fallado (más en «Detalles»)';

  @override
  String get skPinRequired => 'la llave pide su PIN';

  @override
  String get skTooManyKeys =>
      'hay más de una llave de seguridad conectada: deja solo la de esta clave';

  @override
  String get skWrongPin => 'el PIN no es el de la llave';

  @override
  String get skipGuide => 'Saltar la guía';

  @override
  String snippetDeleted(String name) {
    return 'Snippet «$name» eliminado';
  }

  @override
  String get snippetEditorHint =>
      'Comandos que envías a un terminal; lo que va entre llaves se pregunta.';

  @override
  String get snippetNeedsCommand => 'Escribe el comando.';

  @override
  String get snippetNeedsName => 'Ponle un nombre.';

  @override
  String get snippetNoSecrets =>
      'Se guarda sin secretos, como el resto del vault. Lo que escribas al ejecutarlo no se guarda.';

  @override
  String snippetScriptExample(String open, String close) {
    return 'sudo systemctl restart ${open}servicio$close';
  }

  @override
  String get snippetTypeOnlyNote => 'Se deja escrito, sin pulsar Intro.';

  @override
  String get snippetWithEnter => 'Con Intro al final.';

  @override
  String get snippets => 'Snippets';

  @override
  String snippetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippets',
      one: '1 snippet',
    );
    return '$_temp0';
  }

  @override
  String get snippetsEllipsis => 'Snippets…';

  @override
  String snippetsHowToRun(String shortcut) {
    return 'En un terminal: $shortcut o el botón «Snippets» de la barra de estado. Con broadcast, van a todos los paneles que reciben.';
  }

  @override
  String snippetsIntro(String braces) {
    return 'Comandos guardados que envías a un terminal con un atajo. Lo que va entre $braces se pregunta al ejecutarlo.';
  }

  @override
  String get splitDown => 'Dividir abajo';

  @override
  String get splitRight => 'Dividir a la derecha';

  @override
  String splitWith(String name) {
    return 'Dividir con $name';
  }

  @override
  String get splitWithNote => 'a la derecha del panel activo';

  @override
  String stageAuthenticating(String label, String hop) {
    return 'Autenticando en $label$hop…';
  }

  @override
  String stageConnecting(String label, String hop) {
    return 'Conectando con $label$hop…';
  }

  @override
  String stageOpeningSftp(String label) {
    return 'Abriendo SFTP en $label…';
  }

  @override
  String stageOpeningShell(String label) {
    return 'Abriendo el shell en $label…';
  }

  @override
  String stageTouchKey(String key) {
    return 'Toca la llave de seguridad ($key)…';
  }

  @override
  String get start => 'Empezar';

  @override
  String get startAction => 'Empezar';

  @override
  String get startColDuration => 'Duración';

  @override
  String get startHere => 'Empieza aquí';

  @override
  String get startShortcutHosts => 'todos los hosts';

  @override
  String get startShortcutLocal => 'terminal local';

  @override
  String get startShortcutNewHost => 'host nuevo';

  @override
  String get startShortcutSearch => 'buscar';

  @override
  String get startTitle => 'Inicio';

  @override
  String get starting => 'Arrancando…';

  @override
  String startupElsewhereBody(String folder) {
    return 'Otro OpenWard tiene abiertos estos datos (otra copia de la app, o una compilación de desarrollo). Ciérralo y vuelve a abrir este; no se ha cambiado nada en $folder.';
  }

  @override
  String startupErrorBody(String folder) {
    return 'Puede que los escribiera una versión más nueva de OpenWard, que la carpeta no tenga permisos o que el archivo esté dañado. No se ha borrado ni cambiado nada en $folder.';
  }

  @override
  String get startupErrorDetails => 'Detalles';

  @override
  String get startupErrorTitle => 'OpenWard no ha podido abrir sus datos';

  @override
  String startupNewerBody(String folder) {
    return 'Tus datos los guardó una versión más nueva de OpenWard. Vuelve a abrirlos con esa versión: no se ha borrado ni cambiado nada en $folder.';
  }

  @override
  String get startupQuit => 'Salir';

  @override
  String get startupShowFolder => 'Mostrar la carpeta de datos';

  @override
  String get startupSnippet => 'Snippet al conectar';

  @override
  String get startupSnippetGone =>
      'Un snippet que ya no está, o que ahora pregunta algo';

  @override
  String get startupSnippetNone => 'Ninguno';

  @override
  String get startupSnippetNote =>
      'Se escribe en cada shell nuevo en cuanto está listo: al conectar y al reconectar, no al volver a una sesión persistente tal como estaba. Solo los que no preguntan nada.';

  @override
  String get state => 'Estado';

  @override
  String get statusConnected => 'Conectado';

  @override
  String get statusConnecting => 'Conectando';

  @override
  String statusError(String error) {
    return 'Error: $error';
  }

  @override
  String get statusFailed => 'Ha fallado la conexión';

  @override
  String get statusIdle => 'Sin conectar';

  @override
  String get statusStalled => 'Sin respuesta · comprobando…';

  @override
  String get statusUnencrypted => 'Sin cifrar';

  @override
  String get stepAppearance => 'Apariencia';

  @override
  String get stepAuthenticating => 'autenticando…';

  @override
  String get stepConnecting => 'conectando…';

  @override
  String get stepImport => 'Importar';

  @override
  String get stepOpeningSftp => 'abriendo SFTP…';

  @override
  String get stepOpeningShell => 'abriendo el shell…';

  @override
  String get stepReady => 'Listo';

  @override
  String get stepTouchKey => 'toca la llave de seguridad…';

  @override
  String get stopAction => 'Detener';

  @override
  String swapWith(String name) {
    return 'Intercambiar con $name';
  }

  @override
  String get systemByBanner => 'Por el banner del servidor:';

  @override
  String get systemByOsRelease => 'Por /etc/os-release:';

  @override
  String get systemDetectAgain => 'Volver a deducirlo al conectar';

  @override
  String get systemIcon => 'Icono del sistema';

  @override
  String get systemManual => 'Elegido a mano';

  @override
  String systemNotTold(String name) {
    return '«$name» no dice su sistema al conectar.';
  }

  @override
  String get systemNotYet =>
      'Se sabrá al conectar, por el banner del servidor.';

  @override
  String systemOnNextConnection(String name) {
    return 'Se leerá al conectar a «$name».';
  }

  @override
  String systemStillUnknown(String name) {
    return '«$name» tampoco lo dice en /etc/os-release.';
  }

  @override
  String systemTold(String name, String system) {
    return '«$name» es $system.';
  }

  @override
  String get systemUnknown => 'Desconocido';

  @override
  String get systemUnknownYet => 'Aún sin saber';

  @override
  String get tabMenuHint =>
      'También puedes arrastrar la pestaña sobre un terminal para dividirlo, o a otro sitio de la barra para ordenarla.';

  @override
  String get tags => 'Etiquetas';

  @override
  String get telnetUnencrypted => 'Telnet, sin cifrar';

  @override
  String get telnetUnencryptedNote =>
      'Telnet no cifra nada: lo que escribes, contraseñas incluidas, viaja tal cual por la red. Para los equipos que no admiten SSH.';

  @override
  String get terminalAlwaysDark => 'Siempre oscuro';

  @override
  String get terminalAsTheme => 'Como el tema';

  @override
  String get terminalColors => 'Colores del terminal';

  @override
  String get terminalCursorLine => 'Línea del cursor';

  @override
  String get terminalFont => 'Fuente del terminal';

  @override
  String get terminalKeysFirst => 'Las teclas, para el terminal';

  @override
  String get terminalKeysFirstHelp =>
      'En un terminal, Ctrl+Tab, Ctrl+=, Ctrl+−, Ctrl+0, Ctrl+, y Ctrl+Alt+número llegan al programa. Los atajos con Ctrl+Mayús siguen siendo de la ventana.';

  @override
  String get terminalMenuHint =>
      'Arrastra aquí una pestaña o un host para abrirlo en una mitad de este panel.';

  @override
  String get terminalPadding => 'Margen del terminal';

  @override
  String get terminalPaddingHelp =>
      'Espacio alrededor del texto, en cada panel.';

  @override
  String get terminalScheme => 'Esquema propio';

  @override
  String get terminalSchemeApp => 'Los del tema de la app';

  @override
  String get terminalSchemeLabel => 'Colores del terminal';

  @override
  String get terminalSchemeNote =>
      'Otros colores para este host, sea cual sea el tema: para reconocer de un vistazo, por ejemplo, los de producción.';

  @override
  String terminalShortcuts(String key) {
    return '${key}F busca en el terminal y su historial. $key+ y $key− cambian el tamaño de la letra de la pestaña, y ${key}0 lo devuelve. Con $key pulsado, un clic abre un enlace.';
  }

  @override
  String get termiusBrings => 'Se trae';

  @override
  String get termiusBringsHosts => 'Hosts y grupos anidados, con sus ajustes';

  @override
  String get termiusBringsIdentities => 'Identidades: usuario y clave';

  @override
  String get termiusBringsSnippets => 'Snippets, etiquetas y hosts conocidos';

  @override
  String get termiusBringsTunnels => 'Túneles y proxy';

  @override
  String get termiusIntro =>
      'Termius guarda tus hosts cifrados en este equipo, con la clave en el llavero. Para leerlos, el sistema te va a pedir permiso: con «Permitir» basta para esta vez.';

  @override
  String get termiusLeaves => 'No se trae';

  @override
  String get termiusLeavesChains =>
      'Cadenas de saltos (host chaining): añádelas a mano';

  @override
  String get termiusLeavesKeys =>
      'Claves privadas: se busca la misma en ~/.ssh, o se guarda allí si lo pides';

  @override
  String get termiusLeavesPasswords => 'Contraseñas y frases de paso';

  @override
  String get termiusLeavesTelnet =>
      'Hosts de Telnet o serie; los de Mosh entran como SSH';

  @override
  String get termiusReadOnly =>
      'Es una lectura sin cambios: Termius no se modifica y puede seguir abierto.';

  @override
  String get termiusTitle => 'Leer los datos de Termius';

  @override
  String get termiusUnofficial =>
      'No es una función de Termius: OpenWard entiende su formato, y una versión nueva de Termius puede cambiarlo. Si algo no se entiende, no se importa nada a medias y te lo decimos.';

  @override
  String get textSize => 'Tamaño del texto';

  @override
  String get textSizeHelp =>
      'De la interfaz, sobre el del sistema. El terminal tiene el suyo.';

  @override
  String get theHost => 'el host';

  @override
  String get theLocalNetwork => 'Toda la red local';

  @override
  String get theServerNetwork => 'La red del servidor';

  @override
  String get theme => 'Tema';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get themeHelp => 'En claro, Papel; en oscuro, Grafito.';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeSystem => 'Seguir al sistema';

  @override
  String themeVariant(String name, String variant) {
    return '$name ($variant)';
  }

  @override
  String get thisComputer => 'Este equipo';

  @override
  String get time => 'Tiempo';

  @override
  String timeLeft(String time) {
    return 'quedan $time';
  }

  @override
  String get tmuxMissing => 'sin tmux';

  @override
  String get tmuxMissingTip =>
      'tmux no está en este servidor: el terminal no sobrevive a un corte. Instálalo para tener la sesión persistente.';

  @override
  String get tmuxTip =>
      'El terminal está en tmux en el servidor: sigue tras un corte. La rueda recorre su historial; Mayús y arrastrar selecciona texto.';

  @override
  String get toStart => 'Para empezar';

  @override
  String todayAt(String time) {
    return 'hoy $time';
  }

  @override
  String get toggleSidebar => 'Plegar o abrir la barra lateral';

  @override
  String get touchKeyNow => 'Toca la llave de seguridad…';

  @override
  String get transfers => 'Transferencias';

  @override
  String get trust => 'Confianza';

  @override
  String get trustAndConnect => 'Confiar y conectar';

  @override
  String trustCertified(String ca) {
    return 'certificada por la CA $ca';
  }

  @override
  String get trustKnown => 'conocida';

  @override
  String get trustNew => 'nueva, guardada ahora';

  @override
  String get trustNewKey => 'Confiar en la clave nueva';

  @override
  String get trustNewKeyEllipsis => 'Confiar en la clave nueva…';

  @override
  String trustedOn(String date) {
    return 'confiada el $date';
  }

  @override
  String get tryAgain => 'Reintentar';

  @override
  String get tryAnother => 'Probar otro';

  @override
  String get tunnelBadAddress => 'Esa dirección no existe en este equipo.';

  @override
  String get tunnelClosed => 'Detenido';

  @override
  String tunnelDeleted(String name) {
    return 'Túnel «$name» eliminado';
  }

  @override
  String tunnelDidNotOpen(String name, String why) {
    return 'No se abrió «$name» al conectar: $why';
  }

  @override
  String get tunnelEditorHint =>
      'Un puerto de este equipo que lleva a un servicio que solo ve el servidor, o al revés.';

  @override
  String get tunnelFailed => 'No se abrió';

  @override
  String get tunnelLost => 'Se cortó';

  @override
  String tunnelLostBody(String host) {
    return 'Se perdió la conexión con $host. Vuelve a abrirlo cuando haya conexión.';
  }

  @override
  String get tunnelNeedsDest => 'Falta el destino o su puerto.';

  @override
  String get tunnelNeedsHost => 'Elige el host por el que va.';

  @override
  String get tunnelNeedsName => 'Ponle un nombre.';

  @override
  String get tunnelOpen => 'Abierto';

  @override
  String tunnelOpenWith(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Abierto · $count conexiones',
      one: 'Abierto · 1 conexión',
    );
    return '$_temp0';
  }

  @override
  String get tunnelOpening => 'Abriendo…';

  @override
  String tunnelPortBusy(int port) {
    return 'el puerto $port de este equipo está ocupado.';
  }

  @override
  String tunnelRemotePortBusy(int port, String host) {
    return '$host no abrió el puerto $port (en uso o no permitido).';
  }

  @override
  String get tunnelType => 'Tipo';

  @override
  String tunnelVia(String host) {
    return 'por $host';
  }

  @override
  String get tunnels => 'Túneles';

  @override
  String tunnelsCount(int total, int open) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total túneles',
      one: '1 túnel',
    );
    String _temp1 = intl.Intl.pluralLogic(
      open,
      locale: localeName,
      other: '$open abiertos',
      one: '1 abierto',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get tunnelsIntro =>
      'Reenvíos de puertos guardados, cada uno con un host. Se abren a mano o al conectar al host, por la misma conexión que el terminal.';

  @override
  String get tunnelsKeepConnection =>
      'Un túnel abierto mantiene la conexión con su host aunque cierres la pestaña. Se cierra al cerrarlo aquí o al salir de OpenWard.';

  @override
  String tunnelsOf(String host) {
    return 'Túneles de $host';
  }

  @override
  String tunnelsOpenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count túneles abiertos',
      one: '1 túnel abierto',
    );
    return '$_temp0';
  }

  @override
  String get tunnelsStayOpen =>
      'Siguen abiertos si cierras esta pestaña. Todos en Biblioteca › Túneles.';

  @override
  String twoNames(String a, String b) {
    return '$a y $b';
  }

  @override
  String get typeAndFingerprint => 'Tipo y huella';

  @override
  String get typeOnly => 'Solo escribe';

  @override
  String get uiColors => 'Colores de la interfaz';

  @override
  String get uiFont => 'Fuente de la interfaz';

  @override
  String get undo => 'Deshacer';

  @override
  String get unknownKeyType => 'Tipo desconocido';

  @override
  String unreadableItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count elementos los guardó una versión más nueva de OpenWard: no se ven aquí, pero siguen en tus datos tal cual.',
      one: 'Un elemento lo guardó una versión más nueva de OpenWard: no se ve aquí, pero sigue en tus datos tal cual.',
    );
    return '$_temp0';
  }

  @override
  String get upOneLevel => 'Subir un nivel';

  @override
  String get updateWithOpenTabs => 'Cambiar por las pestañas abiertas';

  @override
  String get upload => 'Subida';

  @override
  String uploadToArrow(String where) {
    return 'Subir a $where →';
  }

  @override
  String uploadToHost(String host) {
    return 'Subir a $host';
  }

  @override
  String get useIdentityHint =>
      'Marca grupos o hosts. Un grupo la pasa a todos sus hosts, también a los que añadas después.';

  @override
  String useIdentityOn(String name) {
    return 'Usar «$name» en…';
  }

  @override
  String useIdentitySummary(int changed, int using) {
    String _temp0 = intl.Intl.pluralLogic(
      changed,
      locale: localeName,
      other: 'Cambian $changed hosts',
      one: 'Cambia 1 host',
      zero: 'No cambia ningún host',
    );
    String _temp1 = intl.Intl.pluralLogic(
      using,
      locale: localeName,
      other: 'la usarán $using',
      one: 'la usará 1',
      zero: 'no la usará ninguno',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get useOn => 'Usar en…';

  @override
  String usePort(int port) {
    return 'Usar el $port';
  }

  @override
  String get usedBy => 'La usan';

  @override
  String get usedByNobody => 'Nadie la usa todavía';

  @override
  String usedNotSaved(String ago) {
    return 'ya te conectaste, sin guardar · $ago';
  }

  @override
  String get user => 'Usuario';

  @override
  String get usualKeys => 'las habituales';

  @override
  String get variantDark => 'oscuro';

  @override
  String get variantDarkOnly => 'Oscuro';

  @override
  String get variantLight => 'claro';

  @override
  String get variantLightOnly => 'Claro';

  @override
  String get verificationTitle => 'Verificación';

  @override
  String get verifyRequired => 'Pedir el PIN cada vez que se use';

  @override
  String via(String hops) {
    return 'vía $hops';
  }

  @override
  String get waitingAnswer => 'Esperando respuesta…';

  @override
  String get waitingForYou => 'Espera tu respuesta';

  @override
  String warnAgentForward(String host) {
    return '$host reenviaba el agente SSH, con el que ese servidor puede usar tus claves mientras estás conectado; no se ha traído, para no hacerlo porque lo diga el archivo de otro programa.';
  }

  @override
  String warnBadValue(String subject, String at, String detail) {
    return 'Valor no válido en $subject$at: $detail.';
  }

  @override
  String warnDenied(String file) {
    return 'No hay permiso para leer $file.';
  }

  @override
  String warnFeature(String host, String feature) {
    return '$host: no se ha traído $feature.';
  }

  @override
  String warnFeatureGeneral(String feature) {
    return 'No se ha traído $feature.';
  }

  @override
  String get warnHostChain =>
      'Las cadenas de saltos de Termius no se han traído: añade los saltos a mano en cada host.';

  @override
  String warnIncludeTooDeep(String at) {
    return 'Include anidado demasiado hondo$at.';
  }

  @override
  String warnJumpLossy(String alias, String jump) {
    return '$alias salta por $jump, que no es un host importado: se guarda como dirección, sin sus claves ni su ruta.';
  }

  @override
  String warnMatch(String at) {
    return 'Bloque Match$at: OpenWard no lo evalúa y sus líneas se han saltado.';
  }

  @override
  String warnMosh(String host) {
    return '$host usaba Mosh: se conectará por SSH.';
  }

  @override
  String warnOpenTunnel(String tunnel, String address) {
    return 'El túnel $tunnel escuchaba en $address, abierto a otros equipos; llega cerrado a la red, para no abrirlo porque lo diga el archivo de otro programa. Si confías en él, ábrelo en «Quién puede usarlo».';
  }

  @override
  String warnPartlyUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos de los datos no se han podido leer.',
      one: 'Un elemento de los datos no se ha podido leer.',
    );
    return '$_temp0';
  }

  @override
  String warnProxyCommand(String host, String command) {
    return '$host usaba un ProxyCommand, que ejecuta un programa en este equipo; no se ha importado para no ejecutar lo que dice el archivo de otro programa. Si confías en él, ponlo en el host a mano: $command';
  }

  @override
  String warnShared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count elementos compartidos de un equipo no se pueden leer en este ordenador.',
      one: '1 elemento compartido de un equipo no se puede leer en este ordenador.',
    );
    return '$_temp0';
  }

  @override
  String warnStartupCommand(String host) {
    return '$host ejecutaba un comando al conectar; OpenWard aún no lo hace solo.';
  }

  @override
  String warnStricter(String at) {
    return 'StrictHostKeyChecking no$at: se importa como «aceptar nuevas»; una clave que cambia nunca se acepta sin preguntar.';
  }

  @override
  String warnTunnelAutostart(String tunnel) {
    return 'El túnel $tunnel se iniciaba automáticamente. Queda detenido hasta que lo inicies. Revisa su dirección y destino antes de activar el inicio automático.';
  }

  @override
  String warnUnreadable(String file) {
    return 'No se ha podido leer $file.';
  }

  @override
  String warnUnsupported(String subject, String at) {
    return '$subject: no se importa$at.';
  }

  @override
  String warnValue(String host, String field, String value) {
    return '$host: el valor «$value» de $field no es válido y no se ha traído.';
  }

  @override
  String get welcomeNoConfig =>
      'No hemos encontrado hosts en ~/.ssh/config. Podrás añadirlos a mano en un momento.';

  @override
  String get welcomeTitle => 'Te damos la bienvenida a OpenWard';

  @override
  String get whatsNew => 'Qué hay de nuevo';

  @override
  String get whatsNewIntro =>
      'Todo lo que hacías con tu cliente anterior, ya aquí. Lo verás una vez; está también en Ajustes › General.';

  @override
  String get whatsNewReport =>
      '¿Algo no va? Ajustes › General › Informar de un problema copia lo que hace falta para contarlo.';

  @override
  String get whereItIs => 'Dónde está';

  @override
  String get whoCanUse => 'Quién puede usarlo';

  @override
  String get withCertificate => 'con certificado';

  @override
  String get withEnter => 'Intro al final';

  @override
  String get withPassphrase => 'Con frase de paso';

  @override
  String get withoutPassphrase => 'Sin frase de paso';

  @override
  String workspaceNumbered(int number) {
    return 'Espacio $number';
  }

  @override
  String workspaceSaved(String name) {
    return '«$name» guardado.';
  }

  @override
  String workspaceSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sesiones',
      one: '1 sesión',
    );
    return '$_temp0';
  }

  @override
  String workspaceTabs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pestañas',
      one: '1 pestaña',
    );
    return '$_temp0';
  }

  @override
  String workspaceUpdated(String name) {
    return '«$name» tiene ahora las pestañas abiertas.';
  }

  @override
  String get workspaces => 'Espacios de trabajo';

  @override
  String get workspacesIntro =>
      'Pestañas y paneles guardados con un nombre, para abrirlos otra vez juntos. Se guarda a qué se conecta cada panel, nunca lo que mostraba.';

  @override
  String get wrongAnswer => 'Respuesta incorrecta.';

  @override
  String get wrongPassphrase => 'Frase incorrecta.';

  @override
  String get wrongPassword => 'Contraseña incorrecta.';

  @override
  String get wrongPin => 'El PIN no es el de la llave.';

  @override
  String get yes => 'Sí';

  @override
  String yesterdayAt(String time) {
    return 'ayer $time';
  }

  @override
  String get historyReviewTitle => 'Revisar comando del historial';

  @override
  String historyReviewFrom(String place) {
    return 'Historial de $place';
  }

  @override
  String get historyReviewTo => 'Enviar a:';

  @override
  String get historyOriginOwn => 'Escrito en este dispositivo.';

  @override
  String get historyOriginScreen =>
      'Reconstruido de la salida del terminal; puede incluir texto del servidor.';

  @override
  String get historyOriginUnknown =>
      'Se desconoce el origen de esta entrada antigua del historial.';

  @override
  String get vaultSecurity => 'Seguridad';

  @override
  String get vaultLocked => 'Vault bloqueado';

  @override
  String get vaultPassword => 'Contraseña maestra';

  @override
  String get vaultUnlock => 'Desbloquear';

  @override
  String get vaultLock => 'Bloquear ahora · ⌘L / Ctrl+Alt+L';

  @override
  String get vaultBusy => 'Autenticando…';

  @override
  String get vaultPasswordHint =>
      'Usa al menos 12 caracteres y una contraseña única.';

  @override
  String get vaultEnable => 'Cifrar este vault';

  @override
  String get vaultLegacy =>
      'Este vault todavía no está cifrado. Configura una contraseña y guarda el kit antes de activar el bloqueo.';

  @override
  String get vaultRecovery => 'Usar kit de recuperación';

  @override
  String get vaultKit => 'Kit de recuperación';

  @override
  String get vaultKitWarning =>
      'Guarda este kit fuera de OpenWard. Quien lo tenga puede abrir esta copia del vault. Si pierdes la contraseña, el kit y todos tus dispositivos, no podremos recuperar tus datos.';

  @override
  String get vaultSaved => 'He guardado el kit en un lugar seguro';

  @override
  String get vaultGroup3 => 'Grupo 3 del kit';

  @override
  String get vaultGroup12 => 'Grupo 12 del kit';

  @override
  String get vaultConfirmKit => 'Confirmar kit y cifrar';

  @override
  String get vaultConfirmPassword => 'Repetir contraseña';

  @override
  String get vaultMismatch => 'Las contraseñas no coinciden.';

  @override
  String get vaultAuthError =>
      'No se ha podido desbloquear. Comprueba la contraseña o el kit, o usa la contraseña si el sistema no autoriza el acceso. El vault se conserva.';

  @override
  String get vaultSetupError =>
      'No se ha podido completar. Comprueba la contraseña (12–128 caracteres y robusta) y la confirmación del kit. Reinicia la configuración si has cerrado el diálogo.';

  @override
  String get vaultNativeError =>
      'La protección del sistema no está disponible o se ha cancelado. Puedes seguir usando la contraseña.';

  @override
  String get vaultTouchId => 'Touch ID';

  @override
  String get vaultHello => 'Windows Hello';

  @override
  String get vaultKeyring => 'Llavero de la sesión';

  @override
  String get vaultNativeExplain =>
      'Opcional y apagado por defecto. El sistema protege una clave local para abrir este vault; la contraseña no se guarda. Al cambiar la biometría puede ser necesario volver a configurarlo.';

  @override
  String get vaultLinuxWarning =>
      'En Linux, el llavero puede liberar la clave con la sesión abierta sin pedir otra autenticación. Actívalo solo si aceptas esa protección.';

  @override
  String get vaultLinuxAccept => 'Acepto usar la protección de mi sesión';

  @override
  String get vaultNativeEnable => 'Activar desbloqueo del sistema';

  @override
  String get vaultNativeDisable => 'Desactivar desbloqueo del sistema';

  @override
  String get vaultAutoLock => 'Bloqueo automático por inactividad';

  @override
  String get vaultNever => 'Nunca';

  @override
  String get vaultSessions =>
      'Las sesiones siguen conectadas. Su contenido y entrada permanecen bloqueados hasta desbloquear.';

  @override
  String get vaultPaused =>
      'La configuración se interrumpió. El vault anterior sigue sin cifrar.';

  @override
  String get vaultResume => 'Volver a la configuración';

  @override
  String get vaultStrength => 'Robustez de la contraseña';

  @override
  String get vaultCancel => 'Cancelar';

  @override
  String get vaultKitContinue => 'Ya lo he guardado';

  @override
  String get vaultScope =>
      'El vault cifrado protege los ítems, los secretos guardados y el historial, los recientes y los registros de OpenWard. Los archivos SSH externos sólo se copian al vault cuando lo solicitas. Antes de activar el cifrado, cierra las sesiones abiertas.';

  @override
  String get vaultCompatibility =>
      'Después de cifrar, las versiones antiguas no podrán abrir este vault. Conserva el kit; no se crea una copia nueva en claro.';

  @override
  String get vaultChangePassword => 'Cambiar la contraseña';

  @override
  String get vaultRegenerateKit => 'Regenerar el kit de recuperación';

  @override
  String get vaultCurrentPassword => 'Contraseña actual';

  @override
  String get vaultNewPassword => 'Contraseña nueva';

  @override
  String get vaultChangeExplain =>
      'Autoriza el cambio con la contraseña actual o el kit. Se conservan los datos y el kit; tendrás que volver a activar el desbloqueo nativo.';

  @override
  String get vaultPasswordChanged =>
      'Contraseña cambiada. El kit sigue siendo válido.';

  @override
  String get vaultPasswordChangeError =>
      'No se cambió la contraseña. Comprueba la autorización y elige una contraseña fuerte. Si el vault se creó con una versión anterior, regenera primero el kit con la contraseña actual, o autoriza el cambio con el kit existente.';

  @override
  String get vaultRotateWarning =>
      'La contraseña actual es necesaria. El kit anterior seguirá funcionando hasta confirmar el nuevo. Guarda la nueva hoja antes de confirmar.';

  @override
  String get vaultKitCopies =>
      'El kit no contiene tus datos. Conserva una copia cifrada del vault. La regeneración no invalida los kits de copias antiguas.';

  @override
  String get vaultSavePdf => 'Guardar PDF para imprimir…';

  @override
  String get vaultPdfError =>
      'No se guardó el PDF. Elige un archivo .pdf nuevo y una carpeta con permiso de escritura.';

  @override
  String get vaultQrLabel =>
      'QR del kit de recuperación. Contiene el mismo secreto que el texto.';

  @override
  String get vaultUseKit => 'Usar el kit de recuperación';

  @override
  String get vaultConfirmReplacement => 'Activar el nuevo kit';

  @override
  String get vaultStoreKey => 'Guardar en el vault';

  @override
  String get vaultStoredKey => 'Clave privada en el vault';

  @override
  String get vaultRememberCredential =>
      'Guardar en el vault después de verificar';

  @override
  String get vaultImportPassphrase =>
      'Frase de paso del archivo, si hace falta para importarlo';

  @override
  String get vaultSelectedKeyFile =>
      'Archivo seleccionado. El núcleo leerá la clave; su contenido no se carga en este campo.';

  @override
  String get vaultMoveKeyExplain =>
      'Se guardará una copia cifrada y se actualizarán las referencias directas de hosts, grupos e identidades. El archivo original se conserva salvo que elijas eliminarlo.';

  @override
  String get vaultRemoveSource =>
      'Eliminar el archivo privado original después de verificar la copia';

  @override
  String get vaultExportKeyWarning =>
      'Se creará un archivo de clave privada fuera del vault. Protégelo; ya no dependerá del bloqueo de OpenWard.';

  @override
  String get vaultSavedCredentials => 'Credenciales guardadas';

  @override
  String get vaultCredentialExplain =>
      'Sólo se guardan cuando lo solicitas y la autenticación las verifica. Las contraseñas se vinculan al servidor, puerto, usuario y clave de host. PIN, 2FA y contraseñas de proxy no se guardan.';

  @override
  String get vaultCredentialPassword => 'Contraseña SSH';

  @override
  String get vaultCredentialPassphrase => 'Frase de paso de una clave';

  @override
  String get logsEncrypted =>
      'Los metadatos y las grabaciones se guardan cifrados. Cada sesión tiene su propia clave y puede seguir grabándose con el vault bloqueado. Las exportaciones que elijas guardar fuera quedan en claro.';

  @override
  String get vaultLocalDataError =>
      'No se pudo completar la protección de los datos locales. El vault sigue bloqueado y no se ha borrado. Comprueba el espacio y los permisos; si hay archivos dañados, restáuralos desde una copia y vuelve a intentarlo.';

  @override
  String get backupTitle => 'Copias de seguridad del vault';

  @override
  String get backupScope =>
      'Incluye los elementos del vault, las claves privadas y las credenciales guardadas. Los archivos por ruta, ajustes, historial, recientes y grabaciones son locales y no se incluyen.';

  @override
  String get backupUnlockFirst =>
      'Primero activa el cifrado y desbloquea el vault.';

  @override
  String get backupExportEncrypted => 'Exportar .owvault';

  @override
  String get backupExportJson => 'Exportar JSON en claro';

  @override
  String get backupRestore => 'Restaurar copia';

  @override
  String get backupPlaintextWarning =>
      'El JSON no está cifrado. Quien lo lea puede obtener claves privadas, contraseñas y los demás datos del vault. Guárdalo en un lugar seguro y bórralo cuando ya no lo necesites.';

  @override
  String get backupAcknowledge =>
      'Entiendo que este archivo deja expuestos los datos del vault.';

  @override
  String get backupRestoreExplain =>
      'Restaura en un vault cifrado nuevo y vacío. Seguirá usando su propia contraseña y kit de recuperación. Los datos existentes nunca se reemplazan.';

  @override
  String get backupUseKit => 'Abrir .owvault con su kit de recuperación';

  @override
  String get backupCredentialExplain =>
      'Para .owvault, escribe la contraseña o el kit que tenía al crear esa copia. Para JSON, deja este campo vacío.';

  @override
  String get backupSourceCredential => 'Contraseña o kit de la copia';

  @override
  String get backupPreview => 'Comprobar copia';

  @override
  String get backupNeedsEmpty =>
      'Este vault no está vacío. Usa una carpeta de datos nueva y crea allí un vault cifrado antes de restaurar.';

  @override
  String get backupConfirmRestore =>
      'Restaurar los datos comprobados en este vault vacío.';

  @override
  String get backupFailed =>
      'No se pudo completar la operación. Revisa la credencial, versión e integridad del archivo, permisos del destino y espacio libre. Los datos existentes no se han reemplazado.';

  @override
  String get backupExported =>
      'Copia guardada. Conserva su contraseña o kit de recuperación por separado.';

  @override
  String get backupRestored =>
      'Vault restaurado. Comprueba los hosts y claves antes de conectar.';

  @override
  String get backupSave => 'Guardar copia';

  @override
  String backupSummary(int items, int secrets, int unreadable) {
    return '$items elementos, $secrets secretos guardados, $unreadable elementos conservados para una versión posterior.';
  }

  @override
  String get vaultOnboardingTitle => 'Protege tu vault';

  @override
  String get vaultOnboardingBody =>
      'Crea una contraseña maestra y guarda el kit de recuperación antes de usar OpenWard. Los datos existentes se migran en su ubicación. Guarda el kit fuera del equipo: sin contraseña, kit o método de desbloqueo habilitado, no se puede recuperar el vault.';

  @override
  String get vaultLater => 'Más tarde · proteger en este equipo';

  @override
  String get vaultDeviceWarning =>
      'Protección temporal: cifrado con una clave del llavero de esta cuenta del sistema. Quien acceda a esa cuenta podrá desbloquearlo. Mover o perder el llavero puede impedir recuperar el vault. Crea una contraseña y guarda el kit para recuperarlo en otro equipo y hacer copias.';

  @override
  String get vaultDeviceReminder =>
      'Contraseña y kit pendientes · protegido solo por esta cuenta del sistema';

  @override
  String get vaultFinishSetup => 'Crear contraseña y kit';

  @override
  String get vaultDeviceUnlock => 'Desbloquear con esta cuenta del sistema';

  @override
  String get vaultDeviceError =>
      'Clave del equipo no disponible. Desbloquea el llavero original del sistema y reinténtalo. La configuración no ha terminado; tus datos no se muestran.';

  @override
  String get vaultProtectedStatus => 'Cifrado · contraseña y kit configurados';

  @override
  String get newsVaultTitle => 'Tu vault cifrado';

  @override
  String get newsVaultBody =>
      'Contraseña maestra, desbloqueo opcional del sistema, bloqueo automático y credenciales, historial y registros de sesión cifrados. Ajustes › Seguridad reúne los controles.';

  @override
  String get newsRecoveryTitle => 'Recuperación y copias portables';

  @override
  String get newsRecoveryBody =>
      'Guarda el kit fuera del equipo, cambia la contraseña y exporta o restaura copias .owvault. La exportación JSON está en claro y requiere contraseña y confirmación.';

  @override
  String get vaultMissingKitStatus => 'Cifrado · kit de recuperación pendiente';

  @override
  String get enclaveCreate => 'Crear en Secure Enclave (Touch ID)';

  @override
  String get enclaveNote =>
      'Clave ECDSA P-256 no exportable, protegida por Touch ID. Solo funciona en este Mac. Las copias del vault guardan su referencia, pero no permiten recuperar la clave privada. Conserva otra forma de entrar en tus servidores.';

  @override
  String get enclaveStored => 'Secure Enclave · vinculada al Mac';

  @override
  String get enclaveName => 'Nombre de la clave';

  @override
  String get enclaveDelete =>
      'La clave privada se eliminará de este Mac y no se puede recuperar desde una copia del vault. Revoca también la clave pública en los servidores donde la instalaste.';

  @override
  String get enclaveBusy => 'Autoriza la firma con Touch ID…';

  @override
  String stageTouchId(Object key) {
    return 'Autoriza con Touch ID la firma SSH de $key…';
  }

  @override
  String get chooseSshKey => 'Elegir clave SSH';

  @override
  String get chooseSshKeyFile => 'Elegir archivo de clave…';

  @override
  String get keyBarCtrl => 'Control (se mantiene para la siguiente tecla)';

  @override
  String get keyBarAlt => 'Alt (se mantiene para la siguiente tecla)';

  @override
  String get keyBarLeft => 'Flecha izquierda';

  @override
  String get keyBarUp => 'Flecha arriba';

  @override
  String get keyBarDown => 'Flecha abajo';

  @override
  String get keyBarRight => 'Flecha derecha';

  @override
  String get keyBarHome => 'Inicio';

  @override
  String get keyBarEnd => 'Fin';

  @override
  String get keyBarPageUp => 'RePág';

  @override
  String get keyBarPageDown => 'AvPág';

  @override
  String get keyBarHideKeyboard => 'Ocultar el teclado';

  @override
  String get keyBarShowKeyboard => 'Mostrar el teclado';

  @override
  String get mobileHostsMenu => 'Hosts y biblioteca';

  @override
  String mobileTabs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pestañas abiertas',
      one: '1 pestaña abierta',
    );
    return '$_temp0';
  }

  @override
  String get mobileSftpHere => 'Abrir SFTP de este host';

  @override
  String get mobileBiggerText => 'Letra más grande';

  @override
  String get mobileSmallerText => 'Letra más pequeña';

  @override
  String get vaultFaceId => 'Face ID o Touch ID';

  @override
  String get vaultBiometricAndroid => 'Huella o rostro';

  @override
  String get mobileSaveTo => 'Guardar en…';

  @override
  String get mobileImportFiles => 'Importar archivos del teléfono…';
}
