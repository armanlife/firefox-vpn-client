# Browser sign-in, and moving an account to another device

Mozilla's sign-in servers sit behind a security check that sometimes
refuses sign-ins that do not come from a real browser. The Windows, macOS,
and Android apps have a way around it: **sign in with the browser**, where the
account is added on Mozilla's own sign-in page inside the app. The
terminal (`arman-vpn-core -add-account`) and the web panel have no
browser, so when the check refuses them, add the account in an app and
move it over. Accounts made with Google or Apple sign-in (no password)
also need the browser sign-in.

## 1. Sign in with the browser in an app

1. Install the Arman VPN app on Windows, macOS, or Android
   ([downloads](https://github.com/armanlife/arman-vpn-client#downloads)).
2. Open **Accounts** and change **Sign-in method** from the default,
   **Sign in directly**, to **Sign in with the browser**.
3. Press **Add account** and sign in on Mozilla's page. Any verification
   code or CAPTCHA is handled right there.

## 2. Move the account to the target device

In the app where the account was added, open **Accounts**, press **⋮**
beside **Add account**, and choose **Save a backup**. The file is a zip
of the app's data folder, in the same layout: the accounts and the
settings, without the logs and the routing lists.

**To another app or a web panel** (Windows, macOS, Linux, Android, or a
server's panel): **Accounts → ⋮ → Import a backup**, and pick the file.
An account that is there already takes the file's sign-in; the device
keeps its own settings.

**By hand, to a copy without a panel:** each account lives in its own
folder under `accounts` in the data folder:

| System | Data folder |
| --- | --- |
| Windows | `user-data` next to the app, usually `%LOCALAPPDATA%\Programs\Arman VPN\user-data` (installs from before the rename: `...\Firefox VPN Client\user-data`); a portable copy keeps it next to its exe |
| macOS | `~/Library/Application Support/Arman VPN` |
| Linux | `~/.local/share/arman-vpn`, or `$XDG_DATA_HOME/arman-vpn`; a service started with `-data-dir` uses that folder |

The web panel's Settings page also names the exact data folder of its
own device.

1. Stop the program on the target device (on a Linux server:
   `systemctl stop arman-vpn`, or your service name).
2. Unzip the account folders from the file's `accounts` into the
   target's `accounts` (create `accounts` if it is not there yet). Take
   `accounts/secret.key` too when the target has none: it unlocks the
   stored passwords. Unzipping the whole file replaces the target's
   settings as well.
3. Start the program again. The account appears in
   `arman-vpn-core -list-accounts` and in the panel, and joins the
   rotation at the end of the list.

The file holds the accounts' sign-in: whoever has it can use them. Move
it over a private channel (scp, a USB stick), not by mail or a chat
upload.
