package org.miataru.android.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Simple JSON backed store mirroring the iOS KnownDeviceStore.
 */
class KnownDeviceStore(private val context: Context) {
    private val file: File = File(context.filesDir, "devices.json")

    private val _devices = MutableStateFlow<List<String>>(emptyList())
    val devices: StateFlow<List<String>> = _devices

    init {
        load()
    }

    fun add(deviceId: String) {
        val updated = _devices.value + deviceId
        _devices.value = updated
        save(updated)
    }

    private fun load() {
        if (!file.exists()) return
        val json = JSONArray(file.readText())
        val loaded = mutableListOf<String>()
        for (i in 0 until json.length()) {
            loaded += json.getString(i)
        }
        _devices.value = loaded
    }

    private fun save(devices: List<String>) {
        val array = JSONArray()
        devices.forEach { array.put(it) }
        file.writeText(array.toString())
    }
}
