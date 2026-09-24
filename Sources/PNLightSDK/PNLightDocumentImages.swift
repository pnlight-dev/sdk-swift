import Foundation
import UIKit
import DivKit
import PNLight
import VGSL

/// Keeps document-file behavior behind the schema that introduced it. The
/// renderer reuses one DivKit component graph, so the image-holder decision
/// must be made for each document instead of when the renderer is created.
final class PNLightDocumentImagePolicy {
    // Kept local because this source package compiles against the currently
    // shipped binary, which does not expose the schema-v7 constant yet.
    static let requiredSchemaVersion = 7

    private let lock = NSLock()
    private var storedSchemaVersion = 1

    var schemaVersion: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedSchemaVersion
        }
        set {
            lock.lock()
            storedSchemaVersion = newValue
            lock.unlock()
        }
    }

    var isEnabled: Bool {
        schemaVersion >= Self.requiredSchemaVersion
    }
}

/// DivKit reads pictures through this factory. A picture the SDK decoded into
/// memory (`PNLightDocumentImages` in PNLight, filled when a config is
/// fetched) is answered at once, so the first layout pass draws it; anything
/// else loads over the network as DivKit does by itself.
enum PNLightDocumentImageHolders {
    @MainActor
    static func makeImageHolderFactory(
        policy: PNLightDocumentImagePolicy
    ) -> ImageHolderFactory {
        let network = ImageHolderFactory(
            localImageProvider: nil,
            requestPerformer: URLRequestPerformer(urlTransform: nil)
        )
        return ImageHolderFactory { url, placeholder in
            if policy.isEnabled,
               let url,
               let image = PNLightDocumentImages.image(for: url) {
                return image
            }
            return network.make(url, placeholder)
        }
    }
}
