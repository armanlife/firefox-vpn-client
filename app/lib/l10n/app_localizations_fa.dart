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
  String get waitingForEnabledAccount =>
      'همه حساب‌ها خاموش هستند. یکی را در صفحه حساب‌ها روشن کنید.';

  @override
  String get stateError => 'خطا';

  @override
  String get stateUnknown => 'نامشخص';

  @override
  String get restartProxy => 'راه‌اندازی دوباره پروکسی';

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
    return 'به ترتیب همین فهرست؛ هر حساب تا $percent٪ و آخرین حساب تا تمام شدن حجم.';
  }

  @override
  String get addAccount => 'افزودن حساب';

  @override
  String lowQuotaNotice(String size) {
    return 'حجم این حساب رو به اتمام است. با افزودن یک حساب دیگر، $size حجم بیشتر خواهید داشت.';
  }

  @override
  String get noAccounts => 'هنوز حسابی نیست';

  @override
  String get noAccountsHint => 'برای اتصال یک Firefox Account اضافه کنید.';

  @override
  String get delayTestFailed =>
      'تأخیر سرورها اندازه‌گیری نشد. اینترنت را بررسی کنید.';

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
  String reasonQuotaThreshold(int percent) {
    return 'حجم این حساب به $percent٪ رسید و حساب بعدی فعال شد.';
  }

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
    return '$name و اطلاعات ورود ذخیره‌شده آن از این کامپیوتر حذف می‌شود. بعداً می‌توانید دوباره اضافه‌اش کنید.';
  }

  @override
  String get unlimitedQuota => 'حجم نامحدود';

  @override
  String get signInTitle => 'ورود';

  @override
  String get signInIntro => 'با Firefox Account وارد شوید.';

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
  String get noBrowserTitle => 'این دستگاه مرورگر ندارد';

  @override
  String get noBrowserText => 'این آدرس را روی گوشی یا کامپیوتر باز کنید:';

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
  String get stepTotp => 'کد برنامه احراز هویت (Authenticator) را وارد کنید.';

  @override
  String stepUnblockCode(String email) {
    return 'Mozilla این ورود را غیرعادی می‌داند و یک کد رفع مسدودی به $email فرستاد. آن را اینجا وارد کنید.';
  }

  @override
  String get stepCaptcha => 'حروف داخل تصویر را وارد کنید.';

  @override
  String stepEmailLink(String email) {
    return 'لینک تأییدی را که Mozilla به $email فرستاد باز کنید. ادامه کار خودکار است.';
  }

  @override
  String get signInFailed => 'حساب اضافه نشد.';

  @override
  String get signInCancelled => 'ورود لغو شد.';

  @override
  String get signInNoAccount => 'هیچ Firefox Account با این ایمیل وجود ندارد.';

  @override
  String get signInNoAccountHint =>
      'ایمیل را بررسی کنید، یا با همین ایمیل یک Firefox Account رایگان در سایت Mozilla بسازید، آن را از صندوق ایمیلتان تأیید کنید و بعد اینجا اضافه‌اش کنید.';

  @override
  String get createAccountButton => 'ساخت Firefox Account';

  @override
  String get signInWrongPassword => 'رمز عبور اشتباه است.';

  @override
  String get signInNoPassword =>
      'این حساب رمز ندارد؛ با گوگل یا اپل ساخته شده است. یک رمز بگذارید و بعد با همان رمز اینجا وارد شوید.';

  @override
  String get setPasswordButton => 'ساختن رمز';

  @override
  String get signInTooManyAttempts =>
      'تلاش‌ها بیش از حد بود. کمی صبر کنید و دوباره امتحان کنید.';

  @override
  String get signInUnblockRejected =>
      'کد رفع مسدودی پذیرفته نشد. کد آخرین ایمیل Mozilla را وارد کنید.';

  @override
  String get signInWrongCode =>
      'کد اشتباه است یا منقضی شده. کد آخرین ایمیل Mozilla را وارد کنید؛ با ارسال کد جدید، کد قبلی دیگر کار نمی‌کند.';

  @override
  String get signInWrongTotp =>
      'کد اشتباه است. کدی را که الان برنامه احراز هویت نشان می‌دهد وارد کنید.';

  @override
  String get signInTooManyCodes =>
      'کدهای اشتباه زیادی وارد شد. ورود را از اول شروع کنید.';

  @override
  String get signInTimedOut => 'ورود بیش از حد طول کشید. دوباره شروع کنید.';

  @override
  String get signInNetwork =>
      'به Mozilla وصل نشد. اینترنت را بررسی کنید و دوباره امتحان کنید.';

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
    return 'برنامه هسته کنار اپ پیدا نشد ($path).';
  }

  @override
  String errCoreExited(String detail) {
    return 'هسته متوقف شد: $detail';
  }

  @override
  String get errNotAnswering => 'هسته پاسخ نمی‌دهد.';

  @override
  String get errRefused => 'هسته اپ را نپذیرفت؛ شاید متعلق به نسخه دیگری باشد.';

  @override
  String get settingsTitle => 'تنظیمات';

  @override
  String get sectionGeneral => 'عمومی';

  @override
  String get appSettings => 'تنظیمات برنامه';

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
      'سایت‌ها و IP های کشور انتخاب‌شده از VPN عبور نمی‌کنند: سریع‌تر باز می‌شوند و از حجم کم نمی‌کنند.';

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
  String get dataFolder => 'پوشه داده';

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
    return 'پورت $port در اختیار برنامه دیگری است و اپ نمی‌تواند به هسته‌اش وصل شود.';
  }

  @override
  String proxyPortInUse(String port) {
    return 'پورت $port در اختیار برنامه دیگری است و پروکسی اجرا نمی‌شود.';
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
  String get portInUse => 'برنامه دیگری از این پورت استفاده می‌کند';

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
    return 'سایت‌ها و IP های $country مستقیم و بدون VPN باز می‌شوند. بعداً در بخش مسیریابی قابل تغییر است.';
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
  String get noticeCommand => 'این نوع اتصال در VPN پشتیبانی نمی‌شود.';

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
  String get routeProxy => 'از VPN عبور می‌کند';

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
  String get tlsFragment => 'فرگمنت TLS';

  @override
  String get tlsFragmentOff => 'غیرفعال';

  @override
  String get tlsFragmentFirstByte => 'بایت اول';

  @override
  String get tlsFragmentSni => 'نام سرور (SNI)';

  @override
  String get tlsFragmentFirstByteHint => 'جدا شدن هدر TLS از بایت اول (0x16)';

  @override
  String get tlsFragmentSniHint => 'تقسیم نام سرور (SNI) بین چند بسته TCP';

  @override
  String get tlsFragmentOffHint => 'اتصال عادی TLS';

  @override
  String get sectionBypass => 'اگر موزیلا مسدود است';

  @override
  String get apiRelay => 'سرور رله';

  @override
  String get apiRelayHint =>
      'Cloudflare Worker خودتان، یا فایل relay.php روی هاست خودتان.\nفقط وقتی موزیلا مستقیم جواب ندهد استفاده می‌شود: لاگین، حساب‌ها و لیست سرورها از آن عبور می‌کنند، نه ترافیک VPN.';

  @override
  String get upstreamProxy => 'پروکسی بالادستی';

  @override
  String get upstreamProxyOn => 'پروکسی بالادستی روشن است';

  @override
  String get upstreamProxyAddress => 'آدرس پروکسی SOCKS5';

  @override
  String get upstreamProxyPort => 'پورت';

  @override
  String get upstreamProxyHint =>
      'اتصال به موزیلا از این پروکسی عبور می‌کند؛ برای شبکه‌هایی که موزیلا را مسدود یا کند می‌کنند.\nاگر پروکسی روی همین دستگاه است، آن را از VPN خارج کنید.';

  @override
  String get upstreamProxyInvalid =>
      'آدرس پروکسی را وارد کنید؛ مثلاً 127.0.0.1.';

  @override
  String get upstreamProxyInvalidPort => 'پورتی بین 1 تا 65535 وارد کنید.';

  @override
  String get upstreamProxyOwn =>
      'این پروکسی خود همین برنامه است. پروکسی دیگری وارد کنید.';

  @override
  String get apiRelayInvalid => 'باید یک آدرس https:// باشد.';

  @override
  String get listenAddress => 'دسترسی به پروکسی';

  @override
  String get listenLocal => '127.0.0.1 · فقط همین دستگاه';

  @override
  String get listenAll => '0.0.0.0 · همه شبکه‌ها (LAN)';

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
  String get liveTraffic => 'ترافیک لحظه‌ای';

  @override
  String get totalTraffic => 'ترافیک کل';

  @override
  String get verboseLogs => 'لاگ کامل';

  @override
  String get webDashboard => 'داشبورد وب';

  @override
  String get webDashboardOpen => 'باز کردن';

  @override
  String get webDashboardHint => 'تنظیمات پیشرفته و ابزارهای بیشتر';

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
      'یکی از حساب‌ها باید در صفحه حساب‌ها دوباره وارد شود.';

  @override
  String get navAbout => 'درباره';

  @override
  String get appVersionLabel => 'نسخه برنامه';

  @override
  String get coreVersionLabel => 'نسخه هسته';

  @override
  String get checkUpdates => 'بررسی به‌روزرسانی';

  @override
  String get checkingUpdates => 'در حال بررسی…';

  @override
  String get upToDate => 'آخرین نسخه را دارید.';

  @override
  String updateAvailable(String version) {
    return 'نسخه $version منتشر شده است.';
  }

  @override
  String get download => 'دانلود';

  @override
  String updateCheckFailed(String error) {
    return 'بررسی به‌روزرسانی ممکن نشد: $error';
  }

  @override
  String get updateNow => 'به‌روزرسانی';

  @override
  String updateDownloading(String version) {
    return 'در حال دانلود نسخه $version…';
  }

  @override
  String updateReady(String version) {
    return 'نسخه $version آماده نصب است.';
  }

  @override
  String updateInstalling(String version) {
    return 'در حال نصب نسخه $version؛ برنامه بسته و دوباره باز می‌شود.';
  }

  @override
  String updateFailed(String version) {
    return 'به‌روزرسانی به نسخه $version انجام نشد.';
  }

  @override
  String updateDone(String version) {
    return 'برنامه به نسخه $version به‌روز شد.';
  }

  @override
  String updateRolledBack(String version) {
    return 'به‌روزرسانی به نسخه $version کامل نشد و برنامه به نسخه قبلی برگشت.';
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
  String get startOnBoot => 'اجرا با روشن شدن سیستم';

  @override
  String get connectOnStartup => 'اتصال خودکار هنگام روشن شدن';

  @override
  String get proxyServiceActive => 'سرویس پروکسی فعال';

  @override
  String get navHome => 'خانه';

  @override
  String get groupApp => 'برنامه';

  @override
  String get groupNetwork => 'شبکه';

  @override
  String get stateOff => 'قطع';

  @override
  String get tapToConnectPhone => 'برای اتصال ضربه بزنید';

  @override
  String get tapToDisconnectPhone => 'برای قطع اتصال ضربه بزنید';

  @override
  String get tapToConnectTv => 'برای اتصال OK را بزنید';

  @override
  String get tapToDisconnectTv => 'برای قطع اتصال OK را بزنید';

  @override
  String lanAddress(String address) {
    return 'شبکه محلی $address';
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
      'VPN به اجازه شما نیاز دارد. دوباره دکمه را بزنید و اجازه دهید.';

  @override
  String get dataUsedTitle => 'حجم مصرف‌شده';

  @override
  String get bypassApps => 'انتخاب برنامه‌ها';

  @override
  String get connectRetrying => 'اتصال برقرار نشد. اینترنت را بررسی کنید.';

  @override
  String get failUnreachable =>
      'اتصال به سرورهای Mozilla برقرار نشد. اینترنت دیگری را امتحان کنید.';

  @override
  String get failUpstreamProxy =>
      'اتصال به Mozilla از طریق پروکسی بالادستی برقرار نشد. روشن بودن پروکسی را بررسی کنید.';

  @override
  String get failInsideVpn =>
      'این اینترنت از قبل از یک VPN عبور می‌کند. آن را خاموش کنید.';

  @override
  String get failRefused =>
      'سرور Mozilla اتصال را رد کرد. چند دقیقه دیگر دوباره امتحان کنید.';

  @override
  String get failLocationRefused =>
      'این کشور برای حساب شما باز نیست. کشور دیگری انتخاب کنید.';

  @override
  String get useRecommendedLocation => 'استفاده از مکان پیشنهادی';

  @override
  String exitMismatch(String exit, String chosen) {
    return '$chosen را انتخاب کردید، اما IP شما مال $exit است.';
  }

  @override
  String get failSignIn =>
      'ورود این حساب منقضی شده. از صفحه حساب‌ها دوباره وارد شوید.';

  @override
  String get failQuota => 'حجم این ماه تمام شده. حساب دیگری اضافه کنید.';

  @override
  String get failNotEntitled =>
      'این حساب از طرف Mozilla اجازه VPN ندارد. حساب دیگری اضافه کنید.';

  @override
  String get failRegion => 'سرویس Mozilla در کشور شما ارائه نمی‌شود.';

  @override
  String get failServer =>
      'سرویس Mozilla موقتاً مشکل دارد. برنامه خودش دوباره تلاش می‌کند.';

  @override
  String get failNoAccount => 'هیچ حسابی آماده نیست. صفحه حساب‌ها را باز کنید.';

  @override
  String get failTestSite =>
      'به سرور وصل شد، اما سایت‌ها باز نمی‌شوند. کشور دیگری را امتحان کنید.';

  @override
  String get failOther => 'اتصال برقرار نشد. دوباره امتحان کنید.';

  @override
  String get failNoInternet =>
      'اینترنت وصل نیست. Wi-Fi یا اینترنت موبایل را بررسی کنید.';

  @override
  String get waitingForNetwork => 'منتظر اتصال اینترنت…';

  @override
  String proxyStartFailed(String port) {
    return 'پروکسی روی پورت $port اجرا نشد. پورت دیگری انتخاب کنید.';
  }

  @override
  String get connectionSettings => 'تنظیمات اتصال';

  @override
  String get appModeExclude => 'اتصال مستقیم برنامه‌های انتخاب‌شده';

  @override
  String get appModeInclude => 'فقط برنامه‌های انتخاب‌شده از VPN';

  @override
  String get appModeExcludeHint =>
      'برنامه‌های انتخاب‌شده مستقیم وصل می‌شوند، نه از VPN؛ مثلاً اپ‌های بانکی که آدرس خارجی را نمی‌پذیرند.';

  @override
  String get appModeIncludeHint =>
      'فقط برنامه‌های انتخاب‌شده از VPN عبور می‌کنند؛ بقیه مستقیم وصل می‌شوند.';

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
      'فقط برنامه‌هایی که برای پروکسی تنظیم شده‌اند از آن استفاده می‌کنند.';

  @override
  String get modeSystemProxyHint =>
      'ویندوز و بیشتر برنامه‌ها از پروکسی عبور می‌کنند.';

  @override
  String get modeSystemProxyHintOther =>
      'مرورگرها و بیشتر برنامه‌ها از پروکسی عبور می‌کنند.';

  @override
  String get suggestedApps => 'برنامه‌های پیشنهادی';

  @override
  String get showSystemApps => 'نمایش برنامه‌های سیستمی';

  @override
  String suggestedAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count برنامه پیشنهادی انتخاب شد',
      zero: 'برنامه‌های پیشنهادی از قبل انتخاب شده‌اند',
    );
    return '$_temp0';
  }

  @override
  String get autoSection => 'خودکار';

  @override
  String get locationsSection => 'مکان‌ها';

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
          'DNS شبکه شما برای $count نام آدرس فیلترینگ داد. این برنامه برای آن‌ها از آن استفاده نمی‌کند.',
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
      'اتصال اینترنت برقرار نیست. اینترنت موبایل یا Wi-Fi را روشن کنید.';

  @override
  String get blockAds => 'مسدود کردن تبلیغات';

  @override
  String systemProxyTakenBy(String address) {
    return 'برنامه دیگری پروکسی سیستم را روی $address گذاشته و ترافیک از VPN نمی‌رود.';
  }

  @override
  String get systemProxyTakenOff =>
      'برنامه دیگری پروکسی سیستم را خاموش کرده و ترافیک از VPN نمی‌رود.';

  @override
  String get setSystemProxyAgain => 'دوباره تنظیم کن';

  @override
  String get modeTun => 'حالت TUN';

  @override
  String modeTunHint(String os) {
    return 'کل ترافیک $os از VPN عبور می‌کند.';
  }

  @override
  String get osWindows => 'ویندوز';

  @override
  String get osLinux => 'لینوکس';

  @override
  String get osMacos => 'مک';

  @override
  String get tunInstallWaiting => 'در انتظار اجازه برای نصب سرویس TUN…';

  @override
  String get tunInstallCancelled =>
      'حالت TUN یک بار اجازه Administrator لازم دارد. این اجازه داده نشد و حالت عوض نشد.';

  @override
  String tunInstallFailed(String error) {
    return 'نصب سرویس TUN ممکن نشد: $error';
  }

  @override
  String get tunStarting => 'در حال روشن کردن حالت TUN…';

  @override
  String get tunFailed => 'حالت TUN روشن نشد؛ دوباره تلاش می‌شود…';

  @override
  String get tunLost => 'حالت TUN ناگهان خاموش شد؛ دوباره تلاش می‌شود…';

  @override
  String get tunNotRunning => 'سرویس TUN اجرا نمی‌شود؛ دوباره تلاش می‌شود…';

  @override
  String get tunMissing => 'سرویس TUN نصب نیست.';

  @override
  String get tunOutdated =>
      'سرویس TUN از این برنامه قدیمی‌تر است. برای استفاده از حالت TUN دوباره نصبش کنید.';

  @override
  String get tunAppOutdated =>
      'سرویس TUN از این برنامه جدیدتر است. برای استفاده از حالت TUN برنامه را به‌روز کنید.';

  @override
  String get tunBusy => 'حالت TUN را نسخه دیگری از Firefox VPN استفاده می‌کند.';

  @override
  String get tunInstall => 'نصب';

  @override
  String get tunInstallAgain => 'نصب دوباره';

  @override
  String get trayTunMode => 'حالت TUN (همه برنامه‌ها)';

  @override
  String get removeTunService => 'حذف سرویس TUN';

  @override
  String get removeTunServiceHint =>
      'سرویس سیستمی که حالت TUN از آن استفاده می‌کند حذف می‌شود. با انتخاب دوباره حالت TUN، دوباره نصب می‌شود.';

  @override
  String get tunServiceRemoved => 'سرویس TUN حذف شد.';

  @override
  String get tunInstallPrompt =>
      'برای حالت TUN، سرویس Firefox VPN باید نصب شود.';

  @override
  String get tunRemovePrompt =>
      'برای حذف حالت TUN، سرویس Firefox VPN باید حذف شود.';

  @override
  String tunRemoveFailed(String error) {
    return 'حذف سرویس TUN ممکن نشد: $error';
  }

  @override
  String get sectionTun => 'تنظیمات TUN';

  @override
  String get tunPrograms => 'برنامه‌های بدون VPN';

  @override
  String get tunProgramsHint =>
      'مستقیم وصل می‌شوند، نه از موزیلا؛ فقط برای برنامه‌هایی که بدون VPN کار می‌کنند.';

  @override
  String get tunProgramsEmpty => 'هنوز برنامه‌ای اضافه نشده است.';

  @override
  String get addProgram => 'افزودن برنامه';

  @override
  String get programFiles => 'برنامه‌ها';

  @override
  String get tunProgramAll => 'همه ترافیک';

  @override
  String get tunProgramAllHint => 'کل برنامه مستقیم وصل می‌شود.';

  @override
  String get tunProgramUdp => 'فقط UDP';

  @override
  String get tunProgramUdpHint =>
      'فقط ترافیک UDP آن مستقیم وصل می‌شود؛ بقیه از VPN عبور می‌کند.';

  @override
  String get udpNoticeSetting => 'اعلان مسدود شدن UDP';

  @override
  String udpNoticeBody(String program) {
    return 'ترافیک UDP برنامه $program از VPN عبور نمی‌کند.';
  }

  @override
  String get dontShowAgain => 'دیگر نشان نده';

  @override
  String get addRunningProgram => 'از برنامه‌های در حال اجرا';

  @override
  String get addProgramFile => 'انتخاب فایل…';

  @override
  String get addProgramName => 'نوشتن نام…';

  @override
  String get programNameHint =>
      'نام فایل برنامه، مثل steam.exe؛ علامت * یعنی هر متنی (steam* یعنی همه برنامه‌های Steam).';

  @override
  String get runningProgramsEmpty => 'برنامه دیگری در حال اجرا نیست.';

  @override
  String get tabLog => 'لاگ';

  @override
  String get tabConnections => 'اتصال‌ها';

  @override
  String get connectionsEmpty => 'هنوز اتصالی نیست.';

  @override
  String connectionsOpen(int count) {
    return 'باز: $count';
  }

  @override
  String get connTime => 'زمان';

  @override
  String get connRoute => 'قانون';

  @override
  String get connDestination => 'مقصد';

  @override
  String get connInbound => 'ورودی';

  @override
  String get connProtocol => 'پروتکل';

  @override
  String get connColumns => 'ستون‌ها';

  @override
  String get connTraffic => 'حجم';

  @override
  String get connDuration => 'مدت';

  @override
  String get connRouteVpn => 'پروکسی';

  @override
  String get connRouteDirect => 'مستقیم';

  @override
  String get connRouteBlocked => 'مسدود';

  @override
  String get connRoutePort => 'پورت غیرمجاز';

  @override
  String get connRouteFailed => 'ناموفق';
}
