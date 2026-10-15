// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String aboutVersion(String version) {
    return 'OpenWard $version';
  }

  @override
  String get accessibility => 'Accesibilidad';

  @override
  String get add => 'Añadir';

  @override
  String get addSavedHost => 'Añadir un host guardado';

  @override
  String get addTag => 'Añadir';

  @override
  String get address => 'Dirección';

  @override
  String get addressHint => 'servidor.example.com o 10.0.0.5';

  @override
  String get agent => 'Agente SSH';

  @override
  String get agentNone => 'Ninguno';

  @override
  String get agentSocket => 'Otro socket…';

  @override
  String get agentSystem => 'El del sistema';

  @override
  String get alreadyImported => 'ya importado';

  @override
  String get appearanceStepBody =>
      'Puedes cambiarlo cuando quieras en Ajustes.';

  @override
  String get appearanceStepTitle => '¿Cómo la quieres ver?';

  @override
  String get asSystem => 'Como el sistema';

  @override
  String get back => 'Atrás';

  @override
  String get bellFlash => 'Destello con la campana';

  @override
  String get bellFlashHelp =>
      'Cuando un programa hace sonar la campana. Si la pestaña no está delante, se marca igualmente.';

  @override
  String get bellRang => 'Ha sonado la campana';

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
  String get cancel => 'Cancelar';

  @override
  String get cancelled => 'Cancelado.';

  @override
  String cannotConnect(String label) {
    return 'No se ha podido conectar con $label';
  }

  @override
  String get change => 'Cambiar';

  @override
  String get changedMeanwhile =>
      'Otro cambio ha llegado antes: cierra y vuelve a abrir el editor.';

  @override
  String get checkedFingerprint => 'He comprobado la huella nueva';

  @override
  String get cipher => 'Cifrado';

  @override
  String get clear => 'Quitar';

  @override
  String get clearSelection => 'Quitar la selección';

  @override
  String get close => 'Cerrar';

  @override
  String get closePane => 'Cerrar el panel';

  @override
  String get closeTab => 'Cerrar la pestaña';

  @override
  String get closeTheTab => 'Cerrar la pestaña';

  @override
  String get connect => 'Conectar';

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
      'Lo que no cambies aquí se hereda. Debajo de cada valor ves de dónde viene; los heredados llevan el borde discontinuo.';

  @override
  String connectionLost(String label, String why) {
    return 'Se perdió la conexión con $label$why.';
  }

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
  String get copyFingerprint => 'Copiar la huella';

  @override
  String get ctrlShiftPrefix => 'Ctrl+Mayús+';

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
  String get delete => 'Eliminar';

  @override
  String deleteFailed(String error) {
    return 'No se ha podido eliminar: $error';
  }

  @override
  String get deleteGroup => 'Eliminar grupo';

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
  String get deletedHost => '(host eliminado)';

  @override
  String get destination => 'Destino';

  @override
  String get dontTrust => 'No confiar';

  @override
  String get editEllipsis => 'Editar…';

  @override
  String get editGroup => 'Editar grupo…';

  @override
  String get editGroupTitle => 'Editar grupo';

  @override
  String get editHostTitle => 'Editar host';

  @override
  String failureAuth(String user, String label) {
    return '$user@$label no ha podido autenticarse.';
  }

  @override
  String failureAuthMethods(String user, String label, String methods) {
    return '$user@$label no ha podido autenticarse (el servidor acepta: $methods).';
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
  String get findClose => 'Cerrar la búsqueda (Esc)';

  @override
  String findCount(int selected, int total) {
    return '$selected de $total';
  }

  @override
  String get findHint => 'Buscar en el terminal';

  @override
  String get findNewer => 'Siguiente, más abajo (Mayús+Intro)';

  @override
  String get findOlder => 'Anterior, más arriba (Intro)';

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
  String firstConnectionTo(String label) {
    return 'Primera conexión con $label';
  }

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
  String get fromDefault => 'Valor por defecto';

  @override
  String fromGroup(String name) {
    return 'Del grupo $name';
  }

  @override
  String get fromNowhere => 'Sin valor: lo decide la conexión';

  @override
  String get group => 'Grupo';

  @override
  String get groupInsideItself => 'Un grupo no puede estar dentro de sí mismo.';

  @override
  String get groupNeedsName => 'El grupo necesita un nombre.';

  @override
  String get groupSettingsSection => 'Ajustes para todo lo que contiene';

  @override
  String hostInUse(String name) {
    return 'Otros hosts saltan por «$name»: cámbialos antes de eliminarlo.';
  }

  @override
  String get hostKey => 'Clave del host';

  @override
  String hostKeyUnknownBody(String where) {
    return 'OpenWard aún no conoce la clave de $where. Compara la huella con la que te dé quien administra el servidor antes de confiar en ella.';
  }

  @override
  String get hostKeys => 'Claves de host nuevas';

  @override
  String get hostNeedsName => 'El host necesita un nombre.';

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
  String get importIntoGroup =>
      'Se guardan en el grupo «~/.ssh/config». Un host trae consigo los hosts por los que salta.';

  @override
  String get importKeepsFile =>
      'El fichero no se toca, y las claves se quedan donde están: OpenWard guarda la ruta, nunca la clave.';

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
  String get importScheme => 'Importar de iTerm2 o Ghostty…';

  @override
  String importSchemeDone(String name) {
    return '«$name» importado y puesto en el terminal.';
  }

  @override
  String get importSchemeFailed =>
      'Ese fichero no es un tema de iTerm2 (.itermcolors) ni de Ghostty.';

  @override
  String get importSshConfigMenu => 'Importar de ~/.ssh/config…';

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
  String get inputNotSent => 'Lo que escribas ahora no se envía.';

  @override
  String get inside => 'Dentro de';

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
  String get keyExchange => 'Intercambio';

  @override
  String get keyInKnownHosts => 'en ~/.ssh/known_hosts';

  @override
  String get keyInOpenWard => 'guardada en OpenWard';

  @override
  String keyNow(String algorithm) {
    return 'Ahora ($algorithm)';
  }

  @override
  String keyProtected(String key) {
    return 'La clave $key está protegida.';
  }

  @override
  String get keyReceived => 'Recibida';

  @override
  String get keySaved => 'Guardada';

  @override
  String get keys => 'Claves';

  @override
  String get keysHelp =>
      'Una ruta por línea. OpenWard guarda la ruta, nunca la clave.';

  @override
  String get language => 'Idioma';

  @override
  String get languageSystem => 'Como el sistema';

  @override
  String get licenses => 'Licencias';

  @override
  String get lightAndDark => 'Claro y oscuro';

  @override
  String get lineHeight => 'Interlineado del terminal';

  @override
  String linkNotOpened(String scheme) {
    return 'Los enlaces «$scheme:» no se abren desde el terminal.';
  }

  @override
  String get localTerminal => 'Terminal local';

  @override
  String get localUser => 'tu usuario local';

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
  String get missingProxyCommand => 'Falta el ProxyCommand.';

  @override
  String get missingSocket => 'Falta la ruta del socket del agente.';

  @override
  String get moreActions => 'Más acciones';

  @override
  String get moreOptions => 'Más opciones';

  @override
  String get name => 'Nombre';

  @override
  String get netLost => 'se ha perdido la conexión.';

  @override
  String get netNotFound => 'no se encuentra el host.';

  @override
  String get netRefused => 'conexión rechazada.';

  @override
  String get netTimeout => 'tiempo de espera agotado.';

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
  String get newLocalTerminal => 'Terminal local nuevo';

  @override
  String get newPane => 'Panel nuevo';

  @override
  String get newSubgroup => 'Nuevo subgrupo';

  @override
  String get next => 'Siguiente';

  @override
  String get no => 'No';

  @override
  String get noGroup => 'Sin grupo';

  @override
  String get noHostsBody => 'Añade uno o tráelos de tu ~/⁠.ssh/⁠config.';

  @override
  String get noHostsTitle => 'Aún no tienes hosts';

  @override
  String get noJumpsYet => 'Ninguno todavía.';

  @override
  String get noParent => 'Ningún grupo';

  @override
  String get noPostQuantumNote =>
      'El servidor no ofrece un intercambio poscuántico (mlkem768x25519; OpenSSH lo trae desde la 10.0).';

  @override
  String get noResults => 'Ningún host coincide.';

  @override
  String get notNow => 'Ahora no';

  @override
  String get notes => 'Notas';

  @override
  String get ok => 'Aceptar';

  @override
  String get openLocal => 'Abrir un terminal local';

  @override
  String openSshStillWarns(String command) {
    return 'OpenWard no modifica ~/.ssh/known_hosts: ssh seguirá avisando hasta que quites la clave vieja de allí ($command).';
  }

  @override
  String get optionAsAlt => 'Opción como Alt';

  @override
  String get optionAsAltHelp =>
      'Opción envía Esc + tecla, como esperan emacs y readline, en vez de escribir símbolos como @ o €.';

  @override
  String get orAnAddress => 'o una dirección: usuario@host:puerto';

  @override
  String get paneOptions => 'Opciones del panel';

  @override
  String get paneWhat => '¿Qué abres en este panel?';

  @override
  String get passphraseField => 'Frase';

  @override
  String get passphraseTitle => 'Frase de la clave';

  @override
  String get passwordTitle => 'Contraseña';

  @override
  String get paste => 'Pegar';

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
  String percent(int number) {
    return '$number %';
  }

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
  String get portRange => 'El puerto va de 1 a 65535.';

  @override
  String get postQuantum => 'poscuántico';

  @override
  String postQuantumKex(String kex) {
    return '$kex (poscuántico)';
  }

  @override
  String get preview => 'Vista previa';

  @override
  String get previewLive => 'Los cambios se ven al momento en toda la ventana.';

  @override
  String get quickConnectHint => 'usuario@servidor:puerto';

  @override
  String get quickConnectInvalid =>
      'Escribe una dirección como usuario@servidor:puerto.';

  @override
  String get readyBody => 'Estos atajos te llevan a casi todo:';

  @override
  String get readyTitle => 'Todo listo';

  @override
  String get receives => 'Recibe';

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
  String removeTag(String tag) {
    return 'Quitar $tag';
  }

  @override
  String get rename => 'Renombrar';

  @override
  String get renameTabHelp => 'Vacío para volver al nombre del host';

  @override
  String get renameTabTitle => 'Renombrar pestaña';

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
  String get reportNotEverything => 'No todo se ha podido traer:';

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
  String get reportWhere => 'Están en el grupo «~/.ssh/config».';

  @override
  String get resetTheme => 'Restablecer';

  @override
  String get restart => 'Reiniciar';

  @override
  String get restorePanes => 'Volver a los paneles';

  @override
  String retryIn(int attempt, int max, int secs) {
    return 'Reintento $attempt de $max en $secs s.';
  }

  @override
  String get retryNow => 'Reintentar ahora';

  @override
  String get reviewKey => 'Revisar la clave…';

  @override
  String get route => 'Cómo llegar';

  @override
  String get routeDirect => 'Directo';

  @override
  String get routeJump => 'Saltando por otro host';

  @override
  String get routeStart => 'este equipo';

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
  String get scrollback => 'Historial';

  @override
  String get scrollbackHelp => 'Para las pestañas nuevas.';

  @override
  String scrollbackLines(String lines) {
    return '$lines líneas';
  }

  @override
  String get searchHosts => 'Buscar hosts';

  @override
  String get sectionConnection => 'Conexión';

  @override
  String get sectionGeneral => 'General';

  @override
  String get selectAll => 'Todos';

  @override
  String get selectAllText => 'Seleccionar todo';

  @override
  String selectedOf(int selected, int total) {
    return '$selected de $total';
  }

  @override
  String get sessionClosed => 'Sesión cerrada.';

  @override
  String sessionClosedCode(int code) {
    return 'Sesión cerrada (código $code).';
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
  String get settingsTerminal => 'Terminal';

  @override
  String get shape => 'Forma';

  @override
  String get shortcutLocal => 'Abre un terminal local';

  @override
  String get shortcutNewHost => 'Guarda un host nuevo';

  @override
  String get shortcutSearch => 'Busca entre tus hosts';

  @override
  String get shortcutSettings => 'Abre los ajustes';

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
  String get skipGuide => 'Saltar la guía';

  @override
  String get splitDown => 'Dividir abajo';

  @override
  String get splitRight => 'Dividir a la derecha';

  @override
  String stageAuthenticating(String label, String hop) {
    return 'Autenticando en $label$hop…';
  }

  @override
  String stageConnecting(String label, String hop) {
    return 'Conectando con $label$hop…';
  }

  @override
  String stageOpeningShell(String label) {
    return 'Abriendo el shell en $label…';
  }

  @override
  String get start => 'Empezar';

  @override
  String get startHere => 'Empieza aquí';

  @override
  String get starting => 'Arrancando…';

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
  String get stepAppearance => 'Apariencia';

  @override
  String get stepAuthenticating => 'autenticando…';

  @override
  String get stepConnecting => 'conectando…';

  @override
  String get stepImport => 'Importar';

  @override
  String get stepOpeningShell => 'abriendo el shell…';

  @override
  String get stepReady => 'Listo';

  @override
  String get tags => 'Etiquetas';

  @override
  String get terminalAlwaysDark => 'Siempre oscuro';

  @override
  String get terminalAsTheme => 'Como el tema';

  @override
  String get terminalColors => 'Colores del terminal';

  @override
  String get terminalFont => 'Fuente del terminal';

  @override
  String get terminalScheme => 'Esquema propio';

  @override
  String terminalShortcuts(String key) {
    return '${key}F busca en el terminal y su historial. $key+ y $key− cambian el tamaño de la letra de la pestaña, y ${key}0 lo devuelve. Con $key pulsado, un clic abre un enlace.';
  }

  @override
  String get textSize => 'Tamaño del texto';

  @override
  String get textSizeHelp =>
      'De la interfaz, sobre el del sistema. El terminal tiene el suyo.';

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
  String get tryAgain => 'Reintentar';

  @override
  String get uiColors => 'Colores de la interfaz';

  @override
  String get uiFont => 'Fuente de la interfaz';

  @override
  String get user => 'Usuario';

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
  String via(String hops) {
    return 'vía $hops';
  }

  @override
  String get waitingAnswer => 'Esperando respuesta…';

  @override
  String get waitingForYou => 'Espera tu respuesta';

  @override
  String warnBadValue(String subject, String at, String detail) {
    return 'Valor no válido en $subject$at: $detail.';
  }

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
  String warnStricter(String at) {
    return 'StrictHostKeyChecking no$at: se importa como «aceptar nuevas»; una clave que cambia nunca se acepta sin preguntar.';
  }

  @override
  String warnUnreadable(String file, String error) {
    return 'No se ha podido leer $file: $error.';
  }

  @override
  String warnUnsupported(String subject, String at) {
    return '$subject: no se importa$at.';
  }

  @override
  String get welcomeNoConfig =>
      'No hemos encontrado hosts en ~/.ssh/config. Podrás añadirlos a mano en un momento.';

  @override
  String get welcomeTitle => 'Te damos la bienvenida a OpenWard';

  @override
  String get wrongAnswer => 'Respuesta incorrecta.';

  @override
  String get wrongPassphrase => 'Frase incorrecta.';

  @override
  String get wrongPassword => 'Contraseña incorrecta.';

  @override
  String get yes => 'Sí';
}
