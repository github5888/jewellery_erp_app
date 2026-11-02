package com.example.jewellery_erp

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.print.PrintAttributes
import android.print.PrintManager
import android.provider.MediaStore
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "jewellery_erp/device"
        private const val REQ_PICK_IMAGE = 9411
    }

    private var pendingImageResult: MethodChannel.Result? = null
    private var pendingMaxBytes: Int = 500 * 1024
    private var activePrintWebView: WebView? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImage" -> handlePickImage(call, result)
                    "saveFileToDownloads" -> handleSaveFileToDownloads(call, result)
                    "openUri" -> handleOpenUri(call, result)
                    "shareUri" -> handleShareUri(call, result)
                    "printHtml" -> handlePrintHtml(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handlePickImage(call: MethodCall, result: MethodChannel.Result) {
        if (pendingImageResult != null) {
            result.error("BUSY", "Another image picker request is already active.", null)
            return
        }
        val mode = call.argument<String>("mode") ?: "photos"
        pendingMaxBytes = call.argument<Int>("maxBytes") ?: (500 * 1024)
        pendingImageResult = result

        try {
            val intent = if (mode == "files") {
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "image/*"
                    putExtra(
                        Intent.EXTRA_MIME_TYPES,
                        arrayOf("image/png", "image/jpeg", "image/webp")
                    )
                }
            } else {
                Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply {
                    type = "image/*"
                }
            }
            startActivityForResult(intent, REQ_PICK_IMAGE)
        } catch (_: Exception) {
            try {
                val fallback = Intent(Intent.ACTION_GET_CONTENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "image/*"
                }
                startActivityForResult(
                    Intent.createChooser(fallback, "Select Showroom Logo"),
                    REQ_PICK_IMAGE
                )
            } catch (e: Exception) {
                pendingImageResult = null
                result.error("PICKER_FAILED", e.message ?: "Unable to open device photos.", null)
            }
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PICK_IMAGE) return

        val callback = pendingImageResult ?: return
        pendingImageResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            callback.success(null)
            return
        }

        val uri = data.data!!
        try {
            val rawBytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
            if (rawBytes == null || rawBytes.isEmpty()) {
                callback.error("EMPTY_IMAGE", "Selected image could not be read.", null)
                return
            }
            val normalized = normalizeLogoBytes(rawBytes, pendingMaxBytes)
            callback.success(normalized)
        } catch (e: Exception) {
            callback.error("READ_FAILED", e.message ?: "Unable to read selected photo.", null)
        }
    }

    private fun detectMime(bytes: ByteArray): String? {
        if (bytes.size >= 8 &&
            bytes[0] == 0x89.toByte() &&
            bytes[1] == 0x50.toByte() &&
            bytes[2] == 0x4E.toByte() &&
            bytes[3] == 0x47.toByte()
        ) {
            return "image/png"
        }
        if (bytes.size >= 3 &&
            bytes[0] == 0xFF.toByte() &&
            bytes[1] == 0xD8.toByte() &&
            bytes[2] == 0xFF.toByte()
        ) {
            return "image/jpeg"
        }
        if (bytes.size >= 12 &&
            bytes[0] == 0x52.toByte() &&
            bytes[1] == 0x49.toByte() &&
            bytes[2] == 0x46.toByte() &&
            bytes[3] == 0x46.toByte() &&
            bytes[8] == 0x57.toByte() &&
            bytes[9] == 0x45.toByte() &&
            bytes[10] == 0x42.toByte() &&
            bytes[11] == 0x50.toByte()
        ) {
            return "image/webp"
        }
        return null
    }

    private fun normalizeLogoBytes(raw: ByteArray, maxBytes: Int): Map<String, Any> {
        val detected = detectMime(raw)
        if (detected != null && raw.size <= maxBytes) {
            val ext = when (detected) {
                "image/png" -> "png"
                "image/webp" -> "webp"
                else -> "jpg"
            }
            return mapOf(
                "bytes" to raw,
                "mimeType" to detected,
                "fileName" to "showroom-logo.$ext"
            )
        }

        val decoded = BitmapFactory.decodeByteArray(raw, 0, raw.size)
            ?: throw IllegalArgumentException("Unsupported image format. Select a PNG, JPEG, or WebP photo.")

        var bmp: Bitmap = decoded
        val longest = max(bmp.width, bmp.height)
        if (longest > 900) {
            val scale = 900.0 / longest.toDouble()
            val nw = max(1, (bmp.width * scale).roundToInt())
            val nh = max(1, (bmp.height * scale).roundToInt())
            bmp = Bitmap.createScaledBitmap(bmp, nw, nh, true)
        }

        if (bmp.hasAlpha()) {
            val pngOut = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.PNG, 100, pngOut)
            val pngBytes = pngOut.toByteArray()
            if (pngBytes.size <= maxBytes) {
                return mapOf(
                    "bytes" to pngBytes,
                    "mimeType" to "image/png",
                    "fileName" to "showroom-logo.png"
                )
            }
        }

        for (quality in listOf(90, 82, 74, 65, 55, 45)) {
            val jpgOut = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, quality, jpgOut)
            val jpgBytes = jpgOut.toByteArray()
            if (jpgBytes.size <= maxBytes || quality == 45) {
                return mapOf(
                    "bytes" to jpgBytes,
                    "mimeType" to "image/jpeg",
                    "fileName" to "showroom-logo.jpg"
                )
            }
        }

        return mapOf(
            "bytes" to raw,
            "mimeType" to (detected ?: "image/jpeg"),
            "fileName" to "showroom-logo.jpg"
        )
    }

    private fun handleSaveFileToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val rawName = call.argument<String>("fileName") ?: "JewelleryERP-Document.pdf"
        val mimeType = call.argument<String>("mimeType") ?: "application/pdf"

        if (bytes == null || bytes.isEmpty()) {
            result.error("EMPTY_BYTES", "No file content to save.", null)
            return
        }

        val safeName = rawName.replace(Regex("[^A-Za-z0-9._-]"), "_")
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        Environment.DIRECTORY_DOWNLOADS + "/JewelleryERP"
                    )
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val resolver = applicationContext.contentResolver
                val itemUri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("Could not create entry in Downloads.")

                resolver.openOutputStream(itemUri)?.use { out ->
                    out.write(bytes)
                    out.flush()
                } ?: throw IllegalStateException("Could not write bytes to Downloads.")

                val doneValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(itemUri, doneValues, null, null)

                result.success(
                    mapOf(
                        "savedPath" to "Downloads/JewelleryERP/$safeName",
                        "uri" to itemUri.toString()
                    )
                )
            } else {
                val dir = File(
                    getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir,
                    "JewelleryERP"
                )
                if (!dir.exists()) dir.mkdirs()
                val outFile = File(dir, safeName)
                FileOutputStream(outFile).use { out ->
                    out.write(bytes)
                    out.flush()
                }
                result.success(
                    mapOf(
                        "savedPath" to outFile.absolutePath,
                        "uri" to Uri.fromFile(outFile).toString()
                    )
                )
            }
        } catch (e: Exception) {
            result.error("SAVE_FAILED", e.message ?: "Failed to save file to Downloads.", null)
        }
    }

    private fun handleOpenUri(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri") ?: ""
        val mimeType = call.argument<String>("mimeType") ?: "application/pdf"
        if (uriStr.isEmpty()) {
            result.error("NO_URI", "Missing file URI.", null)
            return
        }
        try {
            val uri = Uri.parse(uriStr)
            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(Intent.createChooser(viewIntent, "Open Document"))
            result.success(true)
        } catch (e: Exception) {
            result.error("OPEN_FAILED", e.message ?: "No PDF viewer installed on device.", null)
        }
    }

    private fun handleShareUri(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri") ?: ""
        val mimeType = call.argument<String>("mimeType") ?: "application/pdf"
        val title = call.argument<String>("title") ?: "Share Document"
        if (uriStr.isEmpty()) {
            result.error("NO_URI", "Missing file URI.", null)
            return
        }
        try {
            val uri = Uri.parse(uriStr)
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(shareIntent, title))
            result.success(true)
        } catch (e: Exception) {
            result.error("SHARE_FAILED", e.message ?: "Unable to open share sheet.", null)
        }
    }

    private fun handlePrintHtml(call: MethodCall, result: MethodChannel.Result) {
        val html = call.argument<String>("html") ?: ""
        val jobName = call.argument<String>("jobName") ?: "JewelleryERP-Document"
        if (html.isEmpty()) {
            result.error("EMPTY_HTML", "Empty HTML document.", null)
            return
        }
        runOnUiThread {
            try {
                val webView = WebView(this)
                activePrintWebView = webView
                webView.webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView, url: String?) {
                        try {
                            val pm = getSystemService(Context.PRINT_SERVICE) as PrintManager
                            val adapter = view.createPrintDocumentAdapter(jobName)
                            val attrs = PrintAttributes.Builder()
                                .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
                                .setResolution(PrintAttributes.Resolution("pdf", "PDF", 300, 300))
                                .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                                .build()
                            pm.print(jobName, adapter, attrs)
                        } catch (_: Exception) {
                        }
                    }
                }
                webView.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
                result.success(true)
            } catch (e: Exception) {
                result.error("PRINT_FAILED", e.message ?: "Unable to open Android Print / Save PDF.", null)
            }
        }
    }
}
