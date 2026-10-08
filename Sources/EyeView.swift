import AppKit
import QuartzCore

/// NSView que hospeda o DragonEye e o anima a cada frame do monitor.
final class EyeView: NSView {
    let eye = DragonEye()
    private var link: CADisplayLink?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(eye.root)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        eye.layout(size: bounds.size, scale: window?.backingScaleFactor ?? 2)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        if window != nil {
            let l = displayLink(target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common)
            link = l
            needsLayout = true
        }
    }

    @objc private func tick(_ sender: CADisplayLink) {
        eye.step(now: CACurrentMediaTime())
    }

    func stop() {
        link?.invalidate()
        link = nil
    }
}
