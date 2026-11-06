# Browser sign-in, and moving an account to another device

Mozilla's sign-in servers sit behind a security check that sometimes
refuses sign-ins that do not come from a real browser. The desktop and
Android apps have a way around it: **sign in with the browser**, where the
account is added on Mozilla's own sign-in page inside the app. The
terminal (`arman-vpn-core -add-account`) and the web panel have no
browser, so when the check refuses them, add the account in an app and
move it over. Accounts made with Google or Apple sign-in (no password)
also need the browser sign-in.

## 1. Sign in with the browser in an app

1. Install the Arman VPN app on a computer
   ([downloads](https://github.com/armanlife/arman-vpn-client#downloads)).
   A computer is best as the source: a phone keeps its app data private,
   so accounts cannot be copied off it.
2. Open **Accounts** and change **Sign-in method** from the default,
   **Sign in directly**, to **Sign in with the browser**.
3. Press **Add account** and sign in on Mozilla's page. Any verification
   code or CAPTCHA is handled right there.

## 2. Copy the account to the target device

Each account lives in its own folder under `accounts` in the app's data
folder:

| System | Data folder |
| --- | --- |
| Windows | `user-data` next to the app, usually `%LOCALAPPDATA%\Programs\Arman VPN\user-data` (installs from before the rename: `...\Firefox VPN Client\user-data`); a portable copy keeps it next to its exe |
| macOS | `~/Library/Application Support/Arman VPN` |
| Linux | `~/.local/share/arman-vpn`, or `$XDG_DATA_HOME/arman-vpn`; a service started with `-data-dir` uses that folder |

The web panel's Settings page also names the exact data folder of its
own device.

1. Stop the program on the **target** device (on a Linux server:
   `systemctl stop arman-vpn`, or your service name).
2. Copy the new account's folder from the source's `accounts` into the
   target's `accounts` (create `accounts` if it is not there yet).
   Copying only `accounts` keeps the target's own settings; copying the
   whole data folder replaces them too.
3. Start the program again. The account appears in
   `arman-vpn-core -list-accounts` and in the panel, and joins the
   rotation at the end of the list.

`credentials.json` inside an account's folder holds the account's access
tokens. Move it over a private channel (scp, a USB stick), not by mail or
a chat upload.
