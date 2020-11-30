import Foundation
import Guaka
import Version
import PromiseKit
import XcodesKit
import LegibleError
import Path

var configuration = Configuration()
try? configuration.load()
let xcodeList = XcodeList()
let installer = XcodeInstaller(configuration: configuration, xcodeList: xcodeList)

migrateApplicationSupportFiles()

// This is awkward, but Guaka wants a root command in order to add subcommands,
// but then seems to want it to behave like a normal command even though it'll only ever print the help.
// But it doesn't even print the help without the user providing the --help flag,
// so we need to tell it to do this explicitly
var app: Command!
app = Command(usage: "xcodes") { _, _ in Current.logging.log(GuakaConfig.helpGenerator.init(command: app).helpMessage) }

func installed() -> Command {
    let installed = Command(usage: "installed",
                            shortMessage: "List the versions of Xcode that are installed") { _, _ in
        installer.printInstalledXcodes()
            .done {
                exit(0)
            }
            .catch { error in
                Current.logging.log(error.legibleLocalizedDescription)
                exit(1)
            }
        
        RunLoop.current.run()
    }
    return installed
}

func select() -> Command {
    let printFlag = Flag(shortName: "p", longName: "print-path", value: false, description: "Print the path of the selected Xcode")
    return Command(usage: "select <version or path>",
                   shortMessage: "Change the selected Xcode",
                   longMessage: "Change the selected Xcode. Run without any arguments to interactively select from a list, or provide an absolute path.",
                   flags: [printFlag],
                   example: """
                                  xcodes select
                                  xcodes select 11.4.0
                                  xcodes select /Applications/Xcode-11.4.0.app
                                  xcodes select -p
                                  """) { flags, args in
        selectXcode(shouldPrint: flags.getBool(name: "print-path") ?? false, pathOrVersion: args.joined(separator: " "))
            .catch { error in
                Current.logging.log(error.legibleLocalizedDescription)
                exit(1)
            }
        
        RunLoop.current.run()
    }
}

func list() -> Command {
    let showDateFlag = Flag(longName: "print-dates", value: false, description: "Print release dates for each version")
    return Command(usage: "list",
                   shortMessage: "List all versions of Xcode that are available to install",
                   flags: [showDateFlag]) { flags, _ in
        firstly { () -> Promise<Void> in
            var shouldPrintDates = false
            if flags.getBool(name: "print-dates") == true {
                shouldPrintDates = true
            }
            if xcodeList.shouldUpdate {
                return installer.updateAndPrint(shouldPrintDates: shouldPrintDates)
            }
            else {
                return installer.printAvailableXcodes(xcodeList.availableXcodes, installed: Current.files.installedXcodes(), shouldPrintDates: shouldPrintDates)
            }
        }
        .done {
            exit(0)
        }
        .catch { error in
            Current.logging.log(error.legibleLocalizedDescription)
            exit(1)
        }
        
        RunLoop.current.run()
    }
}

func update() -> Command {
    let showDateFlag = Flag(longName: "print-dates", value: false, description: "Print release dates for each version")
    return Command(usage: "update",
                   shortMessage: "Update the list of available versions of Xcode",
                   flags: [showDateFlag]) { flags, _ in
        firstly { () -> Promise<Void> in
            var shouldPrintDates = false
            if flags.getBool(name: "print-dates") == true {
                shouldPrintDates = true
            }
            return installer.updateAndPrint(shouldPrintDates: shouldPrintDates)
        }
        .catch { error in
            Current.logging.log(error.legibleLocalizedDescription)
            exit(1)
        }
        
        RunLoop.current.run()
    }
}

func downloadCommand(shouldInstall: Bool) -> Command {
    let pathFlag = Flag(longName: "path", type: String.self, description: "Local path to Xcode .xip")
    let latestFlag = Flag(longName: "latest", value: false, description: "Update and then install the latest non-prerelease version available.")
    let latestPrereleaseFlag = Flag(longName: "latest-prerelease", value: false, description: "Update and then install the latest prerelease version available, including GM seeds and GMs.")
    let aria2 = Flag(longName: "aria2", type: String.self, description: "The path to an aria2 executable. Defaults to /usr/local/bin/aria2c.")
    let noAria2 = Flag(longName: "no-aria2", value: false, description: "Don't use aria2 to download Xcode, even if its available.")
    var flags = [pathFlag, latestFlag, latestPrereleaseFlag, aria2, noAria2]
    if !shouldInstall {
        let listDownloaded = Flag(longName: "list", value: false, description: "List all of the downloaded Xips")
        flags.append(listDownloaded)
    }
    let commandName = shouldInstall ? "install" : "download"
    let commandInstruction = shouldInstall ? "Download and install" : "Download"
    return Command(usage: "\(commandName) <version>",
                   shortMessage: "\(commandInstruction) a specific version of Xcode",
                   longMessage: """
                          \(commandInstruction) a specific version of Xcode

                          By default, xcodes will use a URLSession to download the specified version. If aria2 (https://aria2.github.io, available in Homebrew) is installed, either at /usr/local/bin/aria2c or at the path specified by the --aria2 flag, then it will be used instead. aria2 will use up to 16 connections to download Xcode 3-5x faster. If you have aria2 installed and would prefer to not use it, you can use the --no-aria2 flag.
                          """,
                   flags: flags,
                   example: """
                                   xcodes \(commandName) 10.2.1
                                   xcodes \(commandName) 11 Beta 7
                                   xcodes \(commandName) 11.2 GM seed
                                   xcodes \(commandName) 9.0 --path ~/Archive/Xcode_9.xip
                                   xcodes \(commandName) --latest-prerelease
                                   """) { flags, args in
        let versionString = args.joined(separator: " ")
        let pathFlag = flags.getString(name: "path")
        let searchPath : Path? = (pathFlag != nil) ? Path(pathFlag!) : nil
        let installation: XcodeInstaller.InstallationType
        if flags.getBool(name: "latest") == true {
            installation = .latest
        } else if flags.getBool(name: "latest-prerelease") == true {
            installation = .latestPrerelease
        } else if let path = searchPath {
            installation = .path(versionString, path)
        } else {
            installation = .version(versionString)
        }
        if flags.getBool(name: "list") == true {
            firstly { () -> Promise<[DownloadedXip]> in
                installer.downloadedXips(searchPath: searchPath)
            }
            .done { list in
                Current.logging.log("Available downloaded Xips:\n\(list.compactMap { Version(tolerant: $0.path.basename(dropExtension: true)) })")
                exit(0)
            }
            .catch { error in
                Current.logging.log(error.legibleLocalizedDescription)
                exit(1)
            }
            RunLoop.current.run()
            return
        }
        
        var downloader = XcodeInstaller.Downloader.urlSession(searchPath)
        let aria2Path = flags.getString(name: "aria2").flatMap(Path.init) ?? Path.root.usr.local.bin/"aria2c"
        if aria2Path.exists, flags.getBool(name: "no-aria2") != true {
            downloader = .aria2(aria2Path, searchPath)
        }
        
        installer.install(installation, downloader: downloader, shouldInstall: shouldInstall)
            .catch { error in
                switch error {
                    case Process.PMKError.execution(let process, let standardOutput, let standardError):
                        Current.logging.log("""
                        Failed executing: `\(process)` (\(process.terminationStatus))
                        \([standardOutput, standardError].compactMap { $0 }.joined(separator: "\n"))
                        """)
                    default:
                        Current.logging.log(error.legibleLocalizedDescription)
                }
                
                exit(1)
            }
        
        RunLoop.current.run()
    }
}

func uninstall() -> Command {
    Command(usage: "uninstall <version>",
            shortMessage: "Uninstall a specific version of Xcode",
            example: "xcodes uninstall 10.2.1") { _, args in
        let versionString = args.joined(separator: " ")
        installer.uninstallXcode(versionString)
            .catch { error in
                Current.logging.log(error.legibleLocalizedDescription)
                exit(1)
            }
        RunLoop.current.run()
    }
}

func version() -> Command {
    Command(usage: "version",
            shortMessage: "Print the version number of xcodes itself") { _, _ in
        Current.logging.log(XcodesKit.version.descriptionWithoutBuildMetadata)
        exit(0)
    }
}

func removeXip() -> Command {
    let path = Flag(longName: "path", type: String.self, description: "Search path to locate Xip")
    return Command(usage: "remove <version>",
            shortMessage: "Delete downloaded Xip for a specific version of Xcode",
            flags: [ path ], example: "xcodes remove 10.2.1") { flags, args in
        let versionString = args.joined(separator: " ")
        let pathArgument = flags.getString(name: "path")
        let searchPath = pathArgument != nil ? Path(pathArgument!) : nil
        installer.removeXip(versionString, searchPath: searchPath)
            .done {
                exit(0)
            }
            .catch { error in
                Current.logging.log(error.legibleLocalizedDescription)
                exit(1)
            }
        RunLoop.current.run()
    }
}

func setupCommands() {
    app.add(subCommand: installed())
    app.add(subCommand: select())
    app.add(subCommand: list())
    app.add(subCommand: update())
    app.add(subCommand: downloadCommand(shouldInstall: true))
    app.add(subCommand: downloadCommand(shouldInstall: false))
    app.add(subCommand: version())
    app.add(subCommand: uninstall())
    app.add(subCommand: removeXip())
}

setupCommands()
app.execute()
