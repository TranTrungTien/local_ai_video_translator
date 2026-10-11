abstract final class AppConstants {
  static const targetLanguage = 'vi';
  static const maxIframeDepth = 4;
  static const initialSubtitleBuffer = Duration(seconds: 45);
  static const targetSubtitleLookahead = Duration(minutes: 2);
  static const dangerBuffer = Duration(seconds: 5);
  static const networkTimeout = Duration(seconds: 12);
  static const defaultUserAgent = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36';

  // Độ trễ ban đầu để AI có thời gian dịch (tăng lên 7s cho ổn định)
  static const initialSubtitleBuffer = Duration(seconds: 7);

  // AI sẽ cố gắng dịch trước 1 phút video
  static const targetSubtitleLookahead = Duration(minutes: 1);

  // Nếu buffer còn dưới 3s, video sẽ tạm dừng để đợi AI dịch tiếp
  static const dangerBuffer = Duration(seconds: 3);

  static const networkTimeout = Duration(seconds: 15);
}
