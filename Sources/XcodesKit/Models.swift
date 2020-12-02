import Foundation
import Path
import Version

public struct DownloadedXip : Equatable {
    
    public var path: Path
    /// Composed of the bundle short version from Info.plist and the product build version from version.plist
    public var version: Version
    
    init(path: Path, version: Version) {
        self.path = path
        self.version = version
    }
    
    init?(path: Path) {
        self.path = path
        var name = path.basename(dropExtension: false)
        name = name.replacingOccurrences(of: ".xip", with: "")
        name = name.replacingOccurrences(of: ".aria2", with: "")
        let version = name.replacingOccurrences(of: "Xcode-", with: "")
        guard let filenameVersion = Version(tolerant: version) else {
            print("unable to create version from: \(name)")
            return nil
        }
        self.version = filenameVersion
    }
    
}

struct XcodesProgress {
    var currentSize : String = ""
    var totalSize : String = ""
    var downloadSpeed : String = ""
    var estimatedTime : String = ""
    var percent : Int64
    
    // NSProgress-related properties
    var throughput: Int?
    var fileTotalCount: Int?
    var fileCompletedCount: Int?
    var estimatedTimeRemaining : TimeInterval = .init(0)
    
    init?(string: String) {
        guard let percentMatch = string.percentMatch(regex: #"((?<percent>\d+)%\))"#) else {
            return nil
        }
        self.percent = Int64(string[percentMatch]) ?? 0
        guard let sizeMatches = string.matches(regex: #"((\d+.\d+|\d+)(MiB|GiB))"#) else {
            return nil
        }
        
        var keys = [ \Self.downloadSpeed, \Self.totalSize, \Self.currentSize ]
        for match in sizeMatches.reversed() {
            if keys.isEmpty {
                break
            }
            let value = string.string(from: match.range)
            let dropped = keys.remove(at: 0)
            self[keyPath: dropped] = value ?? ""
        }
        
        guard let etaMatch = string.firstMatch(regex: #"(\d+(m|h|s)\d+(m|h|s))"#) else {
            return nil
        }
        let etaValue = string.string(from: etaMatch.range)
        self.estimatedTime = etaValue ?? ""
        self.setupValues()
    }
    
    mutating func setupValues() {
        self.setupFileCount()
        self.setupThroughput()
        self.setupEstimatedTimeValue()
    }
    
    mutating func bytes(_ keyPath: KeyPath<Self, String>) -> Int {
        let kilobytes = self[keyPath: keyPath].value(regex: #"(?<kilobytes>(\d+.\d+|\d+))KiB"#, template: "kilobytes") ?? 0.0
        let megabytes = self[keyPath: keyPath].value(regex: #"(?<megabytes>(\d+.\d+|\d+))MiB"#, template: "megabytes") ?? 0.0
        let gigabytes = self[keyPath: keyPath].value(regex: #"(?<gigabytes>(\d+.\d+|\d+))GiB"#, template: "gigabytes") ?? 0.0
        let finalKilobytes = 1_000 * abs(floorf(kilobytes))
        let finalMegabytes = 1_000_000 * abs(floorf(megabytes))
        let finalGigabytes = 1_000_000_000 * abs(floorf(gigabytes))
        return Int(finalKilobytes + finalMegabytes + finalGigabytes)
    }
    
    mutating func setupThroughput() {
        self.throughput = self.bytes(\.downloadSpeed)
    }
    
    mutating func setupEstimatedTimeValue() {
        guard let hours = self.estimatedTime.value(regex: #"(?<hours>\d+)m"#, template: "hours"),
        let minutes = self.estimatedTime.value(regex: #"(?<minutes>\d+)m"#, template: "minutes"),
        let seconds = self.estimatedTime.value(regex: #"(?<seconds>\d+)m"#, template: "seconds")
        else {
            return
        }
        let finalHours = hours * 60 * 60
        let finalMinutes = minutes * 60
        self.estimatedTimeRemaining = TimeInterval(finalHours + finalMinutes + seconds)
    }
    
    mutating func setupFileCount() {
        self.fileCompletedCount = self.bytes(\.currentSize)
        self.fileTotalCount = self.bytes(\.totalSize)
    }
    
}

public struct InstalledXcode: Equatable {
    
    public var path: Path
    /// Composed of the bundle short version from Info.plist and the product build version from version.plist
    public var version: Version
    
    init(path: Path, version: Version) {
        self.path = path
        self.version = version
    }
 
    public init?(path: Path) {
        self.path = path

        let infoPlistPath = path.join("Contents").join("Info.plist")
        let versionPlistPath = path.join("Contents").join("version.plist")
        guard 
            let infoPlistData = Current.files.contents(atPath: infoPlistPath.string),
            let infoPlist = try? PropertyListDecoder().decode(InfoPlist.self, from: infoPlistData),
            let bundleShortVersion = infoPlist.bundleShortVersion,
            let bundleVersion = Version(tolerant: bundleShortVersion),

            let versionPlistData = Current.files.contents(atPath: versionPlistPath.string),
            let versionPlist = try? PropertyListDecoder().decode(VersionPlist.self, from: versionPlistData)
        else { return nil }

        // Installed betas don't include the beta number anywhere, so try to parse it from the filename or fall back to simply "beta"
        var prereleaseIdentifiers = bundleVersion.prereleaseIdentifiers
        if let filenameVersion = Version(path.basename(dropExtension: true).replacingOccurrences(of: "Xcode-", with: "")) {
            prereleaseIdentifiers = filenameVersion.prereleaseIdentifiers
        }
        else if infoPlist.bundleIconName == "XcodeBeta", !prereleaseIdentifiers.contains("beta") {
            prereleaseIdentifiers = ["beta"]
        }

        self.version = Version(major: bundleVersion.major,
                               minor: bundleVersion.minor,
                               patch: bundleVersion.patch,
                               prereleaseIdentifiers: prereleaseIdentifiers,
                               buildMetadataIdentifiers: [versionPlist.productBuildVersion].compactMap { $0 })
    }
}

public struct Xcode: Codable, Equatable {
    public let version: Version
    public let url: URL
    public let filename: String
    public let releaseDate: Date?

    public init(version: Version, url: URL, filename: String, releaseDate: Date?) {
        self.version =  version
        self.url = url
        self.filename = filename
        self.releaseDate = releaseDate
    }
}

struct Downloads: Codable {
    let downloads: [Download]
}

public struct Download: Codable {
    public let name: String
    public let files: [File]
    public let dateModified: Date

    public struct File: Codable {
        public let remotePath: String
    }
}

public struct InfoPlist: Decodable {
    public let bundleID: String?
    public let bundleShortVersion: String?
    public let bundleIconName: String?

    public enum CodingKeys: String, CodingKey {
        case bundleID = "CFBundleIdentifier"
        case bundleShortVersion = "CFBundleShortVersionString"
        case bundleIconName = "CFBundleIconName"
    }
}

public struct VersionPlist: Decodable {
    public let productBuildVersion: String

    public enum CodingKeys: String, CodingKey {
        case productBuildVersion = "ProductBuildVersion"
    }
}

