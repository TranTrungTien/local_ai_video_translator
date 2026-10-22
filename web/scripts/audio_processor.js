class AudioProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.targetSampleRate = 16000;
  }

  process(inputs, outputs, parameters) {
    const input = inputs[0];
    if (input.length > 0) {
      const channelData = input[0]; // Mono extraction

      // Use the global sampleRate provided by the AudioWorkletGlobalScope
      const sourceSampleRate = sampleRate;
      const ratio = sourceSampleRate / this.targetSampleRate;

      // Calculate resulting length
      const resampledLength = Math.floor(channelData.length / ratio);
      const resampledData = new Int16Array(resampledLength);

      for (let i = 0; i < resampledLength; i++) {
        // Simple decimation/sampling
        const sourceIndex = Math.floor(i * ratio);
        const sample = Math.max(-1, Math.min(1, channelData[sourceIndex]));
        // Convert Float32 to Int16
        resampledData[i] = sample < 0 ? sample * 0x8000 : sample * 0x7FFF;
      }

      // Send the Int16 buffer back to the main thread
      this.port.postMessage(resampledData.buffer, [resampledData.buffer]);
    }
    return true;
  }
}

registerProcessor('audio-processor', AudioProcessor);
