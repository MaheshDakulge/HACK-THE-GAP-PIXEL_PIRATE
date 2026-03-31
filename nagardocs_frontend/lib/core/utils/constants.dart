class AppConstants {
  static const String appName = 'Nagardocs AI';

  // You are using ADB USB Port Forwarding!
  // This means your phone forwards 127.0.0.1 straight over the USB cable to your laptop.
  // We no longer need to worry about Wi-Fi IP Addresses!
  static String get apiBaseUrl => 'http://127.0.0.1:8000';
}
