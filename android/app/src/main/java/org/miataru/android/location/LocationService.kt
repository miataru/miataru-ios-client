package org.miataru.android.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Looper
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Provides location updates similar to the iOS LocationManager.
 * Foreground activity can bind to this service to receive high accuracy updates
 * while background tracking uses a foreground notification.
 */
class LocationService(private val context: Context) {
    private val fused = LocationServices.getFusedLocationProviderClient(context)

    private val _location = MutableStateFlow<Location?>(null)
    val location: StateFlow<Location?> = _location

    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            _location.value = result.lastLocation
        }
    }

    @SuppressLint("MissingPermission")
    fun startTracking() {
        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            return
        }
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5_000).build()
        fused.requestLocationUpdates(request, callback, Looper.getMainLooper())
    }

    fun stopTracking() {
        fused.removeLocationUpdates(callback)
    }
}

data class Location(val latitude: Double, val longitude: Double)
