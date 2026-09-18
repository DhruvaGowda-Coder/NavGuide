package com.navguardian.navguardian_ai

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.CellIdentityGsm
import android.telephony.CellIdentityLte
import android.telephony.CellIdentityNr
import android.telephony.CellIdentityWcdma
import android.telephony.CellInfo
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellInfoWcdma
import android.telephony.CellSignalStrengthGsm
import android.telephony.CellSignalStrengthLte
import android.telephony.CellSignalStrengthNr
import android.telephony.CellSignalStrengthWcdma
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.navguardian.ai/telephony"
    private val ALARM_CHANNEL = "com.navguardian.ai/alarm"
    private var mediaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCellTowerInfo" -> {
                    try {
                        val data = readCurrentCellTowerInfo()
                        result.success(data)
                    } catch (e: Exception) {
                        result.error("TELEPHONY_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playAlarmSound" -> {
                    try {
                        playAlarmSound()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ALARM_ERROR", e.message, null)
                    }
                }
                "stopAlarmSound" -> {
                    try {
                        stopAlarmSound()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ALARM_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun readCurrentCellTowerInfo(): Map<String, Any?> {
        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            ?: return mapOf("status" to "UNAVAILABLE")

        val carrierName = telephonyManager.networkOperatorName.ifEmpty { telephonyManager.simOperatorName }
        val operatorCode = telephonyManager.networkOperator

        // Detect all active SIM carriers (e.g. Jio and Airtel on Dual SIM phones)
        val detectedCarriers = mutableListOf<String>()
        try {
            val subManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            val hasPhoneState = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED
            if (subManager != null && hasPhoneState) {
                val subs = subManager.activeSubscriptionInfoList
                if (!subs.isNullOrEmpty()) {
                    for (sub in subs) {
                        val name = sub.carrierName?.toString()?.trim()?.ifEmpty { sub.displayName?.toString()?.trim() } ?: ""
                        if (name.isNotEmpty()) {
                            val clean = name.uppercase()
                            if (!detectedCarriers.contains(clean)) {
                                detectedCarriers.add(clean)
                            }
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        val finalCarrier = if (detectedCarriers.isNotEmpty()) {
            detectedCarriers.joinToString(" • ")
        } else if (carrierName.isNotEmpty()) {
            carrierName.uppercase()
        } else {
            "CELLULAR"
        }

        val hasFine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val hasCoarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

        if (!hasFine && !hasCoarse) {
            return mapOf(
                "status" to "PERMISSION_DENIED",
                "carrier" to finalCarrier,
                "operatorCode" to operatorCode
            )
        }

        var registeredCellId: Long = 0
        var registeredLac: Int = 0
        var registeredMcc: String = ""
        var registeredMnc: String = ""
        var signalDbm: Int = -999
        var networkType: String = "CELLULAR"

        try {
            val cellInfoList: List<CellInfo>? = telephonyManager.allCellInfo
            if (!cellInfoList.isNullOrEmpty()) {
                for (info in cellInfoList) {
                    if (info.isRegistered) {
                        when (info) {
                            is CellInfoLte -> {
                                networkType = "4G LTE"
                                val identity: CellIdentityLte = info.cellIdentity
                                registeredCellId = identity.ci.toLong()
                                registeredLac = identity.tac
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                    registeredMcc = identity.mccString ?: ""
                                    registeredMnc = identity.mncString ?: ""
                                }
                                val signal: CellSignalStrengthLte = info.cellSignalStrength
                                signalDbm = signal.dbm
                            }
                            is CellInfoNr -> {
                                networkType = "5G NR"
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    val identity = info.cellIdentity as? CellIdentityNr
                                    if (identity != null) {
                                        registeredCellId = identity.nci
                                        registeredLac = identity.tac
                                        registeredMcc = identity.mccString ?: ""
                                        registeredMnc = identity.mncString ?: ""
                                    }
                                    val signal = info.cellSignalStrength as? CellSignalStrengthNr
                                    if (signal != null) {
                                        signalDbm = signal.dbm
                                    }
                                }
                            }
                            is CellInfoGsm -> {
                                networkType = "2G GSM"
                                val identity: CellIdentityGsm = info.cellIdentity
                                registeredCellId = identity.cid.toLong()
                                registeredLac = identity.lac
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                    registeredMcc = identity.mccString ?: ""
                                    registeredMnc = identity.mncString ?: ""
                                }
                                val signal: CellSignalStrengthGsm = info.cellSignalStrength
                                signalDbm = signal.dbm
                            }
                            is CellInfoWcdma -> {
                                networkType = "3G WCDMA"
                                val identity: CellIdentityWcdma = info.cellIdentity
                                registeredCellId = identity.cid.toLong()
                                registeredLac = identity.lac
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                    registeredMcc = identity.mccString ?: ""
                                    registeredMnc = identity.mncString ?: ""
                                }
                                val signal: CellSignalStrengthWcdma = info.cellSignalStrength
                                signalDbm = signal.dbm
                            }
                        }
                        break
                    }
                }
            }
        } catch (ignored: SecurityException) {
            // Permission or hardware restriction
        }

        if (registeredCellId == Int.MAX_VALUE.toLong() || registeredCellId < 0) registeredCellId = 0
        if (registeredLac == Int.MAX_VALUE || registeredLac < 0) registeredLac = 0

        return mapOf(
            "status" to "OK",
            "carrier" to finalCarrier,
            "operatorCode" to operatorCode,
            "networkType" to networkType,
            "cellId" to registeredCellId,
            "lac" to registeredLac,
            "mcc" to registeredMcc,
            "mnc" to registeredMnc,
            "dbm" to signalDbm
        )
    }

    private fun playAlarmSound() {
        stopAlarmSound()
        try {
            var alertUri: Uri? = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            if (alertUri == null) {
                alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            }
            if (alertUri == null) {
                alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            }

            if (alertUri != null) {
                mediaPlayer = MediaPlayer().apply {
                    setDataSource(applicationContext, alertUri)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ALARM)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build()
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        setAudioStreamType(AudioManager.STREAM_ALARM)
                    }
                    isLooping = true
                    prepare()
                    start()
                }
            }
        } catch (e: Exception) {
            try {
                val notifUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                if (notifUri != null) {
                    mediaPlayer = MediaPlayer.create(applicationContext, notifUri)?.apply {
                        isLooping = true
                        start()
                    }
                }
            } catch (_: Exception) {}
        }
    }

    private fun stopAlarmSound() {
        try {
            mediaPlayer?.let {
                if (it.isPlaying) {
                    it.stop()
                }
                it.reset()
                it.release()
            }
            mediaPlayer = null
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        stopAlarmSound()
        super.onDestroy()
    }
}
