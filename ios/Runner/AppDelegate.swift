import Flutter
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "ReaderImageExportChannel"
    )
    ReaderImageExportChannel.register(with: registrar.messenger())
  }
}

private final class ReaderImageExportChannel {
  private static let channelName = "com.adws.y300/reader_image_export"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "saveImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let sourcePath = arguments["sourcePath"] as? String,
        let displayName = arguments["displayName"] as? String,
        let mimeType = arguments["mimeType"] as? String,
        !sourcePath.isEmpty,
        !displayName.isEmpty,
        !mimeType.isEmpty
      else {
        result(FlutterError(
          code: "mediaWriteFailed",
          message: "Invalid image export request",
          details: nil
        ))
        return
      }
      saveImage(
        sourcePath: sourcePath,
        displayName: displayName,
        mimeType: mimeType,
        result: result
      )
    }
  }

  private static func saveImage(
    sourcePath: String,
    displayName: String,
    mimeType: String,
    result: @escaping FlutterResult
  ) {
    let supportedTypes: Set<String> = ["image/jpeg", "image/png", "image/gif", "image/webp"]
    guard supportedTypes.contains(mimeType) else {
      result(FlutterError(
        code: "unsupportedFormat",
        message: "Unsupported image format",
        details: nil
      ))
      return
    }
    let sourceURL = URL(fileURLWithPath: sourcePath)
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      result(FlutterError(
        code: "mediaWriteFailed",
        message: "Cached image file is missing",
        details: nil
      ))
      return
    }

    requestAddPermission { status in
      switch status {
      case .authorized:
        persistPhoto(sourceURL: sourceURL, displayName: displayName, result: result)
      case .denied:
        result(FlutterError(
          code: "permissionDenied",
          message: "Photo library add permission was denied",
          details: nil
        ))
      case .restricted:
        result(FlutterError(
          code: "permissionRestricted",
          message: "Photo library access is restricted",
          details: nil
        ))
      case .notDetermined:
        result(FlutterError(
          code: "permissionDenied",
          message: "Photo library permission remains undetermined",
          details: nil
        ))
      @unknown default:
        result(FlutterError(
          code: "permissionRestricted",
          message: "Unknown photo library permission state",
          details: nil
        ))
      }
    }
  }

  private static func requestAddPermission(
    completion: @escaping (PHAuthorizationStatus) -> Void
  ) {
    if #available(iOS 14, *) {
      let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
      guard status == .notDetermined else {
        completion(status)
        return
      }
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { nextStatus in
        DispatchQueue.main.async { completion(nextStatus) }
      }
      return
    }

    let status = PHPhotoLibrary.authorizationStatus()
    guard status == .notDetermined else {
      completion(status)
      return
    }
    PHPhotoLibrary.requestAuthorization { nextStatus in
      DispatchQueue.main.async { completion(nextStatus) }
    }
  }

  private static func persistPhoto(
    sourceURL: URL,
    displayName: String,
    result: @escaping FlutterResult
  ) {
    var localIdentifier: String?
    PHPhotoLibrary.shared().performChanges({
      let request = PHAssetCreationRequest.forAsset()
      let options = PHAssetResourceCreationOptions()
      options.originalFilename = displayName
      request.addResource(with: .photo, fileURL: sourceURL, options: options)
      localIdentifier = request.placeholderForCreatedAsset?.localIdentifier
    }) { success, error in
      DispatchQueue.main.async {
        guard success, let identifier = localIdentifier, !identifier.isEmpty else {
          result(FlutterError(
            code: "mediaWriteFailed",
            message: error?.localizedDescription ?? "PhotoKit failed to save image",
            details: nil
          ))
          return
        }
        result([
          "locator": identifier,
          "displayLocation": "系统照片",
        ])
      }
    }
  }
}
