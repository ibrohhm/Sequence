import Foundation
import CoreServices

/// Calls `onChange` (coalesced, on the main queue) when anything under `root` changes.
public final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let box: CallbackBox

    private final class CallbackBox {
        var onChange: (() -> Void)?
        init(_ onChange: @escaping () -> Void) { self.onChange = onChange }
    }

    public init(root: URL, onChange: @escaping () -> Void) {
        box = CallbackBox(onChange)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(box).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue().onChange?()
        }
        stream = FSEventStreamCreate(nil, callback, &context, [root.path] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    public func stop() {
        box.onChange = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
