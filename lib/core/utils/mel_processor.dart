import 'dart:math' as math;
import 'dart:typed_data';

class MelProcessor {
  static const int sampleRate = 16000;
  static const int nFft = 512; // Padded to power of 2 for FFT
  static const int winLength = 400; // Original Whisper window length
  static const int hopLength = 160;
  static const int nMels = 80;
  static const int nFrames = 3000;

  static final Float32List _hannWindow = _createHannWindow(winLength);
  static final List<Float32List> _melFilters = _createMelFilters(
    nMels,
    nFft,
    sampleRate,
    0.0,
    8000.0,
  );

  /// Computes Log-Mel Spectrogram for Whisper from 16kHz PCM data.
  /// Result is a flattened Float32List of shape [nMels, nFrames].
  static Float32List computeLogMel(Int16List pcm) {
    // 1. Pad or truncate PCM to 30 seconds (480,000 samples)
    final samples = Float32List(sampleRate * 30);
    for (int i = 0; i < math.min(pcm.length, samples.length); i++) {
      samples[i] = pcm[i] / 32768.0;
    }

    final output = Float32List(nMels * nFrames);

    // 2. STT + Mel Filterbank
    for (int i = 0; i < nFrames; i++) {
      final start = i * hopLength;
      final fftInput = Float32List(nFft); // Zero-padded to 512

      // Apply Hann window to 400 samples
      for (int j = 0; j < winLength; j++) {
        if (start + j < samples.length) {
          fftInput[j] = samples[start + j] * _hannWindow[j];
        }
      }

      // Compute Power Spectrogram using FFT
      final spectrum = _computePowerSpectrum(fftInput);

      // Apply Mel Filters
      for (int m = 0; m < nMels; m++) {
        double melEnergy = 0.0;
        for (int j = 0; j < spectrum.length; j++) {
          melEnergy += spectrum[j] * _melFilters[m][j];
        }

        // Log10-Mel (Whisper standard)
        final logMel = math.log(math.max(melEnergy, 1e-10)) / math.ln10;
        output[m * nFrames + i] = logMel;
      }
    }

    // Whisper normalization: scale to [-1, 1] based on max value in the batch
    double maxVal = -100.0;
    for (int i = 0; i < output.length; i++) {
      if (output[i] > maxVal) maxVal = output[i];
    }

    final floor = maxVal - 8.0;
    for (int i = 0; i < output.length; i++) {
      final val = math.max(output[i], floor);
      output[i] = (val + 4.0) / 4.0;
    }

    return output;
  }

  static Float32List _createHannWindow(int n) {
    final w = Float32List(n);
    for (int i = 0; i < n; i++) {
      w[i] = 0.5 * (1 - math.cos(2 * math.pi * i / (n - 1)));
    }
    return w;
  }

  static List<Float32List> _createMelFilters(
    int nFilters,
    int nFft,
    int sampleRate,
    double lowFreq,
    double highFreq,
  ) {
    final nBins = nFft ~/ 2 + 1;
    final filters = List.generate(nFilters, (_) => Float32List(nBins));

    double hzToMel(double hz) => 2595 * math.log(1 + hz / 700) / math.log(10);
    double melToHz(double mel) => 700 * (math.pow(10, mel / 2595) - 1);

    final minMel = hzToMel(lowFreq);
    final maxMel = hzToMel(highFreq);
    final melPoints = List.generate(nFilters + 2, (i) => melToHz(minMel + i * (maxMel - minMel) / (nFilters + 1)));
    final binPoints = melPoints.map((hz) => (hz * nFft / sampleRate).floor()).toList();

    for (int i = 0; i < nFilters; i++) {
      for (int j = binPoints[i]; j < binPoints[i + 1] && j < nBins; j++) {
        filters[i][j] = (j - binPoints[i]) / (binPoints[i + 1] - binPoints[i]);
      }
      for (int j = binPoints[i + 1]; j < binPoints[i + 2] && j < nBins; j++) {
        filters[i][j] = (binPoints[i + 2] - j) / (binPoints[i + 2] - binPoints[i + 1]);
      }
    }

    return filters;
  }

  static Float32List _computePowerSpectrum(Float32List window) {
    final n = window.length; // Expected to be 512
    final real = Float64List.fromList(window.map((e) => e.toDouble()).toList());
    final imag = Float64List(n);

    _fft(real, imag);

    final half = n ~/ 2 + 1;
    final spectrum = Float32List(half);
    for (int k = 0; k < half; k++) {
      spectrum[k] = ((real[k] * real[k] + imag[k] * imag[k]) / n).toDouble();
    }
    return spectrum;
  }

  // Simple Cooley-Tukey Radix-2 FFT
  static void _fft(Float64List real, Float64List imag) {
    final n = real.length;
    if (n <= 1) return;

    // Bit-reversal permutation
    int j = 0;
    for (int i = 0; i < n; i++) {
      if (i < j) {
        final tempReal = real[i];
        real[i] = real[j];
        real[j] = tempReal;
        final tempImag = imag[i];
        imag[i] = imag[j];
        imag[j] = tempImag;
      }
      int m = n >> 1;
      while (m >= 1 && j >= m) {
        j -= m;
        m >>= 1;
      }
      j += m;
    }

    // Butterfly computations
    for (int len = 2; len <= n; len <<= 1) {
      final ang = 2 * math.pi / len;
      final wlenReal = math.cos(ang);
      final wlenImag = -math.sin(ang);
      for (int i = 0; i < n; i += len) {
        double wReal = 1;
        double wImag = 0;
        for (int k = 0; k < len / 2; k++) {
          final uReal = real[i + k];
          final uImag = imag[i + k];
          final vReal = real[i + k + len ~/ 2] * wReal - imag[i + k + len ~/ 2] * wImag;
          final vImag = real[i + k + len ~/ 2] * wImag + imag[i + k + len ~/ 2] * wReal;
          real[i + k] = uReal + vReal;
          imag[i + k] = uImag + vImag;
          real[i + k + len ~/ 2] = uReal - vReal;
          imag[i + k + len ~/ 2] = uImag - vImag;
          final nextWReal = wReal * wlenReal - wImag * wlenImag;
          wImag = wReal * wlenImag + wImag * wlenReal;
          wReal = nextWReal;
        }
      }
    }
  }
}
