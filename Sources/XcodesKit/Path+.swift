import Path

extension Path {
    static let oldXcodesApplicationSupport = Path.applicationSupport/"ca.brandonevans.xcodes"
    static let xcodesApplicationSupport = Path.applicationSupport/"com.xcodeupdates.app.XcodeUpdates"
    static let cacheFile = xcodesApplicationSupport/"available-xcodes.json"
    static let configurationFile = xcodesApplicationSupport/"configuration.json"
}
