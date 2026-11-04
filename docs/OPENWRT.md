# Arman VPN on OpenWrt

Your router becomes a **proxy** (SOCKS5 and HTTP, one port) with a **web panel**. Your devices use it, and their traffic goes through Mozilla's VPN servers.

## Contents

- [Before you start](#before-you-start)
- [1. Get the core](#1-get-the-core)
- [2. Open it to your network](#2-open-it-to-your-network)
- [3. Start it with the router](#3-start-it-with-the-router)
- [4. Add your accounts in the panel](#4-add-your-accounts-in-the-panel)
- [5. Use it on your devices](#5-use-it-on-your-devices)
- [6. The whole network, with PassWall2](#6-the-whole-network-with-passwall2)
- [Update and remove](#update-and-remove)
- [Problems](#problems)

## Before you start

| You need | |
|---|---|
| Processor | `x86_64`, `aarch64`, or 32-bit ARM from Cortex-A5 up (others are not supported) |
| RAM | 128 MB or more |
| Free storage | 20 MB |

Tested on a Xiaomi Redmi Router AX6S: 12 MB of RAM idle, 20 MB with traffic.

## 1. Get the core

**Way A: on the router.** Copy all of this and paste it. It picks the right file for your router:

```sh
mkdir -p /root/arman-vpn && cd /root/arman-vpn
case "$(uname -m)" in
  aarch64) arch=arm64 ;;
  x86_64) arch=amd64 ;;
  armv7*) arch=armv7 ;;
esac
wget -O core.tar.gz "https://github.com/armanlife/arman-vpn-client/releases/latest/download/arman-vpn-core-linux-$arch.tar.gz"
tar -xzf core.tar.gz && mv "arman-vpn-core-linux-$arch/arman-vpn-core" . && rm -r core.tar.gz "arman-vpn-core-linux-$arch"
chmod +x arman-vpn-core
```

- Certificate error? `opkg update && opkg install ca-bundle` (on 25.12 and newer: `apk add ca-bundle`)
- No access to GitHub? Use way B.

**Way B: from a computer**

1. On the router, check the processor: `grep DISTRIB_ARCH /etc/openwrt_release`
   `x86_64` → **amd64** · `aarch64_…` → **arm64** · `arm_cortex-a…` → **armv7**
2. Download [arm64](https://github.com/armanlife/arman-vpn-client/releases/latest/download/arman-vpn-core-linux-arm64.tar.gz), [amd64](https://github.com/armanlife/arman-vpn-client/releases/latest/download/arman-vpn-core-linux-amd64.tar.gz), or [armv7](https://github.com/armanlife/arman-vpn-client/releases/latest/download/arman-vpn-core-linux-armv7.tar.gz) and unpack it.
3. Open [Bitvise SSH Client](https://www.bitvise.com/ssh-client-download) or [WinSCP](https://winscp.net/): router address, port 22, user `root`.
4. Put `arman-vpn-core` in `/root/arman-vpn/` (make the folder).
5. On the router: `chmod +x /root/arman-vpn/arman-vpn-core`

The file window does not open? Install `openssh-sftp-server` on the router, or pick **SCP** in WinSCP.

## 2. Open it to your network

```sh
cd /root/arman-vpn
./arman-vpn-core -setup-server admin
```

- The panel and the proxy now listen on **0.0.0.0** (every address of the router), not only on `127.0.0.1` (the router itself). If the panel ever stops opening from your devices, check this, and run this step again.
- It prints the **panel** login and the **proxy** login. **Write them down**: they are shown only once.
- Your own panel password: run `./arman-vpn-core -panel` now.
- Never open the ports 10810 and 10820 on WAN.

## 3. Start it with the router

Save this as `/etc/init.d/arman-vpn`:

```sh
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

start_service() {
	procd_open_instance
	procd_set_param command /root/arman-vpn/arman-vpn-core -plain
	procd_set_param respawn
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_close_instance
}
```

Then:

```sh
chmod +x /etc/init.d/arman-vpn
/etc/init.d/arman-vpn enable
/etc/init.d/arman-vpn start
```

It shows in LuCI under **System → Startup**. Do not use `-app` (that is the desktop app's mode).

## 4. Add your accounts in the panel

Open:

> **http://192.168.1.1:10820/app/**

(`192.168.1.1` = your router's address, the one you open LuCI with.)

1. Sign in with the panel login from step 2.
2. **Accounts → Add account** → email, password → **Sign in**.
3. Mozilla emailed a code? Enter it in **Code**.

The proxy turns on by itself. Use the panel only on your own network (no HTTPS).

## 5. Use it on your devices

| Setting | Value |
|---|---|
| Address | your router's address (`192.168.1.1`) |
| Port | `10810` |
| Type | SOCKS5 or HTTP |
| Username and password | the proxy login from step 2 |

- **Telegram, v2rayNG, NekoBox, v2rayN:** add a SOCKS5 proxy.
- **Browser or system proxy:** HTTP proxy, also for HTTPS.
- **Device with no place for a password** (Android Wi-Fi, TV): remove the proxy login in the panel (**Settings → Local proxy → Login**).

What goes through:

- **TCP:** ports 80, 443, 8080, and 8443.
- **UDP (SOCKS5 only):** ports 80, 443, 3478, 8080, 8443, and 49152-65534.

Calls and games on other ports do not work.

## 6. The whole network, with PassWall2

With [PassWall2](https://github.com/Openwrt-Passwall/openwrt-passwall2) on the router, every device goes through Arman VPN with no setting on the device, and PassWall2's own rules choose what goes through it and what goes direct.

1. **Node List → Add:** protocol **Socks**, address `127.0.0.1`, port `10810`, and the proxy login from step 2.
2. **Basic Settings:** choose this node and turn the main switch on.
3. **Turn off Localhost Proxy** (the router's own traffic). Otherwise Arman VPN's own connections go back into it in a loop, and nothing connects.
4. **DNS → Remote DNS Protocol: DoH** (`https://1.1.1.1/dns-query`).
5. Make your routing rules in PassWall2 (for example, your country's sites direct).

UDP goes through only on the ports in step 5. Menu names differ a little between versions.

## Update and remove

**Update:**

```sh
/etc/init.d/arman-vpn stop
# put the new arman-vpn-core in /root/arman-vpn (step 1)
/etc/init.d/arman-vpn start
```

Accounts and settings stay.

**Remove:**

```sh
/etc/init.d/arman-vpn stop
/etc/init.d/arman-vpn disable
rm /etc/init.d/arman-vpn
rm -r /root/arman-vpn
```

## Problems

| Problem | Fix |
|---|---|
| Is it running? | `/root/arman-vpn/arman-vpn-core -status` |
| See the log | `logread -e arman-vpn` |
| Panel does not open | the service runs? `netstat -ltn \| grep 1082` shows `127.0.0.1:10820` instead of `0.0.0.0` or `:::`? then run step 2 again; use the router's address, not `127.0.0.1` |
| Forgot the panel password | `/root/arman-vpn/arman-vpn-core -panel`, then `/etc/init.d/arman-vpn restart` |
| Proxy port does not answer | add a working account (step 4); the panel's Overview says why it waits |
| Accounts from the desktop app | stop the service, copy only the `user-data/accounts` folder (not `config.json`: it would replace the router's settings, and then step 2 is needed again), start it |
| Slow or times out | panel: **Settings → Connection → Protocol: HTTP/2** |
| A site on another port fails | Mozilla allows only the ports 80, 443, 8080, and 8443 |
