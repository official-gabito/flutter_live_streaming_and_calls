import 'dart:math';

// zego_config.dart

class ZegoConfig {
  // Replace with your appID from ZEGO console
  static const int appID = 868240864; // Replace with your actual AppID

  // Replace with your appSign from ZEGO console
  static const String appSign =
      "1d0aa7ce9b8590baeef169a054fd71ce7431ef8196a3ee39776c0ce8971f270f"; // Replace with your actual AppSign

  // Generate token using your own logic or fetch from your token server
  // For testing purposes, you can return an empty string if token is not required
  static String generateToken(
    String userId, {
    int role = 2,
    bool forceSigned = true,
  }) {
    // TODO: Replace this with your actual token generation or fetching logic
    // Make sure to include role and forceSigned parameters in the generation
    return "";
  }

  // Helper method to generate random ID if needed
  static String getRandomUserID() {
    return Random().nextInt(100000).toString();
  }
}
