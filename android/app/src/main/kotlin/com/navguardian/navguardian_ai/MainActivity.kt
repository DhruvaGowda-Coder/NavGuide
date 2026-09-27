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
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.navguardian.ai/telephony"
    private val ALARM_CHANNEL = "com.navguardian.ai/alarm"
    private var mediaPlayer: MediaPlayer? = null
    private var requestedPhoneState = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCellTowerInfo" -> {
                    try {
                        if (!requestedPhoneState) {
                            val missingPermissions = mutableListOf<String>()
                            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
                                missingPermissions.add(Manifest.permission.READ_PHONE_STATE)
                            }
                            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                                missingPermissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
                            }
                            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                                missingPermissions.add(Manifest.permission.ACCESS_COARSE_LOCATION)
                            }
                            if (missingPermissions.isNotEmpty()) {
                                requestedPhoneState = true
                                ActivityCompat.requestPermissions(this, missingPermissions.toTypedArray(), 101)
                            }
                        }
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

    private fun cleanCarrierName(raw: String?): String {
        if (raw.isNullOrBlank()) return ""
        val lower = raw.trim().lowercase()
        return when {
            lower.contains("jio") || lower.contains("reliance") -> "JIO"
            lower.contains("airtel") || lower.contains("bharti") -> "AIRTEL"
            lower.contains("vodafone") || lower.contains("idea") || lower.contains("vi") -> "VI"
            lower.contains("bsnl") || lower.contains("cellone") -> "BSNL"
            raw.trim().length in 2..15 -> raw.trim().uppercase()
            else -> ""
        }
    }

    private fun mapPlmnToCarrier(mcc: String?, mnc: String?): String? {
        if (mcc.isNullOrEmpty() || mnc.isNullOrEmpty()) return null
        if (mcc == "405") {
            val mncInt = mnc.toIntOrNull()
            if (mncInt != null && mncInt in 840..874) return "JIO"
        }
        if (mcc == "404") {
            val mncInt = mnc.toIntOrNull()
            if (mncInt != null) {
                if (mncInt in listOf(2, 10, 16, 20, 31, 40, 45, 49, 70, 90)) return "AIRTEL"
                if (mncInt in listOf(4, 7, 11, 13, 15, 27, 43, 46, 84, 86)) return "VI"
                if (mncInt in listOf(34, 38, 51, 53, 54, 55, 57, 58, 59, 62, 64, 66, 71, 72, 73, 74, 75, 76, 77, 80, 81)) return "BSNL"
            }
        }
        return null
    }

    private fun readCurrentCellTowerInfo(): Map<String, Any?> {
        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            ?: return mapOf("status" to "UNAVAILABLE")

        val carrierName = telephonyManager.networkOperatorName.ifEmpty { telephonyManager.simOperatorName }
        val operatorCode = telephonyManager.networkOperator

        // Detect all active SIM carriers (e.g. Jio and Airtel on Dual SIM phones)
        val detectedCarriers = mutableListOf<String>()

        // 1. Check active subscriptions if permission granted
        try {
            val subManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            val hasPhoneState = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED
            if (subManager != null && hasPhoneState) {
                val subs = subManager.activeSubscriptionInfoList
                if (!subs.isNullOrEmpty()) {
                    for (sub in subs) {
                        val name = sub.carrierName?.toString()?.trim()?.ifEmpty { sub.displayName?.toString()?.trim() }
                        val clean = cleanCarrierName(name)
                        if (clean.isNotEmpty() && !detectedCarriers.contains(clean)) {
                            detectedCarriers.add(clean)
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        // 2. Add primary network and SIM operator names
        val cleanNet = cleanCarrierName(telephonyManager.networkOperatorName)
        if (cleanNet.isNotEmpty() && !detectedCarriers.contains(cleanNet)) {
            detectedCarriers.add(cleanNet)
        }
        val cleanSim = cleanCarrierName(telephonyManager.simOperatorName)
        if (cleanSim.isNotEmpty() && !detectedCarriers.contains(cleanSim)) {
            detectedCarriers.add(cleanSim)
        }

        val hasFine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val hasCoarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

        var registeredCellId: Long = 0
        var registeredLac: Int = 0
        var registeredMcc: String = ""
        var registeredMnc: String = ""
        var signalDbm: Int = -999
        var networkType: String = "CELLULAR"

        if (hasFine || hasCoarse) {
            try {
                val cellInfoList: List<CellInfo>? = telephonyManager.allCellInfo
                if (!cellInfoList.isNullOrEmpty()) {
                    for (info in cellInfoList) {
                        // Scan carrier name from every cell in cellInfoList
                        val opName = when (info) {
                            is CellInfoLte -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.cellIdentity.operatorAlphaLong?.toString() else null
                            is CellInfoNr -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) (info.cellIdentity as? CellIdentityNr)?.operatorAlphaLong?.toString() else null
                            is CellInfoGsm -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.cellIdentity.operatorAlphaLong?.toString() else null
                            is CellInfoWcdma -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.cellIdentity.operatorAlphaLong?.toString() else null
                            else -> null
                        }
                        val cleanOp = cleanCarrierName(opName)
                        if (cleanOp.isNotEmpty() && !detectedCarriers.contains(cleanOp)) {
                            detectedCarriers.add(cleanOp)
                        }

                        val mcc = when (info) {
                            is CellInfoLte -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.cellIdentity.mccString else null
                            is CellInfoNr -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) (info.cellIdentity as? CellIdentityNr)?.mccString else null
                            is CellInfoGsm -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.cellIdentity.mccString else null
                            is CellInfoWcdma -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.cellIdentity.mccString else null
                            else -> null
                        }
                        val mnc = when (info) {
                            is CellInfoLte -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.cellIdentity.mncString else null
                            is CellInfoNr -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) (info.cellIdentity as? CellIdentityNr)?.mncString else null
                            is CellInfoGsm -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.cellIdentity.mncString else null
                            is CellInfoWcdma -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.cellIdentity.mncString else null
                            else -> null
                        }
                        val plmnCarrier = mapPlmnToCarrier(mcc, mnc)
                        if (plmnCarrier != null && !detectedCarriers.contains(plmnCarrier)) {
                            detectedCarriers.add(plmnCarrier)
                        }

                        if (info.isRegistered && registeredCellId == 0L) {
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
                        }
                    }
                }
            } catch (ignored: SecurityException) {
                // Permission or hardware restriction
            }
        }

        val finalCarrier = if (detectedCarriers.isNotEmpty()) {
            detectedCarriers.joinToString(" • ")
        } else if (carrierName.isNotEmpty()) {
            carrierName.uppercase()
        } else {
            "CELLULAR"
        }

        if (!hasFine && !hasCoarse) {
            return mapOf(
                "status" to "PERMISSION_DENIED",
                "carrier" to finalCarrier,
                "operatorCode" to operatorCode
            )
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

    @Volatile
    private var isSirenRunning = false
    private var sirenThread: Thread? = null
    private var vibrator: Vibrator? = null

    private fun playAlarmSound() {
        stopAlarmSound()
        isSirenRunning = true

        // 1. Heavy Pulsing Emergency Vibration
        try {
            vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val timings = longArrayOf(0, 450, 150, 450, 150, 450, 400)
                val amplitudes = intArrayOf(0, 255, 0, 255, 0, 255, 0)
                vibrator?.vibrate(VibrationEffect.createWaveform(timings, amplitudes, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(longArrayOf(0, 450, 150, 450, 150, 450, 400), 0)
            }
        } catch (_: Exception) {}

        // 2. Global High-Intensity Emergency Siren Synthesizer (Alternating Dual-Tone European/Ambulance Siren)
        sirenThread = Thread {
            val sampleRate = 44100
            val minBufferSize = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            val bufferSize = Math.max(minBufferSize, sampleRate / 2)
            val audioTrack: AudioTrack = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    AudioTrack(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                        AudioFormat.Builder()
                            .setSampleRate(sampleRate)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .build(),
                        bufferSize,
                        AudioTrack.MODE_STREAM,
                        AudioManager.AUDIO_SESSION_ID_GENERATE
                    )
                } else {
                    @Suppress("DEPRECATION")
                    AudioTrack(
                        AudioManager.STREAM_ALARM,
                        sampleRate,
                        AudioFormat.CHANNEL_OUT_MONO,
                        AudioFormat.ENCODING_PCM_16BIT,
                        bufferSize,
                        AudioTrack.MODE_STREAM
                    )
                }
            } catch (e: Exception) {
                return@Thread
            }

            try {
                audioTrack.play()
                val chunk = ShortArray(2048)
                var phase = 0.0
                var currentFreq = 750.0
                var freqDirection = 1.0
                val minFreq = 750.0
                val maxFreq = 1250.0

                while (isSirenRunning && !Thread.currentThread().isInterrupted) {
                    for (i in chunk.indices) {
                        phase += 2.0 * Math.PI * currentFreq / sampleRate
                        if (phase > 2.0 * Math.PI) phase -= 2.0 * Math.PI

                        // Rich acoustic harmonic (sine wave + second harmonic for penetrating emergency clarity)
                        val sample = (Math.sin(phase) * 0.75 + Math.sin(phase * 2.0) * 0.25) * 32767 * 0.95
                        chunk[i] = sample.toInt().toShort()

                        // Sweeping siren modulation
                        currentFreq += freqDirection * 0.8
                        if (currentFreq >= maxFreq) {
                            currentFreq = maxFreq
                            freqDirection = -1.0
                        } else if (currentFreq <= minFreq) {
                            currentFreq = minFreq
                            freqDirection = 1.0
                        }
                    }
                    audioTrack.write(chunk, 0, chunk.size)
                }
            } catch (_: Exception) {
            } finally {
                try {
                    audioTrack.stop()
                    audioTrack.release()
                } catch (_: Exception) {}
            }
        }.apply {
            priority = Thread.MAX_PRIORITY
            isDaemon = true
            start()
        }
    }

    private fun stopAlarmSound() {
        isSirenRunning = false
        sirenThread?.interrupt()
        sirenThread = null
        try {
            vibrator?.cancel()
            vibrator = null
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        stopAlarmSound()
        super.onDestroy()
    }
}
