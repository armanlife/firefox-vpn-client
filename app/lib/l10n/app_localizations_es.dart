// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Firefox VPN';

  @override
  String get navOverview => 'Resumen';

  @override
  String get navAccounts => 'Cuentas';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get stateConnected => 'Conectado';

  @override
  String get stateConnecting => 'Conectando…';

  @override
  String get stateWaiting => 'En espera';

  @override
  String get waitingForAccount =>
      'Agregue una Firefox Account en la página Cuentas para conectarse.';

  @override
  String get stateError => 'Error';

  @override
  String get stateUnknown => 'Desconocido';

  @override
  String get restartProxy => 'Reiniciar el proxy';

  @override
  String copied(String value) {
    return 'Copiado: $value';
  }

  @override
  String get activeAccount => 'Cuenta activa';

  @override
  String get noActiveAccount => 'Sin cuenta activa';

  @override
  String get quotaNotRead => 'Uso de datos aún sin consultar';

  @override
  String get unlimited => 'Ilimitado';

  @override
  String usedOf(String used, String limit) {
    return '$used de $limit usados';
  }

  @override
  String resets(String date) {
    return 'se reinicia el $date';
  }

  @override
  String switchAt(int percent) {
    return 'Cambia de cuenta al $percent %';
  }

  @override
  String get publicIp => 'IP pública';

  @override
  String get testConnection => 'Probar conexión';

  @override
  String get testing => 'Probando…';

  @override
  String get testFailed => 'Falló';

  @override
  String milliseconds(int value) {
    return '$value ms';
  }

  @override
  String get justNow => 'ahora mismo';

  @override
  String minutesAgo(int n) {
    return 'hace $n min';
  }

  @override
  String hoursAgo(int n) {
    return 'hace $n h';
  }

  @override
  String daysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hace $count días',
      one: 'hace 1 día',
    );
    return '$_temp0';
  }

  @override
  String atTime(String time) {
    return 'a las $time';
  }

  @override
  String durationDays(int d, int h) {
    return '$d d $h h';
  }

  @override
  String durationHours(int h, int m) {
    return '$h h $m min';
  }

  @override
  String durationMinutes(int m, int s) {
    return '$m min $s s';
  }

  @override
  String durationSeconds(int s) {
    return '$s s';
  }

  @override
  String accountsGuide(String size) {
    return 'Cada Firefox Account tiene $size de datos al mes. Puede agregar varias: cuando una se agota, la aplicación pasa sola a la siguiente.';
  }

  @override
  String accountsOrderNote(int percent) {
    return 'Se usan en el orden de esta lista, cada una hasta el $percent %.';
  }

  @override
  String get addAccount => 'Agregar cuenta';

  @override
  String lowQuotaNotice(String left, String size) {
    return 'Los datos de la cuenta actual se están agotando (quedan $left). Agregue otra cuenta para tener $size más.';
  }

  @override
  String get noAccounts => 'Aún no hay cuentas';

  @override
  String get noAccountsHint => 'Agregue una Firefox Account para conectarse.';

  @override
  String get createAccountTitle => '¿No tiene una Firefox Account?';

  @override
  String get createAccountHint =>
      'Cree una gratis en accounts.firefox.com, vuelva aquí y pulse Agregar cuenta.';

  @override
  String get moveUp => 'Subir';

  @override
  String get moveDown => 'Bajar';

  @override
  String get statusActive => 'Activa';

  @override
  String get statusReady => 'Lista';

  @override
  String get statusNeedsSignIn => 'Requiere iniciar sesión';

  @override
  String get statusReserved => 'Reservada';

  @override
  String get statusUnavailable => 'No disponible';

  @override
  String statusUnavailableUntil(String date) {
    return 'No disponible hasta $date';
  }

  @override
  String get statusDisabled => 'Desactivada';

  @override
  String get statusEnabled => 'Activada';

  @override
  String get useNow => 'Usar ahora';

  @override
  String get signInAgain => 'Volver a iniciar sesión';

  @override
  String get reasonQuotaThreshold =>
      'Llegó a su punto de cambio; se vuelve a usar tras el reinicio mensual.';

  @override
  String get reasonQuotaExhausted =>
      'Los datos de este mes se agotaron; se vuelve a usar tras el reinicio mensual.';

  @override
  String get reasonSignInRequired =>
      'Inicie sesión de nuevo para usar esta cuenta.';

  @override
  String get reasonSignInConfirm =>
      'Mozilla pide confirmar el inicio de sesión: pulse «Volver a iniciar sesión» (solo hace falta el código).';

  @override
  String reasonSignInFailed(String detail) {
    return 'El inicio de sesión automático falló ($detail). Inicie sesión de nuevo.';
  }

  @override
  String reasonSignInWait(String time) {
    return 'El último inicio de sesión automático dejó de funcionar al poco tiempo; el próximo intento es a las $time.';
  }

  @override
  String reasonSignInRetry(String detail, String time) {
    return 'El inicio de sesión automático no terminó ($detail); se reintentará a las $time.';
  }

  @override
  String get reasonNotEntitled =>
      'Mozilla rechazó esta cuenta; se reintentará más tarde.';

  @override
  String get more => 'Más';

  @override
  String get refreshQuota => 'Actualizar uso de datos';

  @override
  String get remove => 'Quitar';

  @override
  String get removeTitle => '¿Quitar la cuenta?';

  @override
  String removeBody(String name) {
    return '$name y su inicio de sesión guardado se quitarán de este equipo. Puede agregarla de nuevo más tarde.';
  }

  @override
  String get unlimitedQuota => 'Datos ilimitados';

  @override
  String get signInTitle => 'Iniciar sesión';

  @override
  String get signInIntro =>
      'Inicie sesión con una Firefox Account. La contraseña solo se envía al núcleo en este equipo.';

  @override
  String get email => 'Correo electrónico';

  @override
  String get emailInvalid => 'Ingrese el correo de la cuenta';

  @override
  String get password => 'Contraseña';

  @override
  String get passwordEmpty => 'Ingrese la contraseña';

  @override
  String get show => 'Mostrar';

  @override
  String get hide => 'Ocultar';

  @override
  String get signIn => 'Iniciar sesión';

  @override
  String get continueLabel => 'Continuar';

  @override
  String get done => 'Listo';

  @override
  String get close => 'Cerrar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get tryAgain => 'Reintentar';

  @override
  String get signingIn => 'Iniciando sesión…';

  @override
  String get accountReady => 'Cuenta lista';

  @override
  String get accountReadyHint => 'Se agregó al final de la lista de cuentas.';

  @override
  String get captchaLabel => 'Caracteres de la imagen';

  @override
  String get codeLabel => 'Código';

  @override
  String get captchaBroken => 'No se pudo mostrar la imagen CAPTCHA.';

  @override
  String stepEmailCode(String email) {
    return 'Mozilla envió un código a $email. Ingréselo aquí.';
  }

  @override
  String get stepTotp => 'Ingrese el código de su app de autenticación.';

  @override
  String stepUnblockCode(String email) {
    return 'Mozilla considera inusual este inicio de sesión y envió un código de desbloqueo a $email. Ingréselo aquí.';
  }

  @override
  String get stepCaptcha => 'Escriba los caracteres de la imagen.';

  @override
  String stepEmailLink(String email) {
    return 'Abra el enlace de confirmación que Mozilla envió a $email. El proceso continuará automáticamente.';
  }

  @override
  String get coreConnecting => 'Conectando al núcleo…';

  @override
  String get coreLost => 'Se perdió la conexión con el núcleo. Reintentando…';

  @override
  String get cantReachCore => 'No se puede contactar al núcleo';

  @override
  String get startingCore => 'Iniciando el núcleo…';

  @override
  String get retry => 'Reintentar';

  @override
  String errNoCore(String path) {
    return 'No se encontró el programa del núcleo junto a la app ($path).';
  }

  @override
  String errCoreExited(String detail) {
    return 'El núcleo se detuvo: $detail';
  }

  @override
  String get errNotAnswering => 'El núcleo no responde.';

  @override
  String get errRefused =>
      'El núcleo rechazó la app; puede que pertenezca a otra copia.';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get sectionGeneral => 'General';

  @override
  String get language => 'Idioma';

  @override
  String get languageSystem => 'Predeterminado del sistema';

  @override
  String get theme => 'Tema';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get closeBehavior => 'Al cerrar la ventana';

  @override
  String get closeAsk => 'Preguntar siempre';

  @override
  String get closeTray => 'Minimizar a la bandeja';

  @override
  String get closeQuit => 'Salir de la app';

  @override
  String get sectionConnection => 'Conexión';

  @override
  String get localProxy => 'Proxy local';

  @override
  String get systemProxy => 'Proxy del sistema';

  @override
  String get sectionRouting => 'Enrutamiento';

  @override
  String get routingDirect => 'Conexión directa para sitios locales';

  @override
  String get routingDirectHint =>
      'Los sitios e IP del país elegido no pasan por la VPN: abren más rápido y ahorran datos.';

  @override
  String get region => 'País';

  @override
  String get regionIr => 'Irán';

  @override
  String get regionCn => 'China';

  @override
  String get regionRu => 'Rusia';

  @override
  String get regionAf => 'Afganistán';

  @override
  String get regionTr => 'Turquía';

  @override
  String get regionId => 'Indonesia';

  @override
  String get regionBr => 'Brasil';

  @override
  String get regionNone => 'Ninguno';

  @override
  String get saved => 'Guardado';

  @override
  String get dataFolder => 'Carpeta de datos';

  @override
  String get openFolder => 'Abrir carpeta';

  @override
  String get unofficialNote =>
      'Cliente no oficial. Sin afiliación con Mozilla.';

  @override
  String get closeTitle => '¿Cerrar la ventana?';

  @override
  String get closeBody =>
      'Si la minimiza a la bandeja, la VPN sigue conectada. Si sale, se desconecta.';

  @override
  String get rememberChoice => 'Recordar mi elección';

  @override
  String get minimizeToTray => 'Minimizar a la bandeja';

  @override
  String get quit => 'Salir';

  @override
  String get trayOpen => 'Abrir';

  @override
  String get trayQuit => 'Salir';

  @override
  String get trayProxyOnly => 'Solo servicio proxy';

  @override
  String get traySetSystemProxy => 'Configurar proxy del sistema';

  @override
  String errPortInUse(String port) {
    return 'Otro programa usa el puerto $port, por lo que la app no puede contactar a su núcleo.';
  }

  @override
  String proxyPortInUse(String port) {
    return 'Otro programa usa el puerto $port, por lo que el proxy no puede iniciarse.';
  }

  @override
  String get changePort => 'Cambiar puerto';

  @override
  String get portDialogTitle => 'Elija un puerto';

  @override
  String portDialogBody(String port) {
    return 'El puerto $port está ocupado. Abajo se sugiere un puerto libre; puede escribir otro.';
  }

  @override
  String get portChangeBody =>
      'Las aplicaciones se conectan a este puerto. Elija uno entre 1024 y 65535.';

  @override
  String get portLabel => 'Puerto';

  @override
  String get portInvalid => 'Ingrese un puerto entre 1024 y 65535';

  @override
  String get portBusy => 'Este puerto también está en uso';

  @override
  String get portInUse => 'Otro programa usa este puerto';

  @override
  String get save => 'Guardar';

  @override
  String get proxyPort => 'Puerto del proxy';

  @override
  String get appPort => 'Puerto de la app';

  @override
  String get welcomeTitle => 'Bienvenido';

  @override
  String get welcomeBody =>
      'Elija su idioma y su país. Los sitios de su país se abren directamente, sin la VPN: cargan más rápido y ahorran datos.';

  @override
  String get start => 'Comenzar';

  @override
  String routingSuggestTitle(String country) {
    return '¿Conexión directa para $country?';
  }

  @override
  String routingSuggestBody(String country) {
    return 'Los sitios e IP de $country se abrirían directamente, sin la VPN. Puede cambiarlo en Enrutamiento.';
  }

  @override
  String get yes => 'Sí';

  @override
  String get notNow => 'Ahora no';

  @override
  String get navServers => 'Servidores';

  @override
  String get navLogs => 'Registros';

  @override
  String get realDelay => 'Latencia real';

  @override
  String noticePort(String port) {
    return 'El proxy de Mozilla no se conecta al puerto $port. Solo los puertos 80, 443, 8080 y 8443 pasan por la VPN.';
  }

  @override
  String get noticeCommand =>
      'Una app solicitó UDP (juegos, llamadas de voz y video). El proxy de Mozilla solo transporta TCP, así que no puede pasar por la VPN.';

  @override
  String noticeTimes(int count, String time) {
    return '$count veces, la última $time';
  }

  @override
  String get dismiss => 'Descartar';

  @override
  String get modeRecommended => 'Recomendada';

  @override
  String get modeFastest => 'La más rápida';

  @override
  String get modeRecommendedHint => 'Mozilla elige la ubicación por usted.';

  @override
  String get modeFastestHint =>
      'La ubicación con menor latencia en cada conexión.';

  @override
  String get testDelay => 'Medir latencia real';

  @override
  String get testingDelay => 'Probando… puede tardar un minuto';

  @override
  String get search => 'Buscar';

  @override
  String get locked => 'Bloqueada';

  @override
  String get lockedHint =>
      'Es posible que Mozilla no permita a su cuenta usar esta ubicación.';

  @override
  String get noAnswer => 'Sin respuesta';

  @override
  String testedAgo(String ago) {
    return 'Probado $ago';
  }

  @override
  String delaySummary(int answered, int total) {
    return '$answered de $total respondieron';
  }

  @override
  String get noServers =>
      'Aún no hay servidores. Aparecerán cuando el núcleo contacte a Mozilla.';

  @override
  String get levelAll => 'Todos';

  @override
  String get filter => 'Filtrar';

  @override
  String get follow => 'Desplazamiento automático';

  @override
  String get clear => 'Borrar';

  @override
  String get copyAll => 'Copiar';

  @override
  String get logsCopied => 'Registros copiados';

  @override
  String get noLogs => 'Aún no hay líneas de registro.';

  @override
  String get sectionAccounts => 'Cambio automático de cuenta';

  @override
  String get switchThreshold => 'Cambiar de cuenta al';

  @override
  String get switchThresholdHint =>
      'La siguiente cuenta toma el relevo cuando se consume este porcentaje de los datos.';

  @override
  String get quotaInterval => 'Revisar el uso de datos cada';

  @override
  String get sectionDns => 'DNS';

  @override
  String get dnsPreset => 'Servidores DNS';

  @override
  String get dnsSystem => 'Sistema';

  @override
  String get dnsAuto => 'Automático (Cloudflare, Google, Quad9)';

  @override
  String get dnsCustom => 'Personalizado';

  @override
  String get dnsCustomHint =>
      'Uno por línea: https://…/dns-query, tls://… o una dirección IP.';

  @override
  String get dnsFallback => 'Usar el DNS del sistema como respaldo';

  @override
  String get testDns => 'Probar DNS';

  @override
  String get transport => 'Protocolo';

  @override
  String get transportH3 => 'HTTP/3 (QUIC)';

  @override
  String get transportH2 => 'HTTP/2 (TCP)';

  @override
  String get directRules => 'Directo';

  @override
  String get directRulesHint =>
      'Los sitios y direcciones de esta lista se abren sin la VPN, directamente con tu propia conexión. Las reglas del país elegido ya están aquí: añade, cambia o quita líneas. Elegir otro país las reemplaza por las suyas.';

  @override
  String get restoreRegionRules => 'Restaurar las reglas del país';

  @override
  String get blockRules => 'Bloquear';

  @override
  String get blockRulesHint =>
      'Los sitios y direcciones de esta lista no se abren en absoluto, ni directamente ni a través de la VPN: para anuncios o sitios que nunca quieres abrir.';

  @override
  String get rulesTitle => 'Reglas';

  @override
  String get ruleSyntaxTitle => 'Cómo escribir una regla';

  @override
  String get resolveDomains => 'Aplicar reglas de IP a dominios';

  @override
  String get routingLists => 'Archivos geo';

  @override
  String get listSource => 'Origen de las listas';

  @override
  String get listSourceCustom => 'Manual';

  @override
  String listsUpdatedAgo(String ago) {
    return 'Actualizado $ago';
  }

  @override
  String get updateLists => 'Actualizar los archivos geo';

  @override
  String get listsUpdated => 'Los archivos geo se actualizaron.';

  @override
  String get testDestination => 'Comprobar la ruta de un sitio';

  @override
  String get destinationHint => 'Un nombre, una dirección o una URL';

  @override
  String get check => 'Comprobar';

  @override
  String get routeDirect => 'Conexión directa';

  @override
  String get routeProxy => 'Pasa por la VPN';

  @override
  String get routeBlock => 'Bloqueado';

  @override
  String ruleMatched(String rule) {
    return 'Regla: $rule';
  }

  @override
  String get portRefusedNote =>
      'El proxy de Mozilla no se conecta a este puerto.';

  @override
  String get sectionAdvanced => 'Avanzado';

  @override
  String get listenAddress => 'Acceso al proxy';

  @override
  String get listenLocal => '127.0.0.1 · solo este dispositivo';

  @override
  String get listenAll => '0.0.0.0 · todas las redes (LAN)';

  @override
  String get proxyUsername => 'Usuario del proxy';

  @override
  String get proxyPassword => 'Contraseña del proxy';

  @override
  String get proxyLoginHint =>
      'Las apps deberán usar este usuario y contraseña. Deje ambos vacíos para no pedirlos.';

  @override
  String get loginBothOrNone => 'Complete ambos o deje ambos vacíos.';

  @override
  String get proxyLogin => 'Usuario y contraseña del proxy';

  @override
  String get idleSleep => 'Suspender tras inactividad';

  @override
  String get sleepNever => 'Nunca';

  @override
  String sleepMinutes(int count) {
    return '$count minutos';
  }

  @override
  String get sleepHour => '1 hora';

  @override
  String get showPublicIp => 'Mostrar la IP pública';

  @override
  String get speedInNotification => 'Mostrar la velocidad en la notificación';

  @override
  String get verboseLogs => 'Registros detallados';

  @override
  String get allowLocked => 'Permitir ubicaciones bloqueadas';

  @override
  String get webDashboard => 'Panel web';

  @override
  String get durationInvalid => 'Use una duración como 30s, 15m o 6h';

  @override
  String numberInvalid(int min, int max) {
    return 'Ingrese un número entre $min y $max';
  }

  @override
  String get notifySwitchedTitle => 'Se cambió de cuenta';

  @override
  String notifySwitchedBody(String name) {
    return 'Ahora se usa $name.';
  }

  @override
  String get notifySignInTitle => 'Se requiere iniciar sesión';

  @override
  String get notifySignInBody =>
      'Una cuenta necesita volver a iniciar sesión. Vaya a la página Cuentas.';

  @override
  String get navAbout => 'Acerca de';

  @override
  String get appVersionLabel => 'Versión de la app';

  @override
  String get coreVersionLabel => 'Versión del núcleo';

  @override
  String get checkUpdates => 'Buscar actualizaciones';

  @override
  String get checkingUpdates => 'Buscando…';

  @override
  String get upToDate => 'Tiene la última versión.';

  @override
  String updateAvailable(String version) {
    return 'La versión $version está disponible.';
  }

  @override
  String get download => 'Descargar';

  @override
  String updateCheckFailed(String error) {
    return 'No se pudieron buscar actualizaciones: $error';
  }

  @override
  String get repoNotSet => 'El repositorio de GitHub aún no está configurado.';

  @override
  String get sourceCode => 'Código fuente';

  @override
  String get tapToConnect => 'Haga clic para conectar';

  @override
  String get tapToDisconnect => 'Haga clic para desconectar';

  @override
  String get startWithWindows => 'Iniciar con Windows';

  @override
  String get startAtSignIn => 'Iniciar al iniciar sesión';

  @override
  String get proxyServiceActive => 'Servicio de proxy activo';

  @override
  String get navHome => 'Inicio';

  @override
  String get groupVpn => 'VPN';

  @override
  String get groupApp => 'App';

  @override
  String get stateOff => 'Desconectado';

  @override
  String get tapToConnectPhone => 'Toque para conectar';

  @override
  String get tapToDisconnectPhone => 'Toque para desconectar';

  @override
  String lanAddress(String address) {
    return 'LAN $address';
  }

  @override
  String get recommendedLocation => 'Ubicación recomendada';

  @override
  String dataLeftOf(String limit) {
    return 'de $limit';
  }

  @override
  String get homeLocation => 'Ubicación';

  @override
  String get connectedTo => 'Conectado a';

  @override
  String get vpnNotAllowed =>
      'La VPN necesita su permiso. Toque el botón de nuevo y permítalo.';

  @override
  String get dataUsedTitle => 'Datos usados';

  @override
  String get bypassApps => 'Proxy por app';

  @override
  String get connectRetrying =>
      'Sin conexión. Revise su internet; reintentando…';

  @override
  String get appModeExclude => 'Excluir apps seleccionadas';

  @override
  String get appModeInclude => 'Solo apps seleccionadas';

  @override
  String get appModeExcludeHint =>
      'Las apps seleccionadas se conectan directamente, sin la VPN: por ejemplo, apps bancarias que rechazan direcciones extranjeras.';

  @override
  String get appModeIncludeHint =>
      'Solo las apps seleccionadas pasan por la VPN; las demás se conectan directamente.';

  @override
  String fromRegionList(String region) {
    return 'Sugerida: en la lista de $region';
  }

  @override
  String get modeProxy => 'Proxy';

  @override
  String get connectionMode => 'Modo de conexión';

  @override
  String get modeProxyHint =>
      'Solo las apps configuradas para usar el proxy pasan por él; no se cambia nada en Windows.';

  @override
  String get modeSystemProxyHint =>
      'Windows y la mayoría de las apps pasan por el proxy.';

  @override
  String get modeProxyHintLinux =>
      'Solo las apps configuradas para usar el proxy pasan por él; no se cambia nada en el sistema.';

  @override
  String get modeSystemProxyHintLinux =>
      'Los navegadores y la mayoría de las apps pasan por el proxy.';

  @override
  String get suggestedApps => 'Apps sugeridas';

  @override
  String suggestedAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count apps sugeridas seleccionadas',
      one: '1 app sugerida seleccionada',
      zero: 'Las apps sugeridas ya están seleccionadas',
    );
    return '$_temp0';
  }

  @override
  String get autoSection => 'Automático';

  @override
  String get locationsSection => 'Ubicaciones';

  @override
  String get hideLocked => 'Ocultar ubicaciones bloqueadas';

  @override
  String showLocked(int count) {
    return 'Mostrar ubicaciones bloqueadas ($count)';
  }

  @override
  String get dnsSummaryOk => 'El DNS cifrado funciona';

  @override
  String dnsSummaryFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nombres no se resolvieron',
      one: '1 nombre no se resolvió',
    );
    return '$_temp0';
  }

  @override
  String dnsVia(String server) {
    return 'a través de $server';
  }

  @override
  String dnsSummaryDiffers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'El DNS de su red respondió a $count nombres con una dirección de filtrado. Esta app no lo usa para esos nombres.',
      one: 'El DNS de su red respondió a 1 nombre con una dirección de filtrado. Esta app no lo usa para ese nombre.',
    );
    return '$_temp0';
  }

  @override
  String get dnsAnswer => 'Respuesta:';

  @override
  String get dnsNetworkAnswer => 'DNS de la red:';

  @override
  String get dnsFiltered => 'filtrado';

  @override
  String get rulesSyntaxTitle => 'Una regla por línea';

  @override
  String get ruleDomain => 'El sitio y sus subdominios';

  @override
  String get ruleFull => 'Exactamente este nombre';

  @override
  String get ruleKeyword => 'Nombres que contienen la palabra';

  @override
  String get ruleGeosite => 'Sitios de una etiqueta en los archivos geo';

  @override
  String get ruleGeoip => 'Direcciones de un país en los archivos geo';

  @override
  String get ruleIp => 'Una dirección o una red';

  @override
  String get modeVpn => 'VPN';

  @override
  String get modeProxyOnly => 'Solo proxy';

  @override
  String get noNetwork =>
      'Sin conexión a internet. Active el Wi-Fi o los datos móviles.';

  @override
  String get blockAds => 'Bloquear anuncios';
}
