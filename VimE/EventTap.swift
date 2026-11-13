import AppKit
import VimECore

/// Session-wide key-down tap. The handler returns true to swallow the key.
/// Runs on the main run loop, so the handler must stay fast: macOS disables slow taps.
final class EventTap {
    typealias Handler = (KeyInput) -> Bool

    private let handler: Handler
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: eventTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    /// Removes the tap, e.g. when Accessibility permission goes away: a tap left behind after that
    /// can stall keyboard input.
    func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let input = KeyInput(
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            characters: NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? "",
            command: flags.contains(.maskCommand),
            option: flags.contains(.maskAlternate),
            control: flags.contains(.maskControl),
            shift: flags.contains(.maskShift),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        return handler(input) ? nil : Unmanaged.passUnretained(event)
    }
}

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}
