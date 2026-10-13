package com.example.local_ai_video_translator

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object AudioPcmBroker {
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var mediaPositionUs: Long = 0
    @Volatile
    private var anchorMonotonicUs: Long = 0
    @Volatile
    private var playbackRate: Double = 1.0
    @Volatile
    private var isPlaying: Boolean = false
    @Volatile
    private var isBuffering: Boolean = false
    @Volatile
    private var timelineEpoch: Int = 0
    @Volatile
    private var playbackSessionId: String = ""
    @Volatile
    private var seekGeneration: Int = 0
    
    private var sequenceNumber: Long = 0

    fun setSink(sink: EventChannel.EventSink?) {
        mainHandler.post {
            eventSink = sink
        }
    }

    fun updateAnchor(
        mediaPositionUs: Long,
        anchorMonotonicUs: Long,
        playbackRate: Double,
        isPlaying: Boolean,
        isBuffering: Boolean,
        timelineEpoch: Int,
        playbackSessionId: String,
        seekGeneration: Int
    ) {
        this.mediaPositionUs = mediaPositionUs
        this.anchorMonotonicUs = anchorMonotonicUs
        this.playbackRate = playbackRate
        this.isPlaying = isPlaying
        this.isBuffering = isBuffering
        this.timelineEpoch = timelineEpoch
        this.playbackSessionId = playbackSessionId
        this.seekGeneration = seekGeneration
    }

    fun emitAudioChunk(
        pcmBytes: ByteArray,
        sampleRate: Int,
        channelCount: Int,
        encoding: Int,
        captureMonotonicUs: Long,
        durationUs: Long
    ) {
        if (!isPlaying || isBuffering) {
            return
        }

        val elapsedUs = captureMonotonicUs - anchorMonotonicUs
        val estimatedMediaPtsUs = mediaPositionUs + (elapsedUs * playbackRate).toLong()

        val event = mapOf(
            "type" to "audio_chunk",
            "playbackSessionId" to playbackSessionId,
            "timelineEpoch" to timelineEpoch,
            "seekGeneration" to seekGeneration,
            "sequenceNumber" to sequenceNumber++,
            "sampleRate" to sampleRate,
            "channelCount" to channelCount,
            "encoding" to encoding,
            "mediaPtsUs" to estimatedMediaPtsUs,
            "durationUs" to durationUs,
            "pcmBytes" to pcmBytes
        )

        mainHandler.post {
            eventSink?.success(event)
        }
    }
}
