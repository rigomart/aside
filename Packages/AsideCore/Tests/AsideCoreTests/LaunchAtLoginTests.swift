import Foundation
import Testing
@testable import AsideCore

struct LaunchAtLoginTests {
    let installed = URL(fileURLWithPath: "/Applications/Aside.app")

    @Test func installedCopyTurnsItOnTheFirstTime() {
        #expect(LaunchAtLogin.isInstalled(installed))
        #expect(LaunchAtLogin.turnsOnByItself(app: installed, alreadySet: false))
        #expect(!LaunchAtLogin.turnsOnByItself(app: installed, alreadySet: true))
    }

    @Test func copiesOutsideApplicationsNeverHaveIt() {
        let built = URL(fileURLWithPath: "/Users/me/aside/build/DerivedData/Build/Products/Debug/Aside.app")
        let nested = URL(fileURLWithPath: "/Applications/Tools/Aside.app")
        for app in [built, nested] {
            #expect(!LaunchAtLogin.isInstalled(app))
            #expect(!LaunchAtLogin.turnsOnByItself(app: app, alreadySet: false))
        }
    }
}
