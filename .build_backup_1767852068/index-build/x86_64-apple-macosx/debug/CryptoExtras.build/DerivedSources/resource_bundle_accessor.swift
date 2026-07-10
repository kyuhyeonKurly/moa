import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("swift-crypto_CryptoExtras.bundle").path
        let buildPath = "/Users/g30x74w9xy/Documents/Company/Tool/Projects/moa/.build/index-build/x86_64-apple-macosx/debug/swift-crypto_CryptoExtras.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}