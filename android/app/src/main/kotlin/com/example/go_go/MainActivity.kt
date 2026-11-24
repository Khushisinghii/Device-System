package com.example.go_go

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.go_go/direct_sms"
    private val SMS_PERMISSION_CODE = 101
    private var pendingResult: MethodChannel.Result? = null
    private var pendingPhone: String? = null
    private var pendingMessage: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "sendDirectSms") {
                val phone = call.argument<String>("phone")
                val message = call.argument<String>("message")

                if (phone.isNullOrEmpty() || message.isNullOrEmpty()) {
                    result.error("INVALID_ARGS", "Phone or message cannot be empty", null)
                    return@setMethodCallHandler
                }

                if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
                    pendingResult = result
                    pendingPhone = phone
                    pendingMessage = message
                    ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.SEND_SMS), SMS_PERMISSION_CODE)
                } else {
                    sendSmsInternal(phone, message, result)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun sendSmsInternal(phone: String, message: String, result: MethodChannel.Result?) {
        try {
            val smsManager: SmsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                this.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }

            val parts = smsManager.divideMessage(message)
            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
            } else {
                smsManager.sendTextMessage(phone, null, message, null, null)
            }
            result?.success(true)
        } catch (e: Exception) {
            result?.error("SMS_FAILED", e.localizedMessage, null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_PERMISSION_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                if (pendingPhone != null && pendingMessage != null) {
                    sendSmsInternal(pendingPhone!!, pendingMessage!!, pendingResult)
                }
            } else {
                pendingResult?.error("PERMISSION_DENIED", "SMS Permission denied", null)
            }
            pendingResult = null
            pendingPhone = null
            pendingMessage = null
        }
    }
}
