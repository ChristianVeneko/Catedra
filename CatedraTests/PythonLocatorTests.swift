import Testing
@testable import Catedra

struct PythonLocatorTests {
    @Test func dropsUsrBinShimsWithoutCommandLineTools() {
        let paths = ["/opt/homebrew/bin/python3", "/usr/bin/python3", "/usr/local/bin/python3"]
        #expect(PythonLocator.executableCandidates(paths, commandLineToolsInstalled: false)
                == ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"])
    }

    @Test func keepsShimsWhenCommandLineToolsAreInstalled() {
        let paths = ["/usr/bin/python3", "/usr/bin/python3", "/opt/homebrew/bin/python3"]
        #expect(PythonLocator.executableCandidates(paths, commandLineToolsInstalled: true)
                == ["/usr/bin/python3", "/opt/homebrew/bin/python3"])
    }
}
