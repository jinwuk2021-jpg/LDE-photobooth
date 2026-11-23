import Flutter
import Photos

/// PhotoKit wrapper. The app only asks for add-only access. A named album can
/// only be created/looked up with read-write access, so files go into the
/// "Lensly" album when the user has granted that (via
/// `requestAlbumAccess`, offered in Settings), and into the camera roll
/// otherwise.
enum LibrarySaver {
  static func name(_ s: PHAuthorizationStatus) -> String {
    switch s {
    case .authorized: return "granted"
    case .limited: return "limited"
    default: return "denied"
    }
  }

  static func access(request: Bool, result: @escaping FlutterResult) {
    let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    if status == .notDetermined && request {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { s in
        DispatchQueue.main.async { result(name(s)) }
      }
    } else {
      result(status == .notDetermined ? "denied" : name(status))
    }
  }

  static func requestAlbumAccess(result: @escaping FlutterResult) {
    PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
      DispatchQueue.main.async { result(name(s)) }
    }
  }

  private static func album(named title: String) -> PHAssetCollection? {
    let opts = PHFetchOptions()
    opts.predicate = NSPredicate(format: "title = %@", title)
    return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: opts).firstObject
  }

  static func save(path: String, isVideo: Bool, album title: String, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    let canUseAlbum = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
    let existing = canUseAlbum ? album(named: title) : nil
    PHPhotoLibrary.shared().performChanges({
      let req =
        isVideo
        ? PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        : PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
      guard canUseAlbum, let placeholder = req?.placeholderForCreatedAsset else { return }
      let albumReq =
        existing.flatMap { PHAssetCollectionChangeRequest(for: $0) }
        ?? PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
      albumReq.addAssets([placeholder] as NSArray)
    }) { ok, _ in
      DispatchQueue.main.async { result(ok) }
    }
  }
}
