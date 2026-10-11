abstract final class AppConstants {
  static const targetLanguage = 'vi';
  static const maxIframeDepth = 4;
  
  // Độ trễ ban đầu để AI có thời gian dịch (tăng lên 7s cho ổn định)
  static const initialSubtitleBuffer = Duration(seconds: 7);
  
  // AI sẽ cố gắng dịch trước 1 phút video
  static const targetSubtitleLookahead = Duration(minutes: 1);
  
  // Nếu buffer còn dưới 3s, video sẽ tạm dừng để đợi AI dịch tiếp
  static const dangerBuffer = Duration(seconds: 3);
  
  static const networkTimeout = Duration(seconds: 15);
}
