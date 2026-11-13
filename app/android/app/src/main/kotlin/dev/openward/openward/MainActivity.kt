package dev.openward.openward

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Bundle
import android.system.Os
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * A FragmentActivity, for BiometricPrompt (VaultKeystore). It also speaks
 * the two channels the desktop runners speak: `openward/security` (lock
 * the vault when the screen turns off, as on a system lock) and
 * `openward/sessions` (keep the open sessions alive in the background).
 */
class MainActivity : FlutterFragmentActivity() {
    private var security: MethodChannel? = null
    private var securityReady = false
    private var suspendPending = false

    /// A file being saved through the document picker, and who waits.
    private var exporting: Pair<File, MethodChannel.Result>? = null
    private val createDocument =
        registerForActivityResult(ActivityResultContracts.CreateDocument("*/*")) { uri: Uri? ->
            val (file, result) = exporting ?: return@registerForActivityResult
            exporting = null
            if (uri == null) return@registerForActivityResult result.success(false)
            try {
                contentResolver.openOutputStream(uri)?.use { out ->
                    file.inputStream().use { it.copyTo(out) }
                }
                result.success(true)
            } catch (e: Exception) {
                result.error("export", e.message, null)
            }
        }

    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != Intent.ACTION_SCREEN_OFF) return
            suspendPending = true
            if (securityReady) security?.invokeMethod("suspend", null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // An app has no HOME or writable TMPDIR of its own: the core's
        // ~/.ssh, known_hosts and temporary files go in the app's folders.
        Os.setenv("HOME", filesDir.absolutePath, true)
        Os.setenv("TMPDIR", cacheDir.absolutePath, true)
        // The core, before Flutter opens it: JNI_OnLoad hands the Java VM
        // to it, for VaultKeystore.
        System.loadLibrary("openward_ffi")
        VaultKeystore.attach(this)
        super.onCreate(savedInstanceState)
        registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
    }

    override fun onResume() {
        super.onResume()
        VaultKeystore.attach(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val channel = MethodChannel(messenger, "openward/security")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    securityReady = true
                    if (suspendPending) channel.invokeMethod("suspend", null)
                    result.success(null)
                }
                "privacyReady" -> {
                    suspendPending = false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        security = channel
        // "Save as": the system's document picker, then a copy there.
        MethodChannel(messenger, "openward/files").setMethodCallHandler { call, result ->
            val path = call.argument<String>("path")
            val name = call.argument<String>("name")
            if (call.method != "export" || path == null || name == null) {
                return@setMethodCallHandler result.notImplemented()
            }
            if (exporting != null) return@setMethodCallHandler result.success(false)
            exporting = Pair(File(path), result)
            createDocument.launch(name)
        }
        MethodChannel(messenger, "openward/sessions").setMethodCallHandler { call, result ->
            when (call.method) {
                "count" -> {
                    SessionService.update(this, (call.arguments as? Int) ?: 0)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        unregisterReceiver(screenOff)
        if (isFinishing) SessionService.update(this, 0)
        super.onDestroy()
    }
}
