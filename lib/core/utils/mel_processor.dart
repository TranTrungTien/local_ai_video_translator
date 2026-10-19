import 'dart:math' as math;
import 'dart:typed_data';

/// Whisper-compatible log-Mel preprocessing.
///
/// Contract follows OpenAI Whisper: 16 kHz mono PCM, 30 s window,
/// N_FFT=400, hop=160, 80 Slaney mel bins and [80, 3000] output.
class MelProcessor {
  static const int sampleRate = 16000;
  static const int nFft = 400;
  static const int hopLength = 160;
  static const int nMels = 80;
  static const int nFrames = 3000;
  static const int nSamples = sampleRate * 30;
  static const int _freqBins = nFft ~/ 2 + 1;

  static final Float64List _window = _periodicHann(nFft);
  static final List<Float64List> _melFilters = _createSlaneyFilters();

  static Float32List computeLogMel(Int16List pcm) {
    final samples = Float64List(nSamples);
    final limit = math.min(pcm.length, nSamples);
    for (var i = 0; i < limit; i++) {
      samples[i] = pcm[i] / 32768.0;
    }

    // torch.stft(center=true) pads N_FFT/2 on both sides. Whisper then drops
    // the final time frame (magnitudes[..., :-1]), leaving exactly 3000.
    final centered = _reflectPad(samples, nFft ~/ 2);
    final out = Float32List(nMels * nFrames);
    final frame = Float64List(nFft);
    var maxLog = -double.infinity;

    for (var t = 0; t < nFrames; t++) {
      final start = t * hopLength;
      for (var i = 0; i < nFft; i++) {
        frame[i] = centered[start + i] * _window[i];
      }
      final power = _dftPower(frame);
      for (var m = 0; m < nMels; m++) {
        var energy = 0.0;
        final filter = _melFilters[m];
        for (var k = 0; k < _freqBins; k++) {
          energy += filter[k] * power[k];
        }
        final value = math.log(math.max(energy, 1e-10)) / math.ln10;
        out[m * nFrames + t] = value;
        if (value > maxLog) maxLog = value;
      }
    }

    final floor = maxLog - 8.0;
    for (var i = 0; i < out.length; i++) {
      out[i] = (math.max(out[i], floor) + 4.0) / 4.0;
    }
    return out;
  }

  static Float64List _reflectPad(Float64List input, int pad) {
    final out = Float64List(input.length + pad * 2);
    out.setRange(pad, pad + input.length, input);
    for (var i = 0; i < pad; i++) {
      out[pad - 1 - i] = input[math.min(i + 1, input.length - 1)];
      out[pad + input.length + i] =
          input[math.max(0, input.length - 2 - i)];
    }
    return out;
  }

  static Float64List _periodicHann(int length) {
    final w = Float64List(length);
    for (var i = 0; i < length; i++) {
      w[i] = 0.5 - 0.5 * math.cos(2.0 * math.pi * i / length);
    }
    return w;
  }

  /// Exact 400-point real DFT. This deliberately avoids zero-padding to 512:
  /// Whisper's model/filter bank is defined for N_FFT=400.
  static Float64List _dftPower(Float64List frame) {
    final power = Float64List(_freqBins);
    for (var k = 0; k < _freqBins; k++) {
      var re = 0.0;
      var im = 0.0;
      final step = -2.0 * math.pi * k / nFft;
      for (var n = 0; n < nFft; n++) {
        final angle = step * n;
        final x = frame[n];
        re += x * math.cos(angle);
        im += x * math.sin(angle);
      }
      power[k] = re * re + im * im;
    }
    return power;
  }

  /// librosa-style Slaney mel filter bank used by OpenAI Whisper.
  static List<Float64List> _createSlaneyFilters() {
    double hzToMel(double hz) {
      const fSp = 200.0 / 3.0;
      var mel = hz / fSp;
      if (hz >= 1000.0) {
        const minLogHz = 1000.0;
        final minLogMel = minLogHz / fSp;
        final logStep = math.log(6.4) / 27.0;
        mel = minLogMel + math.log(hz / minLogHz) / logStep;
      }
      return mel;
    }

    double melToHz(double mel) {
      const fSp = 200.0 / 3.0;
      var hz = fSp * mel;
      const minLogHz = 1000.0;
      final minLogMel = minLogHz / fSp;
      if (mel >= minLogMel) {
        final logStep = math.log(6.4) / 27.0;
        hz = minLogHz * math.exp(logStep * (mel - minLogMel));
      }
      return hz;
    }

    final minMel = hzToMel(0.0);
    final maxMel = hzToMel(sampleRate / 2.0);
    final melPoints = List<double>.generate(
      nMels + 2,
      (i) => minMel + (maxMel - minMel) * i / (nMels + 1),
    );
    final hzPoints = melPoints.map(melToHz).toList(growable: false);
    final fftFreqs = List<double>.generate(
      _freqBins,
      (i) => i * sampleRate / nFft,
    );

    return List<Float64List>.generate(nMels, (m) {
      final lower = hzPoints[m];
      final center = hzPoints[m + 1];
      final upper = hzPoints[m + 2];
      final enorm = 2.0 / (upper - lower); // norm='slaney'
      final filter = Float64List(_freqBins);
      for (var k = 0; k < _freqBins; k++) {
        final f = fftFreqs[k];
        final up = (f - lower) / (center - lower);
        final down = (upper - f) / (upper - center);
        filter[k] = math.max(0.0, math.min(up, down)) * enorm;
      }
      return filter;
    });
  }
}
