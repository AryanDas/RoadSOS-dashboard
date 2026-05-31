package com.example.roadsos

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.math.sqrt

class SensorService : Service(), SensorEventListener {

    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null
    private var gyroscope: Sensor? = null

    // Sliding window of 3 seconds at 50Hz = 150 samples
    private val windowSize = 150
    private val accBufferX = java.util.Collections.synchronizedList(ArrayList<Float>())
    private val accBufferY = java.util.Collections.synchronizedList(ArrayList<Float>())
    private val accBufferZ = java.util.Collections.synchronizedList(ArrayList<Float>())
    private val accBufferMag = java.util.Collections.synchronizedList(ArrayList<Float>())

    private val gyroBufferX = java.util.Collections.synchronizedList(ArrayList<Float>())
    private val gyroBufferY = java.util.Collections.synchronizedList(ArrayList<Float>())
    private val gyroBufferZ = java.util.Collections.synchronizedList(ArrayList<Float>())
    private val gyroBufferMag = java.util.Collections.synchronizedList(ArrayList<Float>())

    private val channelId = "RoadSOS_Sensor_Channel"
    private val notificationId = 101

    override fun onCreate() {
        super.onCreate()
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        gyroscope = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

        createNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                notificationId,
                createNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(notificationId, createNotification())
        }

        // Register at 50Hz (20,000 microseconds)
        accelerometer?.let {
            sensorManager.registerListener(this, it, 20000)
        }
        gyroscope?.let {
            sensorManager.registerListener(this, it, 20000)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        sensorManager.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return

        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        val mag = sqrt(x * x + y * y + z * z)

        if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
            addToBuffer(accBufferX, x)
            addToBuffer(accBufferY, y)
            addToBuffer(accBufferZ, z)
            addToBuffer(accBufferMag, mag)
        } else if (event.sensor.type == Sensor.TYPE_GYROSCOPE) {
            addToBuffer(gyroBufferX, x)
            addToBuffer(gyroBufferY, y)
            addToBuffer(gyroBufferZ, z)
            addToBuffer(gyroBufferMag, mag)
        }

        // Periodically run classification or send features
        if (accBufferMag.size >= windowSize && gyroBufferMag.size >= windowSize) {
            val features = compute44Features()
            // Send features to Flutter via broadcast/receiver or a static callback
            MainActivity.sendFeaturesToFlutter(features)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun addToBuffer(buffer: MutableList<Float>, value: Float) {
        synchronized(buffer) {
            buffer.add(value)
            if (buffer.size > windowSize) {
                buffer.removeAt(0)
            }
        }
    }

    private fun compute44Features(): FloatArray {
        val features = FloatArray(44)

        // Snapshot copies to avoid concurrent modification
        val ax = ArrayList(accBufferX)
        val ay = ArrayList(accBufferY)
        val az = ArrayList(accBufferZ)
        val am = ArrayList(accBufferMag)

        val gx = ArrayList(gyroBufferX)
        val gy = ArrayList(gyroBufferY)
        val gz = ArrayList(gyroBufferZ)
        val gm = ArrayList(gyroBufferMag)

        if (ax.isEmpty() || gx.isEmpty()) return features

        // Means (1-8)
        features[0] = ax.average().toFloat()
        features[1] = ay.average().toFloat()
        features[2] = az.average().toFloat()
        features[3] = am.average().toFloat()
        features[4] = gx.average().toFloat()
        features[5] = gy.average().toFloat()
        features[6] = gz.average().toFloat()
        features[7] = gm.average().toFloat()

        // Std Devs & Variances (9-24)
        features[8] = calculateStdDev(ax, features[0])
        features[9] = calculateStdDev(ay, features[1])
        features[10] = calculateStdDev(az, features[2])
        features[11] = calculateStdDev(am, features[3])
        features[12] = calculateStdDev(gx, features[4])
        features[13] = calculateStdDev(gy, features[5])
        features[14] = calculateStdDev(gz, features[6])
        features[15] = calculateStdDev(gm, features[7])

        features[16] = features[8] * features[8]
        features[17] = features[9] * features[9]
        features[18] = features[10] * features[10]
        features[19] = features[11] * features[11]
        features[20] = features[12] * features[12]
        features[21] = features[13] * features[13]
        features[22] = features[14] * features[14]
        features[23] = features[15] * features[15]

        // Maxs (25-32)
        features[24] = ax.maxOrNull() ?: 0f
        features[25] = ay.maxOrNull() ?: 0f
        features[26] = az.maxOrNull() ?: 0f
        features[27] = am.maxOrNull() ?: 0f
        features[28] = gx.maxOrNull() ?: 0f
        features[29] = gy.maxOrNull() ?: 0f
        features[30] = gz.maxOrNull() ?: 0f
        features[31] = gm.maxOrNull() ?: 0f

        // Mins (33-40)
        features[32] = ax.minOrNull() ?: 0f
        features[33] = ay.minOrNull() ?: 0f
        features[34] = az.minOrNull() ?: 0f
        features[35] = am.minOrNull() ?: 0f
        features[36] = gx.minOrNull() ?: 0f
        features[37] = gy.minOrNull() ?: 0f
        features[38] = gz.minOrNull() ?: 0f
        features[39] = gm.minOrNull() ?: 0f

        // Ranges (41-42)
        features[40] = features[27] - features[35] // Acc Mag Range
        features[41] = features[31] - features[39] // Gyro Mag Range

        // Current Magnitudes (43-44)
        features[42] = am.lastOrNull() ?: 0f
        features[43] = gm.lastOrNull() ?: 0f

        return features
    }

    private fun calculateStdDev(list: List<Float>, mean: Float): Float {
        var sum = 0f
        for (num in list) {
            sum += (num - mean) * (num - mean)
        }
        return sqrt(sum / list.size)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES:O) {
            val serviceChannel = NotificationChannel(
                channelId,
                "RoadSOS Sensor Monitoring",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("RoadSOS Active")
            .setContentText("Monitoring sensors for accident detection...")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .build()
    }
}
