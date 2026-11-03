import Core
import Darwin
import NetworkExtension

/// The VPN's tunnel: it runs the Go core (the same one the app's UI talks
/// to on loopback) and hev-socks5-tunnel, the C library that takes the
/// device's packets apart and opens a SOCKS5 connection to the core for
/// each TCP connection and UDP flow — what Android's CoreService and
/// Tun2Socks do together. The extension process keeps running while the
/// system says the VPN is on, whether the app is here or not.
///
/// iOS hands out packets through NEPacketTunnelFlow, not a file descriptor
/// as Android's TUN is; a datagram socketpair bridges the two: hev reads
/// and writes plain IP packets on its end, this class pumps them between
/// the other end and the flow, one packet per datagram.
class PacketTunnelProvider: NEPacketTunnelProvider {
    /// The VPN interface's MTU, which the tunnel gets too (CoreService.kt).
    private static let mtu: Int32 = 1500

    private var stopped = false
    private var hevFd: Int32 = -1
    private var pumpFds: [Int32] = [-1, -1]
    private var watching = false

    override func startTunnel(
        _ options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        stopped = false
        let dir = Self.dataDir()
        var err: NSError?
        guard MobileStart(dir, true, &err) else {
            completionHandler(TunnelError(
                "the core did not start: \(err?.localizedDescription ?? MobileLastError())"))
            return
        }
        // Like CoreService.onStartCommand: on already after the button.
        if !MobileIsOn() {
            MobileSetOn(true)
        }
        MobileNetworkChanged(true)
        guard let configPath = MobileTunConfig(Self.mtu, &err) else {
            MobileStop()
            completionHandler(TunnelError(
                "the tunnel's configuration did not write: \(err?.localizedDescription ?? "no error")"))
            return
        }
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "172.19.0.1")
        settings.mtu = NSNumber(value: Self.mtu)
        // The tunnel answers DNS sent to 172.19.0.2 (core/mobile) with
        // addresses that stand for names.
        let dns = NEDNSSettings(servers: ["172.19.0.2"])
        settings.dnsSettings = dns
        let ipv4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        let ipv6 = NEIPv6Settings(addresses: ["fdfe:dcba:9876::1"], networkPrefixLengths: [126])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6
        setTunnelNetworkSettings(settings) { error in
            if let error {
                MobileStopTun()
                MobileStop()
                completionHandler(error)
                return
            }
            guard self.runHev(configPath: configPath) else {
                MobileStopTun()
                MobileStop()
                completionHandler(TunnelError("the tunnel's library did not start"))
                return
            }
            completionHandler(nil)
            self.watch()
        }
    }

    /// Runs hev on one end of a fresh socketpair and pumps packets between
    /// the other end and the flow. False when the socketpair did not open.
    private func runHev(configPath: String) -> Bool {
        var fds: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_DGRAM, 0, &fds) == 0 else {
            return false
        }
        pumpFds = fds
        hevFd = fds[0]
        let mine = fds[1]
        let config = configPath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Blocks until hev_socks5_tunnel_quit; -1 the configuration
            // could not read or the memory did not come.
            let res = hev_socks5_tunnel_main_from_file(config, self?.hevFd ?? -1)
            if res < 0 {
                self?.endTunnel(TunnelError("the tunnel's library ended"))
            }
        }
        // The device's packets into the library.
        readIntoHev(fd: mine)
        // The library's packets back to the device.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.writeToFlow(fd: mine)
        }
        return true
    }

    /// Reads the flow's packets and hands each to hev as one datagram.
    private func readIntoHev(fd: Int32) {
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self, !self.stopped else { return }
            for packet in packets {
                packet.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    _ = write(fd, raw.baseAddress, raw.count)
                }
            }
            self.readIntoHev(fd: fd)
        }
    }

    /// Reads hev's datagrams and puts them on the flow.
    private func writeToFlow(fd: Int32) {
        let size = 65_535
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while !stopped {
            let n = read(fd, buffer, size)
            if n <= 0 {
                if errno == EINTR { continue }
                break
            }
            let packet = Data(bytes: buffer, count: n)
            packetFlow.writePackets([packet], withProtocols: nil)
        }
    }

    /// The core gave the connect up (no connection to Mozilla within a
    /// minute) or ended: the VPN goes, instead of holding the device's
    /// traffic and carrying none of it (CoreService.watchCountry).
    private func watch() {
        guard !watching else { return }
        watching = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            self.watching = false
            if self.stopped { return }
            if !MobileRunning() || !MobileIsOn() {
                self.endTunnel(nil)
                return
            }
            MobileNetworkChanged(true)
            self.watch()
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        if hevFd >= 0 {
            hev_socks5_tunnel_quit()
        }
        MobileStopTun()
        MobileStop()
        closeFds()
        stopped = true
        completionHandler()
    }

    /// Stops the library (its quit unblocks the call above) and ends the
    /// tunnel: the system then calls stopTunnel, which shuts the core.
    private func endTunnel(_ error: Error?) {
        guard !stopped else { return }
        if hevFd >= 0 {
            hev_socks5_tunnel_quit()
        }
        closeFds()
        stopped = true
        cancelTunnelWithError(error)
    }

    private func closeFds() {
        for i in 0..<pumpFds.count where pumpFds[i] >= 0 {
            close(pumpFds[i])
            pumpFds[i] = -1
        }
        hevFd = -1
    }

    /// The folder both processes share (AppDelegate reads the same constant).
    static func dataDir() -> String {
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.arman.firefoxvpn")?
            .path ?? NSTemporaryDirectory()
        return base + "/data"
    }
}

/// A start failure the system shows with the VPN's status.
struct TunnelError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
