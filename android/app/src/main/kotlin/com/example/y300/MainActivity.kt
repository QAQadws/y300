package com.example.y300

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private companion object {
        const val EXPORT_CHANNEL = "com.adws.y300/reader_image_export"
        const val STORAGE_PERMISSION_REQUEST = 7301
    }

    private var pendingPermissionExport: PendingExport? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXPORT_CHANNEL)
            .setMethodCallHandler(::handleExportCall)
    }

    private fun handleExportCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "saveImage") {
            result.notImplemented()
            return
        }
        val sourcePath = call.argument<String>("sourcePath")?.trim().orEmpty()
        val displayName = call.argument<String>("displayName")?.trim().orEmpty()
        val mimeType = call.argument<String>("mimeType")?.trim().orEmpty()
        val albumName = call.argument<String>("albumName")?.trim().orEmpty().ifEmpty { "Y300" }
        if (sourcePath.isEmpty() || displayName.isEmpty() || mimeType.isEmpty()) {
            result.error("mediaWriteFailed", "Invalid image export request", null)
            return
        }
        val request = PendingExport(sourcePath, displayName, mimeType, albumName, result)
        if (Build.VERSION.SDK_INT in Build.VERSION_CODES.M..Build.VERSION_CODES.P &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingPermissionExport != null) {
                result.error("mediaWriteFailed", "Another permission request is active", null)
                return
            }
            pendingPermissionExport = request
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                STORAGE_PERMISSION_REQUEST,
            )
            return
        }
        saveImage(request)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != STORAGE_PERMISSION_REQUEST) return
        val request = pendingPermissionExport ?: return
        pendingPermissionExport = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            saveImage(request)
        } else {
            request.result.error("permissionDenied", "Storage permission was denied", null)
        }
    }

    private fun saveImage(request: PendingExport) {
        val source = File(request.sourcePath)
        if (!source.isFile) {
            request.result.error("mediaWriteFailed", "Cached image file is missing", null)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveToMediaStore(request, source)
            } else {
                saveToLegacyPictures(request, source)
            }
        } catch (error: Exception) {
            request.result.error("mediaWriteFailed", error.message, null)
        }
    }

    private fun saveToMediaStore(request: PendingExport, source: File) {
        val resolver = contentResolver
        val relativePath = "${Environment.DIRECTORY_PICTURES}/${request.albumName}"
        val displayName = uniqueMediaStoreName(request.displayName, relativePath)
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, request.mimeType)
            put(MediaStore.Images.Media.RELATIVE_PATH, relativePath)
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Unable to create MediaStore entry")
        try {
            resolver.openOutputStream(uri, "w")?.use { output ->
                FileInputStream(source).use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("Unable to open MediaStore output")
            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) },
                null,
                null,
            )
            request.result.success(
                mapOf(
                    "locator" to uri.toString(),
                    "displayLocation" to "$relativePath/$displayName",
                ),
            )
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun uniqueMediaStoreName(displayName: String, relativePath: String): String {
        val dot = displayName.lastIndexOf('.')
        val base = if (dot > 0) displayName.substring(0, dot) else displayName
        val extension = if (dot > 0) displayName.substring(dot) else ""
        var candidate = displayName
        var suffix = 1
        while (mediaStoreNameExists(candidate, relativePath)) {
            candidate = "$base ($suffix)$extension"
            suffix += 1
        }
        return candidate
    }

    private fun mediaStoreNameExists(displayName: String, relativePath: String): Boolean {
        val projection = arrayOf(MediaStore.Images.Media._ID)
        val selection =
            "${MediaStore.Images.Media.DISPLAY_NAME}=? AND ${MediaStore.Images.Media.RELATIVE_PATH}=?"
        val normalizedPath = if (relativePath.endsWith('/')) relativePath else "$relativePath/"
        return contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            arrayOf(displayName, normalizedPath),
            null,
        )?.use { it.moveToFirst() } == true
    }

    @Suppress("DEPRECATION")
    private fun saveToLegacyPictures(request: PendingExport, source: File) {
        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
            request.albumName,
        )
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("Unable to create Pictures directory")
        }
        val destination = uniqueLegacyFile(directory, request.displayName)
        FileInputStream(source).use { input ->
            FileOutputStream(destination).use { output -> input.copyTo(output) }
        }
        MediaScannerConnection.scanFile(
            this,
            arrayOf(destination.absolutePath),
            arrayOf(request.mimeType),
        ) { _, uri ->
            request.result.success(
                mapOf(
                    "locator" to (uri ?: Uri.fromFile(destination)).toString(),
                    "displayLocation" to "Pictures/${request.albumName}/${destination.name}",
                ),
            )
        }
    }

    private fun uniqueLegacyFile(directory: File, displayName: String): File {
        val dot = displayName.lastIndexOf('.')
        val base = if (dot > 0) displayName.substring(0, dot) else displayName
        val extension = if (dot > 0) displayName.substring(dot) else ""
        var candidate = File(directory, displayName)
        var suffix = 1
        while (candidate.exists()) {
            candidate = File(directory, "$base ($suffix)$extension")
            suffix += 1
        }
        return candidate
    }

    private data class PendingExport(
        val sourcePath: String,
        val displayName: String,
        val mimeType: String,
        val albumName: String,
        val result: MethodChannel.Result,
    )
}
