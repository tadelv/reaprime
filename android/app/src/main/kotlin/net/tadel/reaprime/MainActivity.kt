package net.tadel.reaprime

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.reaprime.updater/apk_installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val apkPath = call.argument<String>("apkPath")
                    if (apkPath != null) {
                        try {
                            installApk(apkPath)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "APK path is required", null)
                    }
                }
                "canInstallPackages" -> {
                    val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        packageManager.canRequestPackageInstalls()
                    } else {
                        true // Pre-Oreo doesn't need special permission
                    }
                    result.success(canInstall)
                }
                "requestInstallPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                    }
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun installApk(apkPath: String) {
        val apkFile = File(apkPath)
        
        if (!apkFile.exists()) {
            throw IllegalArgumentException("APK file does not exist: $apkPath")
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // Use FileProvider for Android 7.0+
                val apkUri = FileProvider.getUriForFile(
                    this@MainActivity,
                    "$packageName.fileprovider",
                    apkFile
                )
                setDataAndType(apkUri, "application/vnd.android.package-archive")
            } else {
                // Direct file URI for older versions
                setDataAndType(Uri.fromFile(apkFile), "application/vnd.android.package-archive")
            }
        }

        startActivity(intent)
    }
}

