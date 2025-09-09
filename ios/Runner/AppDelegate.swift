import UIKit
import Flutter
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Read API key from Info.plist (key: "GMSApiKey")
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !apiKey.isEmpty {
      GMSServices.provideAPIKey(apiKey)
    } else {
      // Optional fallback (not recommended for prod):
      // GMSServices.provideAPIKey("AIzaSyD9vAj4KGmzoDKSSAKxapB4SVZc_Wf-WFI")
      print("⚠️ Missing 'GMSApiKey' in Info.plist. Google Maps will not initialize.")
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
