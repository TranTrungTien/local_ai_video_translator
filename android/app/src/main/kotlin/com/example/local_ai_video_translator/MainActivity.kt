package com.example.local_ai_video_translator

import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Native extension point for Android runtime media discovery, candidate verification,
 * and hardware capability profiling.
 */
class MainActivity : FlutterActivity() {
    companion object {
        const val MEDIA_EVENTS_CHANNEL = "local_ai_video_translator/media_events"
        const val AUDIO_PCM_CHANNEL = "local_ai_video_translator/audio_pcm"
        const val NATIVE_RESOLVER_CHANNEL = "local_ai_video_translator/native_resolver"
        const val REQUEST_MEDIA_PROJECTION = 1001

        private var eventSink: EventChannel.EventSink? = null
        private val mainHandler = Handler(Looper.getMainLooper())

        fun emitMediaEvent(eventData: Map<String, Any?>) {
            mainHandler.post {
                eventSink?.success(eventData)
            }
        }
    }

    private var pendingAudioResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Stream channel for runtime media discovery events
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_EVENTS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        // EventChannel for PCM audio data
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_PCM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    AudioPcmBroker.setSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    AudioPcmBroker.setSink(null)
                }
            })

        // Method channel for candidate verification and device metrics
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_RESOLVER_CHANNEL)
            .setMethodCallHandler(object : MethodChannel.MethodCallHandler {
                override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
                    when (call.method) {
                        "startAudioCapture" -> {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                                result.error("UNSUPPORTED", "Audio capture requires Android 10+", null)
                                return
                            }
                            pendingAudioResult = result
                            val mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                            startActivityForResult(mediaProjectionManager.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
                        }

                        "stopAudioCapture" -> {
                            val intent = Intent(this@MainActivity, AudioCaptureService::class.java).apply {
                                action = AudioCaptureService.ACTION_STOP
                            }
                            startService(intent)
                            result.success(true)
                        }

                        "verifyCandidate" -> {
                            val urlStr = call.argument<String>("url")
                            val headersMap: Map<String, String>? = call.argument("headers")
                            if (urlStr.isNullOrEmpty()) {
                                result.error("INVALID_ARG", "URL is null or empty", null)
                                return
                            }
                            thread {
                                try {
                                    val url = URL(urlStr)
                                    val conn = url.openConnection() as HttpURLConnection
                                    conn.requestMethod = "HEAD"
                                    conn.connectTimeout = 8000
                                    conn.readTimeout = 8000
                                    conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 13) LocalAIVideoTranslator/1.0")
                                    if (headersMap != null) {
                                        for ((k, v) in headersMap) {
                                            conn.setRequestProperty(k, v)
                                        }
                                    }
                                    conn.instanceFollowRedirects = true
                                    val responseCode = conn.responseCode
                                    val contentType = conn.contentType ?: ""
                                    val contentLength = conn.contentLengthLong

                                    val resMap = mapOf(
                                        "url" to urlStr,
                                        "statusCode" to responseCode,
                                        "contentType" to contentType,
                                        "contentLength" to contentLength,
                                        "isAccessible" to (responseCode in 200..299 || responseCode == 302 || responseCode == 301)
                                    )
                                    conn.disconnect()
                                    mainHandler.post { result.success(resMap) }
                                } catch (e: Exception) {
                                    mainHandler.post {
                                        result.success(
                                            mapOf(
                                                "url" to urlStr,
                                                "statusCode" to -1,
                                                "contentType" to "",
                                                "contentLength" to -1L,
                                                "isAccessible" to false,
                                                "error" to (e.message ?: "Network error")
                                            )
                                        )
                                    }
                                }
                            }
                        }

                        "getDeviceCapabilities" -> {
                            val runtime = Runtime.getRuntime()
                            val maxMemoryMb = runtime.maxMemory() / (1024 * 1024)
                            val availableProcessors = runtime.availableProcessors()
                            val capabilities = mapOf(
                                "maxMemoryMb" to maxMemoryMb,
                                "cores" to availableProcessors,
                                "sdkInt" to Build.VERSION.SDK_INT,
                                "model" to Build.MODEL,
                                "manufacturer" to Build.MANUFACTURER,
                                "supportsNnapi" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                            )
                            result.success(capabilities)
                        }

                        "getMonotonicUs" -> {
                            result.success(System.nanoTime() / 1000)
                        }

                        "reportObservedResource" -> {
                            val urlStr = call.argument<String>("url")
                            val mime = call.argument<String>("mimeType") ?: ""
                            if (!urlStr.isNullOrEmpty()) {
                                emitMediaEvent(
                                    mapOf(
                                        "url" to urlStr,
                                        "mimeType" to mime,
                                        "timestamp" to System.currentTimeMillis()
                                    )
                                )
                            }
                            result.success(true)
                        }

                        "updateAudioAnchor" -> {
                            val mediaPositionUs = call.argument<Long>("mediaPositionUs") ?: 0L
                            val anchorMonotonicUs = call.argument<Long>("anchorMonotonicUs") ?: 0L
                            val playbackRate = call.argument<Double>("playbackRate") ?: 1.0
                            val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                            val isBuffering = call.argument<Boolean>("isBuffering") ?: false
                            val timelineEpoch = call.argument<Int>("timelineEpoch") ?: 0
                            val playbackSessionId = call.argument<String>("playbackSessionId") ?: ""
                            val seekGeneration = call.argument<Int>("seekGeneration") ?: 0

                            AudioPcmBroker.updateAnchor(
                                mediaPositionUs,
                                anchorMonotonicUs,
                                playbackRate,
                                isPlaying,
                                isBuffering,
                                timelineEpoch,
                                playbackSessionId,
                                seekGeneration
                            )
                            result.success(true)
                        }

                        else -> result.notImplemented()
                    }
                }
            })
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            if (resultCode == RESULT_OK && data != null) {
                val intent = Intent(this, AudioCaptureService::class.java).apply {
                    action = AudioCaptureService.ACTION_START
                    putExtra(AudioCaptureService.EXTRA_RESULT_CODE, resultCode)
                    putExtra(AudioCaptureService.EXTRA_DATA, data)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
                pendingAudioResult?.success(true)
            } else {
                pendingAudioResult?.error("PERMISSION_DENIED", "MediaProjection permission denied", null)
            }
            pendingAudioResult = null
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}

class ObservingWebViewClient(
    private val onResource: (String) -> Unit,
) : WebViewClient() {
    private val mediaPatterns = listOf(".m3u8", ".mpd", ".mp4", ".webm", ".m4v")

    override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
        request?.url?.toString()?.let { url ->
            val isMedia = mediaPatterns.any { url.contains(it, ignoreCase = true) }
            if (isMedia || request.isForMainFrame) {
                onResource(url)
                MainActivity.emitMediaEvent(
                    mapOf(
                        "url" to url,
                        "method" to (request.method ?: "GET"),
                        "isForMainFrame" to request.isForMainFrame,
                        "timestamp" to System.currentTimeMillis()
                    )
                )
            }
        }
        return super.shouldInterceptRequest(view, request)
    }
}
