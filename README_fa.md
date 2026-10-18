<div dir="rtl">

# Firefox VPN

**VPN رایگان موزیلا روی کل کامپیوتر و گوشی‌تان، با هر تعداد حسابی که بخواهید.**

[English](README.md)

فایرفاکس یک VPN داخلی دارد: هر حساب فایرفاکس (Firefox Account) ماهی ۵۰ گیگابایت از سرورهای پروکسی خود موزیلا سهم دارد. Firefox VPN این سرویس را از مرورگر بیرون می‌آورد: روی ویندوز و اندروید برای همهٔ برنامه‌ها، و روی لینوکس به‌صورت پروکسی بدون رابط کاربری. چند حساب با هم کار می‌کنند، پس حجم ماهانه دیگر به ۵۰ گیگ محدود نمی‌ماند.

> **غیررسمی.** این پروژه را موزیلا نساخته، تأیید نکرده و پشتیبانی نمی‌کند. Firefox و Mozilla علامت‌های تجاری بنیاد موزیلا هستند.

## چرا Firefox VPN

- **رایگان، روی شبکه‌ای قابل اعتماد.** ترافیک از سرورهای خود موزیلا (Fastly) رد می‌شود، همان‌هایی که فایرفاکس استفاده می‌کند. هیچ شرکت VPN دیگری وسط کار نیست.
- **حجم بیشتر با حساب‌های بیشتر.** چند حساب فایرفاکس اضافه کنید. وقتی حساب فعال ۹۰٪ حجمش را مصرف کرد، حساب بعدی خودکار جایش را می‌گیرد، بدون اینکه اتصال‌هایتان قطع شود.
- **همهٔ برنامه‌ها، نه فقط مرورگر.** روی اندروید یک VPN کامل، روی ویندوز پروکسی کل سیستم، و برای بقیه یک پروکسی SOCKS5 و HTTP.
- **سریع، همان‌جا که مهم است.** سایت‌های کشور خودتان می‌توانند مستقیم و بدون VPN باز شوند: سریع‌تر بالا می‌آیند و از حجم کم نمی‌کنند.
- **ساخته‌شده برای شبکه‌های فیلترشده.** DNS رمزگذاری‌شده، HTTP/3 با برگشت خودکار به HTTP/2، تشخیص DNS دستکاری‌شده، و در صورت نیاز یک رلهٔ شخصی برای وقتی که ورود به حساب موزیلا بسته است.
- **کم‌حجم و سبک.** حدود ۱۴ مگابایت برای اندروید و ۱۸ مگابایت برای ویندوز. بدون تبلیغ، بدون ردیابی، و بدون هیچ سروری جز سرورهای موزیلا.

## امکانات

### اتصال

- اتصال با یک لمس. برنامه همیشه قطع باز می‌شود و فقط وقتی خودتان بخواهید وصل می‌شود.
- مکان‌ها از فهرست سرورهای موزیلا، هر کدام با پرچم و تأخیر واقعی‌اش. خودتان یکی را انتخاب کنید یا بگذارید برنامه پیشنهادی یا سریع‌ترین را بردارد.
- HTTP/2 یا HTTP/3 (QUIC). هر جا QUIC بسته باشد، برنامه خودش به HTTP/2 برمی‌گردد.
- وقتی چیزی از اتصال استفاده نکند، ارتباط با موزیلا موقتاً بسته می‌شود تا حساب‌ها استراحت کنند. اولین درخواست بعدی، در چند ثانیه دوباره وصلش می‌کند.
- وقتی شبکه نیست، بی‌سروصدا صبر می‌کند و با وصل شدن شبکهٔ جدید فوراً دوباره وصل می‌شود.
- تست اتصال با زمان هر مرحله، و IP عمومی، کشور و شبکه‌ای که سایت‌ها می‌بینند.

### حساب‌ها

- ورود به حساب فایرفاکس داخل خود برنامه، با هر مرحله‌ای که موزیلا بخواهد: کد ایمیل، کد برنامهٔ احراز هویت (Authenticator) یا تصویر امنیتی.
- حجم باقی‌ماندهٔ هر حساب و تاریخ ریست آن.
- جابه‌جایی خودکار بین حساب‌ها در درصدی که خودتان انتخاب می‌کنید.
- یادآوری وقتی حجم حساب فعال کم است و حساب دیگری آماده نیست.
- ورودهای منقضی‌شده خودکار تمدید می‌شوند، با رمزی که روی دستگاه خودتان ذخیره است.

### مسیریابی

- سایت‌ها و آدرس‌های کشور شما مستقیم باز می‌شوند: ایران، چین، روسیه، افغانستان، ترکیه، اندونزی یا برزیل.
- قوانین در قالب v2ray (geosite، geoip، دامنه، کلمه، محدودهٔ IP)، با فهرست‌های Chocolate4U یا Loyalsoldier که خودکار به‌روز می‌شوند.
- فهرست‌های «مستقیم» و «مسدود» شخصی.
- مسدود کردن تبلیغات با یک کلید.
- روی اندروید، انتخاب اینکه کدام برنامه‌ها از VPN استفاده کنند.
- تست هر آدرس، برای دیدن اینکه از کجا می‌رود و کدام قانون تصمیم گرفته.

### DNS

- DNS رمزگذاری‌شده: DNS over HTTPS یا TLS، از Cloudflare، Google یا Quad9، یا سرورهای خودتان.
- تست DNS که جواب‌ها را با جواب شبکهٔ خودتان مقایسه می‌کند و می‌گوید اگر شبکه DNS را دستکاری کرده باشد.

### اندروید

- VPN کامل برای همهٔ برنامه‌ها، یا فقط پروکسی محلی.
- کاشی تنظیمات سریع و دکمهٔ صفحهٔ اصلی برای اتصال با یک لمس.
- سرعت و مکان در اعلان.

### ویندوز

- پروکسی برای کل سیستم، یا فقط برای برنامه‌هایی که خودتان تنظیم می‌کنید.
- در کنار ساعت (tray) می‌ماند و اگر بخواهید با ویندوز اجرا می‌شود.
- اشتراک پروکسی با دستگاه‌های دیگر شبکه، با نام کاربری و رمز.

### مک

- همین برنامه در نوار منو، با پروکسی سیستم برای همهٔ شبکه‌ها (Wi-Fi، Ethernet) و اجرا هنگام ورود به سیستم.
- یک فایل برای مک‌های Apple silicon و Intel.

### لینوکس

- همین برنامه، با پروکسی سیستم (تنظیم GNOME)، آیکون کنار ساعت و اجرا هنگام ورود به سیستم، که با [یک دستور](#نصب-از-ترمینال) نصب می‌شود.
- برای سرورها، هستهٔ بدون رابط کاربری به‌صورت سرویس systemd، آن هم با یک دستور.
- داشبورد وب برای مدیریت همه‌چیز از مرورگر: وضعیت، حساب‌ها، مکان‌ها، تنظیمات و لاگ‌ها.

### برای همه

- ۱۵ زبان: English، فارسی، 简体中文، 繁體中文، Русский، Türkçe، العربية، Azərbaycan، Bahasa Indonesia، Español، Français، Magyar، Português، Tiếng Việt و বাংলা. فارسی و عربی راست‌به‌چپ‌اند و تاریخ‌های فارسی شمسی است.
- پوستهٔ روشن و تیره.

## دانلود

جدیدترین نسخه، مستقیم از [Releases](https://github.com/armanlife/firefox-vpn-client/releases/latest):

</div>

<table>
<tr><th>System</th><th>Download</th></tr>
<tr><td>Android</td><td><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Android-universal.apk"><img src="https://img.shields.io/badge/APK-Universal-1a7f37?logo=android&logoColor=white" alt="APK Universal"></a><br><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Android-arm64-v8a.apk"><img src="https://img.shields.io/badge/APK-ARMv8-2da44e?logo=android&logoColor=white" alt="APK ARMv8"></a><br><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Android-armeabi-v7a.apk"><img src="https://img.shields.io/badge/APK-ARMv7-4ac26b?logo=android&logoColor=white" alt="APK ARMv7"></a><br><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Android-x86_64.apk"><img src="https://img.shields.io/badge/APK-x64-6fdd8b?logo=android&logoColor=white" alt="APK x64"></a></td></tr>
<tr><td>Windows</td><td><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Windows-Setup-x64.exe"><img src="https://img.shields.io/badge/Setup-x64-0550ae?logo=windows&logoColor=white" alt="Setup x64"></a><br><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Windows-x64.zip"><img src="https://img.shields.io/badge/Portable-x64-0969da" alt="Portable x64"></a></td></tr>
<tr><td>macOS</td><td><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-macOS.dmg"><img src="https://img.shields.io/badge/DMG-Universal-24292f?logo=apple&logoColor=white" alt="DMG Universal"></a></td></tr>
<tr><td rowspan="2">Linux</td><td><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Linux-amd64.tar.gz"><img src="https://img.shields.io/badge/App-amd64-e36209?logo=linux&logoColor=white" alt="App amd64"></a><br><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Linux-arm64.tar.gz"><img src="https://img.shields.io/badge/App-ARM64-e36209?logo=linux&logoColor=white" alt="App ARM64"></a></td></tr>
<tr><td><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/firefox-vpn-core-linux-amd64.tar.gz"><img src="https://img.shields.io/badge/Core-amd64-f0883e?logo=linux&logoColor=white" alt="Core amd64"></a><br><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/firefox-vpn-core-linux-arm64.tar.gz"><img src="https://img.shields.io/badge/Core-ARM64-f6a35e?logo=linux&logoColor=white" alt="Core ARM64"></a></td></tr>
</table>

<div dir="rtl">

- **اندروید** ۷٫۰ به بالا: نسخهٔ ARMv8 برای تقریباً همهٔ گوشی‌هاست؛ Universal روی همه نصب می‌شود ولی حجمش بیشتر است.
- **ویندوز** ۱۰ یا ۱۱: Setup برنامه را فقط برای کاربر شما و بدون نیاز به دسترسی مدیر نصب می‌کند و نسخهٔ جدید روی قبلی نصب می‌شود. Portable یک پوشهٔ `Firefox VPN` است: آن را هر جا خواستید از حالت فشرده خارج کنید و `firefox-vpn.exe` را اجرا کنید. در هر دو حالت حساب‌ها و تنظیمات در پوشهٔ `user-data` کنار برنامه می‌مانند.
- **مک** ۱۲ به بالا: فایل DMG را باز کنید و Firefox VPN را به Applications بکشید. برنامه امضای اپل ندارد، پس بار اول مک اجازهٔ باز شدنش را نمی‌دهد: در System Settings > Privacy & Security گزینهٔ Open Anyway را بزنید. دستور پایین بدون این مرحله نصبش می‌کند.
- **لینوکس:** برنامه برای دسکتاپ (amd64 همان کامپیوترهای معمولی Intel و AMD است؛ ARM64 مثل Raspberry Pi یا لپ‌تاپ‌های ARM)، یا فقط هسته با داشبورد وب برای سرورها؛ هر دو با یک دستور نصب می‌شوند (پایین).

### نصب از ترمینال

برنامه روی مک یا دسکتاپ لینوکس، برای خودتان (بدون sudo):

</div>

```bash
curl -fsSL https://raw.githubusercontent.com/armanlife/firefox-vpn-client/main/install.sh | bash -s -- desktop
```

<div dir="rtl">

در مک برنامه در Applications قرار می‌گیرد و حساب‌ها در `~/Library/Application Support/Firefox VPN Client` می‌مانند. در لینوکس برنامه در `~/.local/opt/firefox-vpn-client` و منوی برنامه‌ها قرار می‌گیرد و حساب‌ها در `~/.local/share/firefox-vpn-client` می‌مانند؛ آیکون کنار ساعت به `libayatana-appindicator3-1` (دبیان، اوبونتو) یا `libappindicator-gtk3` (فدورا، آرچ) نیاز دارد؛ در GNOME افزونهٔ AppIndicator هم لازم است. برای حذف: `... | bash -s -- remove-desktop`.

هسته به‌صورت سرویس، برای سرور لینوکس (amd64 یا ARM64، با systemd):

</div>

```bash
curl -fsSL https://raw.githubusercontent.com/armanlife/firefox-vpn-client/main/install.sh | sudo bash
```

<div dir="rtl">

هر دو دستور تازه‌ترین نسخه را دانلود می‌کنند، آن را با checksumهای همان نسخه بررسی می‌کنند و نصب می‌کنند. برای سرویس، بعد:

</div>

```bash
sudo firefox-vpn add-account    # sign in to a Firefox Account
sudo firefox-vpn status         # the service and its state
sudo firefox-vpn help           # every command
```

<div dir="rtl">

داشبورد در http://127.0.0.1:10820 است و پروکسی (SOCKS5 و HTTP) روی `127.0.0.1:10810`. برای به‌روزرسانی همان دستور را دوباره اجرا کنید؛ حساب‌ها و تنظیمات می‌مانند. `sudo firefox-vpn uninstall` سرویس را حذف می‌کند (با `PURGE=1` حساب‌ها هم پاک می‌شوند). اسکریپت: [install.sh](install.sh).

## شروع کار

۱. اگر حساب فایرفاکس ندارید، یک حساب رایگان در [accounts.firefox.com](https://accounts.firefox.com) بسازید.

۲. برنامه را باز کنید، زبان و کشورتان را انتخاب کنید و حساب را اضافه کنید.

۳. دکمه را بزنید تا وصل شوید.

برای حجم بیشتر، حساب‌های بیشتری اضافه کنید: هر حساب ماهی ۵۰ گیگابایت می‌آورد.

## محدودیت‌ها

این‌ها از خود سرویس موزیلا می‌آیند:

- **فقط TCP.** ترافیک UDP رد نمی‌شود؛ برنامه‌هایی که از آن استفاده می‌کنند (بعضی بازی‌ها و تماس‌ها) به TCP برمی‌گردند.
- **فقط پورت‌های وب.** پروکسی موزیلا فقط به پورت‌های 80، 443، 8080 و 8443 وصل می‌شود.
- موزیلا بعضی مکان‌ها را برای بعضی حساب‌ها قفل کرده است.

## ساخت از روی سورس

</div>

```powershell
scripts\build-windows.ps1   # dist\Firefox-VPN-<version>\, its .zip, and the installer
scripts\build-android.ps1   # dist\Firefox-VPN-<version>-android\
```

<div dir="rtl">

به Go و Flutter نیاز دارید، و برای اندروید به Android SDK و NDK همراه با gomobile. پروژه دو بخش دارد:

</div>

```text
core/   Go: the VPN core (accounts, connections, routing, DNS, the dashboard and its API)
app/    Flutter: the app for Windows, Android, and macOS
```

<div dir="rtl">

برنامه از API محلی هسته استفاده می‌کند، پس همهٔ سیستم‌ها یک هستهٔ مشترک دارند. مستندات توسعه‌دهندگان در [core/doc](core/doc/README.md) است.

## لایسنس

[MIT](LICENSE).

## قدردانی

پرچم کشورها از [flag-icons](https://github.com/lipis/flag-icons) (MIT) است. فونت فارسی [وزیرمتن](https://github.com/rastikerdar/vazirmatn) است (SIL Open Font License).

</div>
