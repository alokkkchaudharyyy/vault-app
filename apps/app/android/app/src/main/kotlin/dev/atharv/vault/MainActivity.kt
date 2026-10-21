package dev.atharv.vault

import android.app.AppOpsManager
import android.app.KeyguardManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Telephony
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    // Screenshots: a permission prompt or a trash request waiting for the user.
    private var pendingAccess: MethodChannel.Result? = null
    private var pendingTrash: MethodChannel.Result? = null

    // Money and health: a permission screen waiting for the user.
    private var pendingSms: MethodChannel.Result? = null
    private var pendingHealth: MethodChannel.Result? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    // Something shared to the app: read once, handed to Dart.
    private var shareChannel: MethodChannel? = null
    private var initialShare: Map<String, Any>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initialShare = readShare(intent)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "todo/share").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "initial") {
                    result.success(initialShare)
                    initialShare = null
                } else {
                    result.notImplemented()
                }
            }
        }
        // Bank and UPI messages, read on the phone to track spending.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "todo/sms").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccess" -> result.success(hasSmsAccess())
                "requestAccess" -> {
                    if (hasSmsAccess()) return@setMethodCallHandler result.success(true)
                    pendingSms = result
                    requestPermissions(arrayOf(android.Manifest.permission.READ_SMS), REQUEST_SMS)
                }
                "inbox" -> result.success(smsSince((call.argument<Number>("since") ?: 0).toLong()))
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "todo/health").setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(Health.available(this))
                "hasAccess" -> scope.launch { result.success(runCatching { Health.hasAccess(this@MainActivity) }.getOrDefault(false)) }
                "requestAccess" -> {
                    if (!Health.available(this)) return@setMethodCallHandler result.success(false)
                    pendingHealth = result
                    startActivityForResult(Health.requestIntent(this), REQUEST_HEALTH)
                }
                "days" -> scope.launch {
                    try {
                        result.success(Health.days(this@MainActivity, call.argument<String>("from")!!, call.argument<String>("to")!!))
                    } catch (e: Exception) {
                        result.error("health", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "todo/shots").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccess" -> result.success(hasImageAccess())
                "requestAccess" -> {
                    if (hasImageAccess()) return@setMethodCallHandler result.success(true)
                    pendingAccess = result
                    requestPermissions(arrayOf(imagePermission()), REQUEST_IMAGES)
                }
                "canManage" -> result.success(MediaStore.canManageMedia(this))
                "openManageSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_REQUEST_MANAGE_MEDIA, Uri.parse("package:$packageName"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }
                "list" -> result.success(screenshots())
                "trash" -> {
                    val ids = call.argument<List<Number>>("ids").orEmpty()
                    if (ids.isEmpty()) return@setMethodCallHandler result.success(true)
                    val uris = ids.map { ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, it.toLong()) }
                    // With "Media management" allowed, the system approves this without asking.
                    val request = MediaStore.createTrashRequest(contentResolver, uris, true)
                    pendingTrash = result
                    startIntentSenderForResult(request.intentSender, REQUEST_TRASH, null, 0, 0, 0)
                }
                else -> result.notImplemented()
            }
        }
        // For the full-screen reminder: after it is answered over the lock
        // screen, the app steps back so the lock screen shows again.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "todo/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "isLocked" ->
                    result.success((getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isKeyguardLocked)
                "leave" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "todo/usage").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccess" -> result.success(hasUsageAccess())
                "openSettings" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "deviceName" -> result.success(Build.MODEL)
                "spans" -> {
                    val from = (call.argument<Number>("from") ?: 0).toLong()
                    val to = (call.argument<Number>("to") ?: System.currentTimeMillis()).toLong()
                    result.success(foregroundSpans(from, to))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        readShare(intent)?.let { shareChannel?.invokeMethod("shared", it) }
    }

    /**
     * A share from another app as {text, subject, images}: images are copied
     * into the cache, since the URI's permission ends with the intent. The
     * intent is marked read so a restart does not share it again.
     */
    private fun readShare(intent: Intent?): Map<String, Any>? {
        if (intent == null || (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE)) return null
        val uris = ArrayList<Uri>()
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)?.let(uris::addAll)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)?.let(uris::add)
        }
        val dir = java.io.File(cacheDir, "shared").apply { mkdirs() }
        val images = uris.mapIndexedNotNull { i, uri ->
            try {
                val type = contentResolver.getType(uri) ?: ""
                if (!type.startsWith("image/")) return@mapIndexedNotNull null
                val file = java.io.File(dir, "${System.currentTimeMillis()}_$i.img")
                contentResolver.openInputStream(uri)?.use { input -> file.outputStream().use { input.copyTo(it) } }
                file.absolutePath
            } catch (e: Exception) {
                null
            }
        }
        val share = HashMap<String, Any>()
        intent.getStringExtra(Intent.EXTRA_TEXT)?.let { share["text"] = it }
        intent.getStringExtra(Intent.EXTRA_SUBJECT)?.let { share["subject"] = it }
        share["images"] = images
        intent.action = null
        return share
    }

    private fun hasSmsAccess() =
        checkSelfPermission(android.Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    /** Received messages after [since] (epoch ms), oldest first, as {sender, body, date}. */
    private fun smsSince(since: Long): List<Map<String, Any>> {
        val out = ArrayList<Map<String, Any>>()
        if (!hasSmsAccess()) return out
        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
            "${Telephony.Sms.DATE} > ?",
            arrayOf(since.toString()),
            "${Telephony.Sms.DATE} ASC",
        )?.use { c ->
            while (c.moveToNext()) {
                out.add(mapOf("sender" to (c.getString(0) ?: ""), "body" to (c.getString(1) ?: ""), "date" to c.getLong(2)))
            }
        }
        return out
    }

    private fun imagePermission() =
        if (Build.VERSION.SDK_INT >= 33) android.Manifest.permission.READ_MEDIA_IMAGES
        else android.Manifest.permission.READ_EXTERNAL_STORAGE

    private fun hasImageAccess() = checkSelfPermission(imagePermission()) == PackageManager.PERMISSION_GRANTED

    /** Every image in a Screenshots folder, newest first, as {id, path, name, date}. */
    private fun screenshots(): List<Map<String, Any>> {
        val out = ArrayList<Map<String, Any>>()
        val columns = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DATA,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.DATE_ADDED,
        )
        contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            columns,
            "${MediaStore.Images.Media.RELATIVE_PATH} LIKE ? AND ${MediaStore.MediaColumns.IS_TRASHED} = 0",
            arrayOf("%Screenshots%"),
            "${MediaStore.Images.Media.DATE_ADDED} DESC",
        )?.use { c ->
            while (c.moveToNext()) {
                val taken = c.getLong(3).takeIf { it > 0 } ?: (c.getLong(4) * 1000)
                out.add(mapOf("id" to c.getLong(0), "path" to (c.getString(1) ?: continue), "name" to (c.getString(2) ?: ""), "date" to taken))
            }
        }
        return out
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_IMAGES) {
            pendingAccess?.success(hasImageAccess())
            pendingAccess = null
        }
        if (requestCode == REQUEST_SMS) {
            pendingSms?.success(hasSmsAccess())
            pendingSms = null
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_TRASH) {
            pendingTrash?.success(resultCode == RESULT_OK)
            pendingTrash = null
        }
        if (requestCode == REQUEST_HEALTH) {
            val pending = pendingHealth
            pendingHealth = null
            scope.launch { pending?.success(runCatching { Health.hasAccess(this@MainActivity) }.getOrDefault(false)) }
        }
    }

    private fun hasUsageAccess(): Boolean {
        val ops = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** Apps that are not "using the phone": the home screen and system chrome. */
    private fun ignoredPackages(): Set<String> {
        val home = packageManager.resolveActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), 0
        )?.activityInfo?.packageName
        return setOfNotNull(home, "com.android.systemui")
    }

    private fun label(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        pkg
    }

    /**
     * Foreground stretches in [from, to] as {app, name, start, end} (epoch ms).
     * An app is in front from the moment one of its activities resumes until
     * another app takes over or the screen turns off.
     */
    private fun foregroundSpans(from: Long, to: Long): List<Map<String, Any>> {
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(from, to)
        val ignored = ignoredPackages()
        val names = HashMap<String, String>()
        val spans = ArrayList<Map<String, Any>>()
        var current: String? = null
        var activity: String? = null
        var since = 0L

        fun close(at: Long) {
            val pkg = current ?: return
            if (at > since && pkg !in ignored) {
                spans.add(mapOf("app" to pkg, "name" to names.getOrPut(pkg) { label(pkg) }, "start" to since, "end" to at))
            }
            current = null
        }

        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            when (e.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    if (current != e.packageName) {
                        close(e.timeStamp)
                        current = e.packageName
                        since = e.timeStamp
                    }
                    activity = e.className
                }
                // Moving between two screens of one app pauses the old one
                // after the new one resumes; that is not leaving the app.
                UsageEvents.Event.ACTIVITY_PAUSED ->
                    if (current == e.packageName && activity == e.className) close(e.timeStamp)
                UsageEvents.Event.SCREEN_NON_INTERACTIVE,
                UsageEvents.Event.KEYGUARD_SHOWN,
                UsageEvents.Event.DEVICE_SHUTDOWN -> close(e.timeStamp)
            }
        }
        // Still in front right now.
        close(minOf(to, System.currentTimeMillis()))
        return spans
    }

    companion object {
        private const val REQUEST_IMAGES = 4101
        private const val REQUEST_TRASH = 4102
        private const val REQUEST_SMS = 4103
        private const val REQUEST_HEALTH = 4104
    }
}
