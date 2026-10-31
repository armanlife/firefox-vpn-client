package com.arman.firefoxvpn

import android.os.ParcelFileDescriptor

/**
 * hev-socks5-tunnel (app/android), the C library that takes the VPN's packets
 * apart and opens a SOCKS5 connection to the core for each TCP connection and
 * UDP flow, on a thread of its own. A stack in the Go core cost two to three
 * times its CPU.
 *
 * The library binds these native methods to this class by name when it loads:
 * proguard-rules.pro keeps them, and app/build.gradle.kts names the class.
 */
object Tun2Socks {
    private external fun TProxyStartService(configPath: String, fd: Int): Boolean
    private external fun TProxyStopService(): Boolean
    private external fun TProxyIsRunning(): Boolean

    @Suppress("unused") // The library binds all four, or none.
    private external fun TProxyGetStats(): LongArray

    /** The VPN's device: the library only borrows it. */
    private var device: ParcelFileDescriptor? = null

    /**
     * Runs the library on [tun], which this now owns, instead of a device it
     * ran on before. False, or a throw, when it could not start: [tun] is
     * closed then, which ends the VPN instead of holding the phone's traffic.
     */
    @Synchronized
    fun start(configPath: String, tun: ParcelFileDescriptor): Boolean {
        try {
            stop()
            System.loadLibrary("hev-socks5-tunnel")
            device = tun
            if (TProxyStartService(configPath, tun.fd)) return true
        } catch (e: Throwable) {
            device = null
            tun.close()
            throw e
        }
        stop()
        return false
    }

    /** Stops the library, which ends its connections, and closes the device. */
    @Synchronized
    fun stop() {
        val tun = device ?: return
        device = null
        TProxyStopService()
        tun.close()
    }

    /**
     * It was started and ended without [stop], which it does only when it
     * could not start: its configuration, or no memory.
     */
    @Synchronized
    fun ended(): Boolean = device != null && !TProxyIsRunning()
}
