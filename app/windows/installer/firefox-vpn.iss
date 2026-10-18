; The Windows installer of Firefox VPN (Inno Setup 6). scripts\build-windows.ps1
; compiles it with the built app:
;
;   ISCC /DAppVersion=1.1.9 /DSourceDir=<the app's folder> /DOutputDir=<dir>
;        /DOutputName=<file name without .exe> firefox-vpn.iss
;
; It installs for the current user only, without administrator rights, into
; %LOCALAPPDATA%\Programs\Firefox VPN Client (apart from Mozilla's own
; client): the app keeps its data (accounts,
; settings, logs) in user-data beside it, which needs a folder of the user's
; own. A new version installs over the old one and keeps user-data.

#define AppName "Firefox VPN"
#define AppExe "firefox-vpn.exe"
#define AppDir "Firefox VPN Client"
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #error SourceDir must name the built app's folder
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif
#ifndef OutputName
  #define OutputName "Firefox-VPN-Setup"
#endif

[Setup]
; The same id in every version, so a new one replaces the old.
AppId={{6F3A2C1E-9B4D-4E7A-8C21-5D0F7B9E4A63}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=armanlife
AppPublisherURL=https://github.com/armanlife/firefox-vpn-client
AppSupportURL=https://github.com/armanlife/firefox-vpn-client/issues
AppUpdatesURL=https://github.com/armanlife/firefox-vpn-client/releases
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\{#AppDir}
DisableDirPage=yes
; Always that folder, even over a version installed elsewhere.
UsePreviousAppDir=no
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
; A running copy is closed before its files are replaced.
CloseApplications=force
RestartApplications=no
ShowLanguageDialog=auto

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "fa"; MessagesFile: "languages\Farsi.isl"
Name: "ar"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "tr"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "az"; MessagesFile: "languages\Azerbaijan.isl"
Name: "id"; MessagesFile: "languages\Indonesian.isl"
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"
Name: "hu"; MessagesFile: "compiler:Languages\Hungarian.isl"
Name: "pt"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "vi"; MessagesFile: "languages\Vietnamese.isl"
Name: "bn"; MessagesFile: "languages\Bengali.islu"

[CustomMessages]
; Uninstalling asks about the data, keeping it unless the user chooses
; otherwise.
DataQuestion=Keep your accounts and settings?
DataText=They stay in the user-data folder, so installing the app again brings them back. Delete them only if you will not use Firefox VPN again.
DataKeep=Keep them (recommended)
DataDelete=Delete them
fa.DataQuestion=حساب‌ها و تنظیمات شما نگه داشته شوند؟
fa.DataText=در پوشهٔ user-data می‌مانند و با نصب دوبارهٔ برنامه برمی‌گردند. فقط اگر دیگر از Firefox VPN استفاده نمی‌کنید پاکشان کنید.
fa.DataKeep=نگه داشته شوند (پیشنهادی)
fa.DataDelete=پاک شوند
ar.DataQuestion=هل تريد الاحتفاظ بحساباتك وإعداداتك؟
ar.DataText=تبقى في مجلد user-data، فتعود عند تثبيت التطبيق مرة أخرى. احذفها فقط إذا كنت لن تستخدم Firefox VPN مجددًا.
ar.DataKeep=احتفظ بها (موصى به)
ar.DataDelete=احذفها
ru.DataQuestion=Сохранить ваши аккаунты и настройки?
ru.DataText=Они останутся в папке user-data, и при повторной установке приложение их вернёт. Удаляйте их, только если больше не будете пользоваться Firefox VPN.
ru.DataKeep=Сохранить (рекомендуется)
ru.DataDelete=Удалить
tr.DataQuestion=Hesaplarınız ve ayarlarınız saklansın mı?
tr.DataText=user-data klasöründe kalırlar; uygulamayı yeniden kurduğunuzda geri gelirler. Yalnızca Firefox VPN'i bir daha kullanmayacaksanız silin.
tr.DataKeep=Sakla (önerilen)
tr.DataDelete=Sil
az.DataQuestion=Hesablarınız və ayarlarınız saxlanılsın?
az.DataText=Onlar user-data qovluğunda qalır və tətbiqi yenidən quraşdıranda geri qayıdır. Yalnız Firefox VPN-dən bir daha istifadə etməyəcəksinizsə silin.
az.DataKeep=Saxla (tövsiyə olunur)
az.DataDelete=Sil
id.DataQuestion=Simpan akun dan pengaturan Anda?
id.DataText=Semuanya tetap di folder user-data, jadi akan kembali saat aplikasi dipasang lagi. Hapus hanya jika Anda tidak akan memakai Firefox VPN lagi.
id.DataKeep=Simpan (disarankan)
id.DataDelete=Hapus
es.DataQuestion=¿Conservar tus cuentas y ajustes?
es.DataText=Se quedan en la carpeta user-data, así que vuelven al instalar de nuevo la aplicación. Bórralos solo si no vas a volver a usar Firefox VPN.
es.DataKeep=Conservarlos (recomendado)
es.DataDelete=Borrarlos
fr.DataQuestion=Conserver vos comptes et paramètres ?
fr.DataText=Ils restent dans le dossier user-data et reviennent si vous réinstallez l'application. Ne les supprimez que si vous n'utiliserez plus Firefox VPN.
fr.DataKeep=Les conserver (recommandé)
fr.DataDelete=Les supprimer
hu.DataQuestion=Megtartja a fiókjait és a beállításait?
hu.DataText=A user-data mappában maradnak, így az alkalmazás újratelepítésekor visszakerülnek. Csak akkor törölje őket, ha többé nem használja a Firefox VPN-t.
hu.DataKeep=Megtartás (ajánlott)
hu.DataDelete=Törlés
pt.DataQuestion=Manter suas contas e configurações?
pt.DataText=Elas ficam na pasta user-data e voltam se você instalar o aplicativo de novo. Apague-as só se não for mais usar o Firefox VPN.
pt.DataKeep=Manter (recomendado)
pt.DataDelete=Apagar
vi.DataQuestion=Giữ lại tài khoản và cài đặt của bạn?
vi.DataText=Chúng vẫn nằm trong thư mục user-data, nên sẽ quay lại khi bạn cài lại ứng dụng. Chỉ xóa nếu bạn sẽ không dùng Firefox VPN nữa.
vi.DataKeep=Giữ lại (khuyên dùng)
vi.DataDelete=Xóa
bn.DataQuestion=আপনার অ্যাকাউন্ট ও সেটিংস রেখে দেবেন?
bn.DataText=এগুলো user-data ফোল্ডারে থেকে যায়, তাই অ্যাপটি আবার ইনস্টল করলে ফিরে আসে। Firefox VPN আর ব্যবহার না করলে তবেই মুছুন।
bn.DataKeep=রেখে দিন (প্রস্তাবিত)
bn.DataDelete=মুছে ফেলুন

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Never an existing data folder, if one was in the source.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "user-data,portable"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
const
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';
  InternetKey = 'Software\Microsoft\Windows\CurrentVersion\Internet Settings';

// Uninstalling: the app's autostart entry goes, and so does a Windows
// proxy setting the app left pointing at its own (now gone) proxy; then
// the data, if the user wants.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Enabled: Cardinal;
  Server: String;
  Data: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    RegDeleteValue(HKCU, RunKey, '{#AppName}');
    if RegQueryDWordValue(HKCU, InternetKey, 'ProxyEnable', Enabled) and (Enabled = 1) and
       RegQueryStringValue(HKCU, InternetKey, 'ProxyServer', Server) and
       (Pos('127.0.0.1:', Server) = 1) then
      RegWriteDWordValue(HKCU, InternetKey, 'ProxyEnable', 0);
  end;
  if CurUninstallStep = usPostUninstall then
  begin
    Data := ExpandConstant('{app}\user-data');
    // Keep is the first and default button; a silent uninstall keeps too.
    if DirExists(Data) and not UninstallSilent and
       (TaskDialogMsgBox(CustomMessage('DataQuestion'), CustomMessage('DataText'), mbConfirmation,
          MB_YESNO, [CustomMessage('DataKeep'), CustomMessage('DataDelete')], 0) = IDNO) then
      DelTree(Data, True, True, True);
    RemoveDir(ExpandConstant('{app}'));
  end;
end;
