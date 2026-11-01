package com.arman.firefoxvpn

import android.Manifest
import android.app.ActivityManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import android.net.Uri
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result

/**
 * The Flutter UI. Channel "app/android": dataDir, startCore (with the proxy
 * off), setOn, isRunning, openUrl. The UI talks to the core itself through
 * its HTTP API on loopback, as on the desktop.
 */
class MainActivity : FlutterActivity() {
    /** Waits for the user's answer to the VPN permission. */
    private var pendingOn: Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        holdPhoneUpright(resources.configuration)
        super.onCreate(savedInstanceState)
        removeOtherCards()
    }

    /**
     * One card in the recent apps. A card stays there after Back, and with no
     * task affinity (the manifest's, against task hijacking) Android keeps it
     * beside a new task opened with another intent: from the notification,
     * the tile, the widget, or the installer's Open.
     */
    private fun removeOtherCards() {
        for (task in getSystemService(ActivityManager::class.java).appTasks) {
            try {
                @Suppress("DEPRECATION") // taskId came only with Android 10.
                if (task.taskInfo.persistentId != taskId) task.finishAndRemoveTask()
            } catch (e: IllegalArgumentException) {
                // That task went by itself meanwhile.
            }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        holdPhoneUpright(newConfig)
    }

    /**
     * A phone stays upright (its layout is made for it); a tablet, whose
     * shorter side is 600 dp or more, turns freely. Asked again when the
     * screen changes, so a foldable follows its folding. A TV (960 x 540 dp,
     * so "short" too) cannot turn: it keeps its own orientation.
     */
    private fun holdPhoneUpright(config: Configuration) {
        val wanted = if (config.smallestScreenWidthDp < 600 && !isTv(config)) {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        } else {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
        if (requestedOrientation != wanted) requestedOrientation = wanted
    }

    /** Whether this is a TV (Android TV, Google TV), worked with a remote. */
    private fun isTv(config: Configuration) =
        config.uiMode and Configuration.UI_MODE_TYPE_MASK == Configuration.UI_MODE_TYPE_TELEVISION

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/android").setMethodCallHandler { call, result ->
            when (call.method) {
                "dataDir" -> result.success(CoreService.dataDir(this).absolutePath)
                "startCore" -> {
                    CoreService.startCore(this, on = false)
                    result.success(null)
                }
                "setOn" -> {
                    if (call.argument<Boolean>("on") != true) {
                        CoreService.turnOff(this)
                        result.success(null)
                    } else {
                        askForNotifications()
                        // The first time, Android asks the user to allow the
                        // VPN; proxy mode needs no VPN.
                        val consent = if (CoreService.usesVpn(this)) VpnService.prepare(this) else null
                        if (consent == null) {
                            turnOn(result)
                        } else {
                            pendingOn?.error("vpn_denied", "superseded", null)
                            pendingOn = result
                            startActivityForResult(consent, VPN_REQUEST)
                        }
                    }
                }
                "isRunning" -> result.success(mobile.Mobile.running())
                "connectionMode" -> result.success(CoreService.connectionMode(this))
                "showSpeed" -> result.success(CoreService.showSpeed(this))
                "setShowSpeed" -> {
                    CoreService.setShowSpeed(this, call.argument<Boolean>("on") == true)
                    result.success(null)
                }
                "setConnectionMode" -> {
                    val mode = call.argument<String>("mode") ?: CoreService.MODE_VPN
                    // A running proxy switched to the VPN needs the permission
                    // first; the app turns it off and on again to ask.
                    if (CoreService.on && mode == CoreService.MODE_VPN && VpnService.prepare(this) != null) {
                        result.error("vpn_denied", "the VPN is not allowed yet", null)
                    } else {
                        CoreService.setConnectionMode(this, mode)
                        result.success(null)
                    }
                }
                "installedApps" -> inBackground(result) { installedApps() }
                "appIcon" -> {
                    val pkg = call.argument<String>("package") ?: ""
                    inBackground(result) { appIcon(pkg) }
                }
                "appRouting" -> inBackground(result) {
                    // The page shows the region's apps installed since the
                    // last look checked; the VPN takes them at once.
                    if (CoreService.appMode(this) == CoreService.MODE_EXCLUDE &&
                        CoreService.suggest(this, force = true)
                    ) {
                        CoreService.reconnect(this)
                    }
                    mapOf(
                        "mode" to CoreService.appMode(this),
                        "bypass" to CoreService.appSet(this, CoreService.BYPASS).toList(),
                        "only" to CoreService.appSet(this, CoreService.ONLY).toList(),
                        "declined" to CoreService.appSet(this, CoreService.DECLINED).toList(),
                        "region" to CoreService.regionAppList(),
                    )
                }
                "setAppRouting" -> {
                    fun set(key: String) = (call.argument<List<String>>(key) ?: emptyList()).toSet()
                    CoreService.setAppRouting(
                        this,
                        call.argument<String>("mode") ?: CoreService.MODE_EXCLUDE,
                        mapOf(
                            CoreService.BYPASS to set("bypass"),
                            CoreService.ONLY to set("only"),
                            CoreService.DECLINED to set("declined"),
                        ),
                    )
                    if (call.argument<Boolean>("apply") == true) CoreService.reconnect(this)
                    result.success(null)
                }
                // The phone's main processor type (arm64-v8a, armeabi-v7a, ...).
                "abi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "")
                "isTv" -> result.success(isTv(resources.configuration))
                "openUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    val view = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    try {
                        // A TV without a browser does not throw: its stub
                        // "browser" only shows Android's "no app" message.
                        val handlers = packageManager.queryIntentActivities(view, 0)
                            .filter { it.activityInfo.packageName != "com.android.tv.frameworkpackagestubs" }
                        if (handlers.isEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        startActivity(view)
                        result.success(true)
                    } catch (e: ActivityNotFoundException) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** Runs [work] off the UI thread and answers with its value. */
    private fun inBackground(result: Result, work: () -> Any?) {
        worker.execute {
            val value = try {
                work()
            } catch (e: Exception) {
                null
            }
            main.post { result.success(value) }
        }
    }

    /**
     * The installed apps but this one: package, name, and whether it has a
     * launcher icon, on a phone's home screen or a TV's (the others are
     * mostly the system's). Packages without code (overlays, resources) use
     * no network and are left out.
     */
    private fun installedApps(): List<Map<String, Any>> {
        val pm = packageManager
        val withIcon = listOf(Intent.CATEGORY_LAUNCHER, Intent.CATEGORY_LEANBACK_LAUNCHER)
            .flatMap { pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(it), 0) }
            .map { it.activityInfo.packageName }
            .toSet()
        @Suppress("DEPRECATION")
        return pm.getInstalledApplications(0)
            .filter { it.packageName != packageName && (it.flags and ApplicationInfo.FLAG_HAS_CODE) != 0 }
            .map {
                mapOf(
                    "package" to it.packageName,
                    "label" to it.loadLabel(pm).toString(),
                    "launcher" to (it.packageName in withIcon),
                )
            }
    }

    /** An app's icon as a small PNG. */
    private fun appIcon(pkg: String): ByteArray {
        val drawable = packageManager.getApplicationIcon(pkg)
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    private fun turnOn(result: Result) {
        try {
            CoreService.turnOn(this)
            result.success(null)
        } catch (e: Exception) {
            result.error("start_failed", e.message, null)
        }
    }

    @Deprecated("The VPN permission is asked with startActivityForResult.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VPN_REQUEST) return
        val result = pendingOn ?: return
        pendingOn = null
        if (resultCode == RESULT_OK) turnOn(result) else result.error("vpn_denied", "the VPN was not allowed", null)
    }

    override fun onDestroy() {
        // Off, nothing needs the core once the UI is gone.
        if (isFinishing && !CoreService.on) CoreService.stopCore()
        super.onDestroy()
    }

    companion object {
        private const val VPN_REQUEST = 7
    }

    /** The service's notification needs this on Android 13 and later. */
    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }
}
