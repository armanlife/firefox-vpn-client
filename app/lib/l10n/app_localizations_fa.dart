// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class AppLocalizationsFa extends AppLocalizations {
  AppLocalizationsFa([String locale = 'fa']) : super(locale);

  @override
  String get appTitle => 'Firefox VPN';

  @override
  String get navOverview => 'نمای کلی';

  @override
  String get navAccounts => 'حساب‌ها';

  @override
  String get navSettings => 'تنظیمات';

  @override
  String get stateConnected => 'متصل';

  @override
  String get stateConnecting => 'در حال اتصال…';

  @override
  String get stateWaiting => 'در انتظار';

  @override
  String get waitingForAccount =>
      'برای اتصال، در بخش حساب‌ها یک Firefox Account اضافه کنید.';

  @override
  String get stateError => 'خطا';

  @override
  String get stateUnknown => 'نامشخص';

  @override
  String get restartProxy => 'راه‌اندازی دوباره‌ی پروکسی';

  @override
  String copied(String value) {
    return '$value کپی شد';
  }

  @override
  String get activeAccount => 'حساب فعال';

  @override
  String get noActiveAccount => 'حساب فعالی نیست';

  @override
  String get quotaNotRead => 'حجم هنوز خوانده نشده';

  @override
  String get unlimited => 'نامحدود';

  @override
  String usedOf(String used, String limit) {
    return '$used از $limit مصرف شده';
  }

  @override
  String resets(String date) {
    return 'ریست در $date';
  }

  @override
  String switchAt(int percent) {
    return 'تعویض حساب در $percent٪';
  }

  @override
  String get publicIp => 'IP عمومی';

  @override
  String get testConnection => 'تست اتصال';

  @override
  String get testing => 'در حال تست…';

  @override
  String get testFailed => 'ناموفق';

  @override
  String milliseconds(int value) {
    return '$value میلی‌ثانیه';
  }

  @override
  String get justNow => 'همین الان';

  @override
  String minutesAgo(int n) {
    return '$n دقیقه پیش';
  }

  @override
  String hoursAgo(int n) {
    return '$n ساعت پیش';
  }

  @override
  String daysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count روز پیش',
    );
    return '$_temp0';
  }

  @override
  String atTime(String time) {
    return 'ساعت $time';
  }

  @override
  String durationDays(int d, int h) {
    return '$d روز و $h ساعت';
  }

  @override
  String durationHours(int h, int m) {
    return '$h ساعت و $m دقیقه';
  }

  @override
  String durationMinutes(int m, int s) {
    return '$m دقیقه و $s ثانیه';
  }

  @override
  String durationSeconds(int s) {
    return '$s ثانیه';
  }

  @override
  String accountsGuide(String size) {
    return 'هر حساب Firefox ماهی $size حجم دارد. می‌توانید چند حساب اضافه کنید؛ وقتی حجم یکی تمام شود، برنامه خودش به حساب بعدی می‌رود.';
  }

  @override
  String accountsOrderNote(int percent) {
    return 'حساب‌ها به ترتیب همین فهرست، هر کدام تا $percent٪ استفاده می‌شوند.';
  }

  @override
  String get addAccount => 'افزودن حساب';

  @override
  String lowQuotaNotice(String left, String size) {
    return 'حجم حساب فعلی رو به اتمام است ($left مانده). با افزودن یک حساب دیگر، $size حجم دیگر خواهید داشت.';
  }

  @override
  String get noAccounts => 'هنوز حسابی نیست';

  @override
  String get noAccountsHint => 'برای اتصال یک Firefox Account اضافه کنید.';

  @override
  String get createAccountTitle => 'حساب Firefox ندارید؟';

  @override
  String get createAccountHint =>
      'در accounts.firefox.com یک حساب رایگان بسازید، بعد برگردید و «افزودن حساب» را بزنید.';

  @override
  String get moveUp => 'بالا بردن';

  @override
  String get moveDown => 'پایین بردن';

  @override
  String get statusActive => 'فعال';

  @override
  String get statusReady => 'آماده';

  @override
  String get statusNeedsSignIn => 'نیاز به ورود';

  @override
  String get statusReserved => 'رزرو';

  @override
  String get statusUnavailable => 'در دسترس نیست';

  @override
  String statusUnavailableUntil(String date) {
    return 'تا $date در دسترس نیست';
  }

  @override
  String get statusDisabled => 'غیرفعال';

  @override
  String get statusEnabled => 'فعال';

  @override
  String get useNow => 'انتخاب';

  @override
  String get signInAgain => 'ورود دوباره';

  @override
  String get reasonQuotaThreshold =>
      'به مرز تعویض رسیده؛ بعد از ریست ماهانه دوباره استفاده می‌شود.';

  @override
  String get reasonQuotaExhausted =>
      'حجم این ماه تمام شده؛ بعد از ریست ماهانه دوباره استفاده می‌شود.';

  @override
  String get reasonSignInRequired =>
      'برای استفاده از این حساب، دوباره وارد شوید.';

  @override
  String get reasonSignInConfirm =>
      'Mozilla می‌خواهد ورود تأیید شود: «ورود دوباره» را بزنید (فقط کد لازم است).';

  @override
  String reasonSignInFailed(String detail) {
    return 'ورود خودکار ناموفق بود ($detail). دوباره وارد شوید.';
  }

  @override
  String reasonSignInWait(String time) {
    return 'ورود خودکار قبلی کمی بعد از کار افتاد؛ تلاش بعدی ساعت $time است.';
  }

  @override
  String reasonSignInRetry(String detail, String time) {
    return 'ورود خودکار کامل نشد ($detail)؛ ساعت $time دوباره تلاش می‌شود.';
  }

  @override
  String get reasonNotEntitled =>
      'Mozilla این حساب را نپذیرفت؛ بعداً دوباره تلاش می‌شود.';

  @override
  String get more => 'بیشتر';

  @override
  String get refreshQuota => 'به‌روزرسانی حجم';

  @override
  String get remove => 'حذف';

  @override
  String get removeTitle => 'حساب حذف شود؟';

  @override
  String removeBody(String name) {
    return '$name و اطلاعات ورود ذخیره‌شده‌ی آن از این کامپیوتر حذف می‌شود. بعداً می‌توانید دوباره اضافه‌اش کنید.';
  }

  @override
  String get unlimitedQuota => 'حجم نامحدود';

  @override
  String get signInTitle => 'ورود';

  @override
  String get signInIntro =>
      'با Firefox Account وارد شوید. رمز عبور فقط به هسته‌ی روی همین کامپیوتر فرستاده می‌شود.';

  @override
  String get email => 'ایمیل';

  @override
  String get emailInvalid => 'ایمیل حساب را وارد کنید';

  @override
  String get password => 'رمز عبور';

  @override
  String get passwordEmpty => 'رمز عبور را وارد کنید';

  @override
  String get show => 'نمایش';

  @override
  String get hide => 'پنهان';

  @override
  String get signIn => 'ورود';

  @override
  String get continueLabel => 'ادامه';

  @override
  String get done => 'تمام';

  @override
  String get close => 'بستن';

  @override
  String get cancel => 'انصراف';

  @override
  String get tryAgain => 'تلاش دوباره';

  @override
  String get signingIn => 'در حال ورود…';

  @override
  String get accountReady => 'حساب آماده است';

  @override
  String get accountReadyHint => 'به انتهای فهرست حساب‌ها اضافه شد.';

  @override
  String get captchaLabel => 'حروف داخل تصویر';

  @override
  String get codeLabel => 'کد';

  @override
  String get captchaBroken => 'تصویر CAPTCHA نمایش داده نشد.';

  @override
  String stepEmailCode(String email) {
    return 'Mozilla یک کد به $email فرستاد. آن را اینجا وارد کنید.';
  }

  @override
  String get stepTotp => 'کد برنامه‌ی احراز هویت (Authenticator) را وارد کنید.';

  @override
  String stepUnblockCode(String email) {
    return 'Mozilla این ورود را غیرعادی می‌داند و یک کد رفع مسدودی به $email فرستاد. آن را اینجا وارد کنید.';
  }

  @override
  String get stepCaptcha => 'حروف داخل تصویر را وارد کنید.';

  @override
  String stepEmailLink(String email) {
    return 'لینک تأییدی را که Mozilla به $email فرستاد باز کنید. ادامه‌ی کار خودکار است.';
  }

  @override
  String get coreConnecting => 'در حال اتصال به هسته…';

  @override
  String get coreLost => 'ارتباط با هسته قطع شد. در حال تلاش دوباره…';

  @override
  String get cantReachCore => 'دسترسی به هسته ممکن نیست';

  @override
  String get startingCore => 'در حال اجرای هسته…';

  @override
  String get retry => 'تلاش دوباره';

  @override
  String errNoCore(String path) {
    return 'برنامه‌ی هسته کنار اپ پیدا نشد ($path).';
  }

  @override
  String errCoreExited(String detail) {
    return 'هسته متوقف شد: $detail';
  }

  @override
  String get errNotAnswering => 'هسته پاسخ نمی‌دهد.';

  @override
  String get errRefused =>
      'هسته اپ را نپذیرفت؛ شاید متعلق به نسخه‌ی دیگری باشد.';

  @override
  String get settingsTitle => 'تنظیمات';

  @override
  String get sectionGeneral => 'عمومی';

  @override
  String get language => 'زبان';

  @override
  String get languageSystem => 'پیش‌فرض سیستم';

  @override
  String get theme => 'تم';

  @override
  String get themeSystem => 'سیستم';

  @override
  String get themeLight => 'روشن';

  @override
  String get themeDark => 'تیره';

  @override
  String get closeBehavior => 'هنگام بستن پنجره';

  @override
  String get closeAsk => 'هر بار بپرس';

  @override
  String get closeTray => 'پنهان شدن کنار ساعت';

  @override
  String get closeQuit => 'خروج از برنامه';

  @override
  String get sectionConnection => 'اتصال';

  @override
  String get localProxy => 'پروکسی محلی';

  @override
  String get systemProxy => 'پروکسی سیستم';

  @override
  String get sectionRouting => 'مسیریابی';

  @override
  String get routingDirect => 'اتصال مستقیم برای سایت‌های داخلی';

  @override
  String get routingDirectHint =>
      'سایت‌ها و IPهای کشور انتخاب‌شده از VPN عبور نمی‌کنند: سریع‌تر باز می‌شوند و از حجم کم نمی‌کنند.';

  @override
  String get region => 'کشور';

  @override
  String get regionIr => 'ایران';

  @override
  String get regionCn => 'چین';

  @override
  String get regionRu => 'روسیه';

  @override
  String get regionAf => 'افغانستان';

  @override
  String get regionTr => 'ترکیه';

  @override
  String get regionId => 'اندونزی';

  @override
  String get regionBr => 'برزیل';

  @override
  String get regionNone => 'هیچ‌کدام';

  @override
  String get saved => 'ذخیره شد';

  @override
  String get dataFolder => 'پوشه‌ی داده';

  @override
  String get openFolder => 'باز کردن پوشه';

  @override
  String get unofficialNote => 'کلاینت غیررسمی. وابسته به Mozilla نیست.';

  @override
  String get closeTitle => 'پنجره بسته شود؟';

  @override
  String get closeBody =>
      'وقتی برنامه کنار ساعت پنهان باشد، VPN وصل می‌ماند. با خروج، قطع می‌شود.';

  @override
  String get rememberChoice => 'انتخابم را به خاطر بسپار';

  @override
  String get minimizeToTray => 'پنهان شدن کنار ساعت';

  @override
  String get quit => 'خروج';

  @override
  String get trayOpen => 'باز کردن';

  @override
  String get trayQuit => 'خروج';

  @override
  String get trayProxyOnly => 'فقط سرویس پروکسی';

  @override
  String get traySetSystemProxy => 'تنظیم پروکسی سیستم';

  @override
  String errPortInUse(String port) {
    return 'پورت $port در اختیار برنامه‌ی دیگری است و اپ نمی‌تواند به هسته‌اش وصل شود.';
  }

  @override
  String proxyPortInUse(String port) {
    return 'پورت $port در اختیار برنامه‌ی دیگری است و پروکسی اجرا نمی‌شود.';
  }

  @override
  String get changePort => 'تغییر پورت';

  @override
  String get portDialogTitle => 'انتخاب پورت';

  @override
  String portDialogBody(String port) {
    return 'پورت $port اشغال است. یک پورت آزاد در زیر پیشنهاد شده؛ می‌توانید پورت دیگری هم وارد کنید.';
  }

  @override
  String get portChangeBody =>
      'برنامه‌ها به این پورت وصل می‌شوند. یک پورت بین 1024 تا 65535 انتخاب کنید.';

  @override
  String get portLabel => 'پورت';

  @override
  String get portInvalid => 'یک پورت بین 1024 تا 65535 وارد کنید';

  @override
  String get portBusy => 'این پورت هم اشغال است';

  @override
  String get portInUse => 'برنامه‌ی دیگری از این پورت استفاده می‌کند';

  @override
  String get save => 'ذخیره';

  @override
  String get proxyPort => 'پورت پروکسی';

  @override
  String get appPort => 'پورت اپ';

  @override
  String get welcomeTitle => 'خوش آمدید';

  @override
  String get welcomeBody =>
      'زبان و کشورتان را انتخاب کنید. سایت‌های کشورتان مستقیم و بدون VPN باز می‌شوند؛ سریع‌تر است و از حجم کم نمی‌کند.';

  @override
  String get start => 'شروع';

  @override
  String routingSuggestTitle(String country) {
    return 'مسیریابی مستقیم برای $country؟';
  }

  @override
  String routingSuggestBody(String country) {
    return 'سایت‌ها و IPهای $country مستقیم و بدون VPN باز می‌شوند. بعداً در بخش مسیریابی قابل تغییر است.';
  }

  @override
  String get yes => 'بله';

  @override
  String get notNow => 'فعلاً نه';

  @override
  String get navServers => 'سرورها';

  @override
  String get navLogs => 'لاگ‌ها';

  @override
  String get realDelay => 'تأخیر واقعی';

  @override
  String noticePort(String port) {
    return 'پروکسی Mozilla به پورت $port وصل نمی‌شود. فقط پورت‌های 80، 443، 8080 و 8443 از VPN عبور می‌کنند.';
  }

  @override
  String get noticeCommand =>
      'یک برنامه UDP خواست (بازی‌ها، تماس صوتی و تصویری). پروکسی Mozilla فقط TCP را منتقل می‌کند، پس این ترافیک عبور نمی‌کند.';

  @override
  String noticeTimes(int count, String time) {
    return '$count بار، آخرین بار $time';
  }

  @override
  String get dismiss => 'بستن';

  @override
  String get modeRecommended => 'پیشنهادی';

  @override
  String get modeFastest => 'سریع‌ترین';

  @override
  String get modeRecommendedHint => 'Mozilla مکان را برایتان انتخاب می‌کند.';

  @override
  String get modeFastestHint => 'مکانی با کمترین تأخیر در هر اتصال.';

  @override
  String get testDelay => 'تست تأخیر واقعی';

  @override
  String get testingDelay => 'در حال تست… ممکن است یک دقیقه طول بکشد';

  @override
  String get search => 'جستجو';

  @override
  String get locked => 'قفل';

  @override
  String get lockedHint =>
      'ممکن است Mozilla اجازه‌ی استفاده از این مکان را به حساب شما ندهد.';

  @override
  String get noAnswer => 'بی‌پاسخ';

  @override
  String testedAgo(String ago) {
    return 'تست‌شده $ago';
  }

  @override
  String delaySummary(int answered, int total) {
    return '$answered از $total پاسخ دادند';
  }

  @override
  String get noServers =>
      'هنوز سروری نیست. وقتی هسته به Mozilla وصل شود، سرورها نمایش داده می‌شوند.';

  @override
  String get levelAll => 'همه';

  @override
  String get filter => 'فیلتر';

  @override
  String get follow => 'اسکرول خودکار';

  @override
  String get clear => 'پاک کردن';

  @override
  String get copyAll => 'کپی';

  @override
  String get logsCopied => 'لاگ‌ها کپی شد';

  @override
  String get noLogs => 'هنوز لاگی نیست.';

  @override
  String get sectionAccounts => 'تعویض خودکار حساب';

  @override
  String get switchThreshold => 'تعویض حساب در';

  @override
  String get switchThresholdHint =>
      'وقتی این مقدار از حجم مصرف شود، حساب بعدی جایگزین می‌شود.';

  @override
  String get quotaInterval => 'بررسی حجم هر';

  @override
  String get sectionDns => 'DNS';

  @override
  String get dnsPreset => 'سرورهای DNS';

  @override
  String get dnsSystem => 'سیستم';

  @override
  String get dnsAuto => 'خودکار (Cloudflare، Google، Quad9)';

  @override
  String get dnsCustom => 'سفارشی';

  @override
  String get dnsCustomHint =>
      'هر خط یکی: https://…/dns-query، tls://… یا یک نشانی IP.';

  @override
  String get dnsFallback => 'استفاده از DNS سیستم اگر این‌ها پاسخ ندهند';

  @override
  String get testDns => 'تست DNS';

  @override
  String get transport => 'پروتکل';

  @override
  String get transportH3 => 'HTTP/3 (QUIC)';

  @override
  String get transportH2 => 'HTTP/2 (TCP)';

  @override
  String get directRules => 'مستقیم';

  @override
  String get directRulesHint =>
      'سایت‌ها و آدرس‌های این فهرست بدون VPN و مستقیم با اینترنت خودتان باز می‌شوند. قوانین کشوری که انتخاب کرده‌اید از قبل اینجا هست: می‌توانید خطی اضافه، ویرایش یا حذف کنید. با انتخاب کشور دیگر، قوانین آن کشور جایگزین می‌شوند.';

  @override
  String get restoreRegionRules => 'بازگرداندن قوانین کشور';

  @override
  String get blockRules => 'مسدود';

  @override
  String get blockRulesHint =>
      'سایت‌ها و آدرس‌های این فهرست اصلاً باز نمی‌شوند، نه مستقیم و نه از VPN: برای تبلیغات یا سایت‌هایی که نمی‌خواهید هیچ‌وقت باز شوند.';

  @override
  String get rulesTitle => 'قوانین';

  @override
  String get ruleSyntaxTitle => 'راهنمای نوشتن قانون';

  @override
  String get resolveDomains => 'اعمال قوانین IP روی دامنه‌ها';

  @override
  String get routingLists => 'فایل‌های Geo';

  @override
  String get listSource => 'منبع فهرست‌ها';

  @override
  String get listSourceCustom => 'تنظیم دستی';

  @override
  String listsUpdatedAgo(String ago) {
    return 'به‌روزرسانی: $ago';
  }

  @override
  String get updateLists => 'به‌روزرسانی فایل‌های Geo';

  @override
  String get listsUpdated => 'فایل‌های Geo به‌روز شدند.';

  @override
  String get testDestination => 'بررسی مسیر یک سایت';

  @override
  String get destinationHint => 'یک نام، نشانی یا URL';

  @override
  String get check => 'بررسی';

  @override
  String get routeDirect => 'مستقیم وصل می‌شود';

  @override
  String get routeProxy => 'از VPN رد می‌شود';

  @override
  String get routeBlock => 'مسدود';

  @override
  String ruleMatched(String rule) {
    return 'قانون: $rule';
  }

  @override
  String get portRefusedNote => 'پروکسی Mozilla به این پورت وصل نمی‌شود.';

  @override
  String get sectionAdvanced => 'پیشرفته';

  @override
  String get listenAddress => 'دسترسی به پروکسی';

  @override
  String get listenLocal => '127.0.0.1 · فقط همین دستگاه';

  @override
  String get listenAll => '0.0.0.0 · همه‌ی شبکه‌ها (LAN)';

  @override
  String get proxyUsername => 'نام کاربری پروکسی';

  @override
  String get proxyPassword => 'رمز عبور پروکسی';

  @override
  String get proxyLoginHint =>
      'برنامه‌ها برای استفاده از پروکسی باید این‌ها را وارد کنند. برای استفاده بدون رمز، هر دو را خالی بگذارید.';

  @override
  String get loginBothOrNone => 'هر دو را پر کنید، یا هر دو را خالی بگذارید.';

  @override
  String get proxyLogin => 'نام کاربری و رمز پروکسی';

  @override
  String get idleSleep => 'توقف موقت هنگام عدم استفاده';

  @override
  String get sleepNever => 'هرگز';

  @override
  String sleepMinutes(int count) {
    return '$count دقیقه';
  }

  @override
  String get sleepHour => '۱ ساعت';

  @override
  String get showPublicIp => 'نمایش IP عمومی';

  @override
  String get speedInNotification => 'نمایش سرعت در اعلان';

  @override
  String get verboseLogs => 'لاگ کامل';

  @override
  String get allowLocked => 'استفاده از مکان‌های قفل';

  @override
  String get webDashboard => 'داشبورد وب';

  @override
  String get durationInvalid => 'مدتی مثل 30s، 15m یا 6h وارد کنید';

  @override
  String numberInvalid(int min, int max) {
    return 'عددی از $min تا $max وارد کنید';
  }

  @override
  String get notifySwitchedTitle => 'حساب عوض شد';

  @override
  String notifySwitchedBody(String name) {
    return 'الان از $name استفاده می‌شود.';
  }

  @override
  String get notifySignInTitle => 'نیاز به ورود';

  @override
  String get notifySignInBody =>
      'یکی از حساب‌ها باید در صفحه‌ی حساب‌ها دوباره وارد شود.';

  @override
  String get navAbout => 'درباره';

  @override
  String get appVersionLabel => 'نسخه‌ی برنامه';

  @override
  String get coreVersionLabel => 'نسخه‌ی هسته';

  @override
  String get checkUpdates => 'بررسی به‌روزرسانی';

  @override
  String get checkingUpdates => 'در حال بررسی…';

  @override
  String get upToDate => 'آخرین نسخه را دارید.';

  @override
  String updateAvailable(String version) {
    return 'نسخه‌ی $version منتشر شده است.';
  }

  @override
  String get download => 'دانلود';

  @override
  String updateCheckFailed(String error) {
    return 'بررسی به‌روزرسانی ممکن نشد: $error';
  }

  @override
  String get repoNotSet => 'آدرس مخزن گیت‌هاب هنوز تنظیم نشده است.';

  @override
  String get sourceCode => 'کد منبع';

  @override
  String get tapToConnect => 'برای اتصال کلیک کنید';

  @override
  String get tapToDisconnect => 'برای قطع اتصال کلیک کنید';

  @override
  String get startWithWindows => 'اجرا با روشن شدن ویندوز';

  @override
  String get proxyServiceActive => 'سرویس پروکسی فعال';

  @override
  String get navHome => 'خانه';

  @override
  String get groupVpn => 'VPN';

  @override
  String get groupApp => 'برنامه';

  @override
  String get stateOff => 'قطع';

  @override
  String get tapToConnectPhone => 'برای اتصال ضربه بزنید';

  @override
  String get tapToDisconnectPhone => 'برای قطع اتصال ضربه بزنید';

  @override
  String lanAddress(String address) {
    return 'شبکه‌ی محلی $address';
  }

  @override
  String get recommendedLocation => 'مکان پیشنهادی';

  @override
  String dataLeftOf(String limit) {
    return 'از $limit';
  }

  @override
  String get homeLocation => 'مکان';

  @override
  String get connectedTo => 'متصل به';

  @override
  String get vpnNotAllowed =>
      'VPN به اجازه‌ی شما نیاز دارد. دوباره دکمه را بزنید و اجازه دهید.';

  @override
  String get dataUsedTitle => 'حجم مصرف‌شده';

  @override
  String get bypassApps => 'انتخاب برنامه‌ها';

  @override
  String get connectRetrying =>
      'اتصال برقرار نشد. اینترنت را بررسی کنید؛ دوباره تلاش می‌کنیم…';

  @override
  String get appModeExclude => 'اتصال مستقیم برنامه‌های انتخاب‌شده';

  @override
  String get appModeInclude => 'فقط برنامه‌های انتخاب‌شده از VPN';

  @override
  String get appModeExcludeHint =>
      'برنامه‌های انتخاب‌شده مستقیم وصل می‌شوند، نه از VPN؛ مثلاً اپ‌های بانکی که آدرس خارجی را نمی‌پذیرند.';

  @override
  String get appModeIncludeHint =>
      'فقط برنامه‌های انتخاب‌شده از VPN رد می‌شوند؛ بقیه مستقیم وصل می‌شوند.';

  @override
  String fromRegionList(String region) {
    return 'پیشنهادی: در فهرست $region';
  }

  @override
  String get modeProxy => 'پروکسی';

  @override
  String get connectionMode => 'حالت اتصال';

  @override
  String get modeProxyHint =>
      'فقط برنامه‌هایی که برای پروکسی تنظیم شده‌اند از آن استفاده می‌کنند؛ تنظیمات ویندوز تغییر نمی‌کند.';

  @override
  String get modeSystemProxyHint =>
      'ویندوز و بیشتر برنامه‌ها از پروکسی رد می‌شوند.';

  @override
  String get suggestedApps => 'برنامه‌های پیشنهادی';

  @override
  String suggestedAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count برنامه‌ی پیشنهادی انتخاب شد',
      zero: 'برنامه‌های پیشنهادی از قبل انتخاب شده‌اند',
    );
    return '$_temp0';
  }

  @override
  String get autoSection => 'خودکار';

  @override
  String get locationsSection => 'مکان‌ها';

  @override
  String get hideLocked => 'پنهان کردن مکان‌های قفل';

  @override
  String showLocked(int count) {
    return 'نمایش مکان‌های قفل ($count)';
  }

  @override
  String get dnsSummaryOk => 'DNS رمزنگاری‌شده کار می‌کند';

  @override
  String dnsSummaryFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نام پیدا نشد',
    );
    return '$_temp0';
  }

  @override
  String dnsVia(String server) {
    return 'از طریق $server';
  }

  @override
  String dnsSummaryDiffers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'DNS شبکه‌ی شما برای $count نام آدرس فیلترینگ داد. این برنامه برای آن‌ها از آن استفاده نمی‌کند.',
    );
    return '$_temp0';
  }

  @override
  String get dnsAnswer => 'پاسخ:';

  @override
  String get dnsNetworkAnswer => 'DNS شبکه:';

  @override
  String get dnsFiltered => 'فیلتر شده';

  @override
  String get rulesSyntaxTitle => 'هر خط یک قانون';

  @override
  String get ruleDomain => 'سایت و زیردامنه‌هایش';

  @override
  String get ruleFull => 'دقیقاً همین نام';

  @override
  String get ruleKeyword => 'نام‌هایی که این کلمه را دارند';

  @override
  String get ruleGeosite => 'سایت‌های یک برچسب در فایل‌های Geo';

  @override
  String get ruleGeoip => 'آدرس‌های یک کشور در فایل‌های Geo';

  @override
  String get ruleIp => 'یک آدرس یا یک شبکه';

  @override
  String get modeVpn => 'VPN';

  @override
  String get modeProxyOnly => 'فقط پروکسی';

  @override
  String get noNetwork =>
      'اتصال اینترنت برقرار نیست. Wi-Fi یا داده‌ی همراه را روشن کنید.';

  @override
  String get blockAds => 'مسدود کردن تبلیغات';
}
