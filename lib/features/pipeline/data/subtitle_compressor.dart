class SubtitleCompressor {
  const SubtitleCompressor({this.maxLineLength = 45});

  final int maxLineLength;

  /// Architecture hook for compressing long translated subtitle lines for optimal mobile readability.
  String compress(String text) {
    if (text.length <= maxLineLength) return text;

    // Word wrap / natural break insertion
    final words = text.split(' ');
    final buffer = StringBuffer();
    var currentLineLength = 0;

    for (final word in words) {
      if (currentLineLength + word.length + 1 > maxLineLength) {
        buffer.write('\n');
        currentLineLength = 0;
      } else if (buffer.isNotEmpty) {
        buffer.write(' ');
        currentLineLength++;
      }
      buffer.write(word);
      currentLineLength += word.length;
    }

    return buffer.toString();
  }
}
