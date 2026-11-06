import AppKit
import SwiftUI
@preconcurrency import VisionKit

/// Shows a screenshot whose text you can select and copy, like Live Text in Preview.
struct LiveTextImage: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> LiveTextImageView {
        LiveTextImageView(image: image)
    }

    func updateNSView(_ view: LiveTextImageView, context: Context) {}
}

final class LiveTextImageView: NSView {
    private let imageView = NSImageView()
    private let overlay = ImageAnalysisOverlayView()
    private var analysisTask: Task<Void, Never>?

    init(image: NSImage) {
        super.init(frame: .zero)
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        overlay.preferredInteractionTypes = .automaticTextOnly
        overlay.trackingImageView = imageView
        for view in [imageView, overlay] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        analysisTask = Task { [overlay] in
            let analyzer = ImageAnalyzer()
            let configuration = ImageAnalyzer.Configuration([.text])
            guard let analysis = try? await analyzer.analyze(image, orientation: .up, configuration: configuration) else { return }
            overlay.analysis = analysis
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { analysisTask?.cancel() }
}
