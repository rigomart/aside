import AppKit
import XCTest

/// Base class for Aside's UI tests. Launches the Verify build (`com.rigomart.aside.verify`, "Aside Verify")
/// with its own hotkey, and attaches the evidence that `scripts/verify run` exports.
class VerifyTestCase: XCTestCase {
    /// The Verify build's hotkey: Control-Option-Shift-Space. The owner's copy holds Control-Option-Space,
    /// and Carbon hotkeys are not exclusive, so sharing it would open both panels on one press.
    static let hotkey: (key: String, modifiers: XCUIElement.KeyModifierFlags) = (" ", [.control, .option, .shift])

    /// The same shortcut as KeyboardShortcuts stores it. A launch argument puts it in the argument domain,
    /// which wins over the stored default; the outer quotes keep it a string rather than a plist.
    private static let hotkeyDefault = #""{\"carbonModifiers\":6656,\"carbonKeyCode\":49}""#

    /// Text unique to this test, for anything the test types or creates.
    let stamp = String(UUID().uuidString.prefix(6))

    /// Apps this test launched, so a failure can attach their trees. Only touched on the main thread,
    /// where XCTest runs UI tests and records their failures.
    nonisolated(unsafe) private var launched: [XCUIApplication] = []

    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches the Verify build with the verification hotkey. Pass launch arguments to arrange a precondition.
    @MainActor func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-KeyboardShortcuts_togglePanel", Self.hotkeyDefault]
            + arguments
        app.launch()
        launched.append(app)
        addTeardownBlock { @MainActor in app.terminate() }
        return app
    }

    /// Attaches a picture of `element` (usually `app.panel`) and `margin` points around it, named `label`.
    /// XCUITest can't screenshot the panel itself ("Image creation failed"), so this crops a screenshot
    /// of the display the element is on. That also keeps the rest of the owner's screen out of evidence.
    @MainActor func shot(_ label: String, of element: XCUIElement, margin: CGFloat = 24) {
        shot(label, region: element.frame, margin: margin)
    }

    /// Attaches a picture of `frame` on screen. To show that the panel closed, keep `app.panel.frame`
    /// while it is open and shoot that region after.
    @MainActor func shot(_ label: String, region frame: CGRect, margin: CGFloat = 24) {
        // Element frames have their origin at the top left of the main display, y down; NSScreen's at
        // the bottom left, y up. XCUIScreen.screens lists displays in NSScreen.screens order.
        let mainHeight = NSScreen.screens[0].frame.height
        let center = NSPoint(x: frame.midX, y: mainHeight - frame.midY)
        guard let index = NSScreen.screens.firstIndex(where: { $0.frame.contains(center) }),
              let image = XCUIScreen.screens[index].screenshot().image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return XCTFail("\(label): no display shows \(frame)") }
        let display = NSScreen.screens[index].frame
        let scale = CGFloat(image.width) / display.width
        XCTAssertEqual(CGFloat(image.height) / scale, display.height, accuracy: 1, "\(label): displays are not in NSScreen order")
        let crop = CGRect(
            x: (frame.minX - display.minX - margin) * scale,
            y: (frame.minY - (mainHeight - display.maxY) - margin) * scale,
            width: (frame.width + 2 * margin) * scale,
            height: (frame.height + 2 * margin) * scale
        ).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let cropped = image.cropping(to: crop),
              let png = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])
        else { return XCTFail("\(label): could not crop \(crop) from display \(index + 1)") }
        keep(XCTAttachment(data: png, uniformTypeIdentifier: "public.png"), named: label)
    }

    /// Attaches a screenshot of every display. Use it when the change is about where the panel sits
    /// relative to other apps. The panel opens on the display the pointer is on.
    @MainActor func shotScreens(_ label: String) {
        for (index, screen) in XCUIScreen.screens.enumerated() {
            keep(XCTAttachment(screenshot: screen.screenshot()), named: "\(label)-display\(index + 1)")
        }
    }

    /// Attaches the accessibility tree of `app`: roles, labels, identifiers and values.
    @MainActor func tree(_ app: XCUIApplication, _ label: String = "tree") {
        keep(XCTAttachment(string: app.debugDescription), named: label)
    }

    /// Every failure gets a picture of each display and the tree of each app this test launched.
    /// Xcode adds a tree on its own only when an element query fails.
    override func record(_ issue: XCTIssue) {
        let apps = launched
        let (screenshots, trees) = MainActor.assumeIsolated {
            (XCUIScreen.screens.map { $0.screenshot() }, apps.map(\.debugDescription))
        }
        var issue = issue
        for (index, screenshot) in screenshots.enumerated() {
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "failure-display\(index + 1)"
            issue.add(attachment)
        }
        for (index, tree) in trees.enumerated() {
            let attachment = XCTAttachment(string: tree)
            attachment.name = "failure-tree\(index + 1)"
            issue.add(attachment)
        }
        super.record(issue)
    }

    private func keep(_ attachment: XCTAttachment, named name: String) {
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
