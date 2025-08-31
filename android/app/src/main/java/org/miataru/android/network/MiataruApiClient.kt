package org.miataru.android.network

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Minimal HTTP client for Miataru API.
 */
class MiataruApiClient(private val baseUrl: String) {
    suspend fun getLocation(deviceId: String): JSONObject? = withContext(Dispatchers.IO) {
        val url = URL("$baseUrl/GetLocation")
        val body = "{\"DeviceId\":\"$deviceId\"}"
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            outputStream.use { it.write(body.toByteArray()) }
        }
        return@withContext conn.inputStream.use { stream ->
            val text = stream.bufferedReader().readText()
            JSONObject(text)
        }
    }
}
