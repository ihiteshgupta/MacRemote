import SwiftUI

struct ScreenCanvasView: View {
    @ObservedObject var frameBuffer: FrameBuffer
    let inputMode: InputMode
    let displayMode: DisplayMode
    var onMouseEvent: (MouseEvent) -> Void
    var onKeyEvent: (KeyEvent) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero

    // Trackpad mode state
    @State private var cursorPosition: CGPoint = .zero
    @State private var lastTrackpadLocation: CGPoint?

    // Display cropping for multi-monitor support
    private var displayWidth: Int {
        switch displayMode {
        case .all: return frameBuffer.width
        case .primary, .secondary: return frameBuffer.width / 2
        }
    }

    private var displayHeight: Int {
        return frameBuffer.height
    }

    private var displayOffsetX: Int {
        switch displayMode {
        case .all, .primary: return 0
        case .secondary: return frameBuffer.width / 2
        }
    }

    private var croppedImage: UIImage? {
        guard let image = frameBuffer.image else { return nil }

        // If showing all displays, return full image
        if displayMode == .all {
            return image
        }

        // Crop to the selected display
        guard let cgImage = image.cgImage else { return nil }

        let cropRect = CGRect(
            x: displayOffsetX,
            y: 0,
            width: displayWidth,
            height: displayHeight
        )

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedCGImage)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = croppedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)

                    // Show cursor in trackpad mode
                    if inputMode == .trackpad {
                        cursorOverlay(in: geometry)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(combinedGesture(in: geometry))
            .onAppear {
                // Center cursor initially
                cursorPosition = CGPoint(
                    x: CGFloat(displayWidth) / 2,
                    y: CGFloat(displayHeight) / 2
                )
            }
        }
    }

    private func cursorOverlay(in geometry: GeometryProxy) -> some View {
        let screenPoint = remoteToScreen(cursorPosition, in: geometry)
        return Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .shadow(color: .black, radius: 2)
            .position(screenPoint)
    }

    private func combinedGesture(in geometry: GeometryProxy) -> some Gesture {
        SimultaneousGesture(
            magnificationGesture,
            dragGesture(in: geometry)
        )
        .simultaneously(with: tapGestures(in: geometry))
    }

    // MARK: - Magnification (Pinch to Zoom)

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = lastScale * value
            }
            .onEnded { value in
                lastScale = scale
                // Clamp scale
                scale = min(max(scale, 0.5), 4.0)
                lastScale = scale
            }
    }

    // MARK: - Drag Gesture

    private func dragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                switch inputMode {
                case .touch:
                    handleTouchDrag(value, in: geometry)
                case .trackpad:
                    handleTrackpadDrag(value, in: geometry)
                }
            }
            .onEnded { value in
                switch inputMode {
                case .touch:
                    handleTouchDragEnd(value, in: geometry)
                case .trackpad:
                    lastTrackpadLocation = nil
                }
            }
    }

    private func handleTouchDrag(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        let remotePoint = screenToRemote(value.location, in: geometry)
        onMouseEvent(MouseEvent(
            x: Int(remotePoint.x),
            y: Int(remotePoint.y),
            buttons: [.left]
        ))
    }

    private func handleTouchDragEnd(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        let remotePoint = screenToRemote(value.location, in: geometry)
        onMouseEvent(MouseEvent(
            x: Int(remotePoint.x),
            y: Int(remotePoint.y),
            buttons: []
        ))
    }

    private func handleTrackpadDrag(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        let currentLocation = value.location

        if let lastLocation = lastTrackpadLocation {
            let deltaX = currentLocation.x - lastLocation.x
            let deltaY = currentLocation.y - lastLocation.y

            // Apply sensitivity
            let sensitivity: CGFloat = 1.5
            cursorPosition.x += deltaX * sensitivity
            cursorPosition.y += deltaY * sensitivity

            // Clamp to display bounds (accounting for offset)
            cursorPosition.x = max(CGFloat(displayOffsetX), min(CGFloat(displayOffsetX + displayWidth), cursorPosition.x))
            cursorPosition.y = max(0, min(CGFloat(displayHeight), cursorPosition.y))

            // Send mouse move
            onMouseEvent(MouseEvent(
                x: Int(cursorPosition.x),
                y: Int(cursorPosition.y),
                buttons: []
            ))
        }

        lastTrackpadLocation = currentLocation
    }

    // MARK: - Tap Gestures

    private func tapGestures(in geometry: GeometryProxy) -> some Gesture {
        SimultaneousGesture(
            singleTapGesture(in: geometry),
            doubleTapGesture(in: geometry)
        )
    }

    private func singleTapGesture(in geometry: GeometryProxy) -> some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { value in
                let point = inputMode == .touch
                    ? screenToRemote(value.location, in: geometry)
                    : cursorPosition

                // Click down
                onMouseEvent(MouseEvent(x: Int(point.x), y: Int(point.y), buttons: [.left]))
                // Click up (after small delay)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    onMouseEvent(MouseEvent(x: Int(point.x), y: Int(point.y), buttons: []))
                }
            }
    }

    private func doubleTapGesture(in geometry: GeometryProxy) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let point = inputMode == .touch
                    ? screenToRemote(value.location, in: geometry)
                    : cursorPosition

                // Double click
                for i in 0..<2 {
                    let delay = Double(i) * 0.1
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        onMouseEvent(MouseEvent(x: Int(point.x), y: Int(point.y), buttons: [.left]))
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.05) {
                        onMouseEvent(MouseEvent(x: Int(point.x), y: Int(point.y), buttons: []))
                    }
                }
            }
    }

    // MARK: - Coordinate Conversion

    private func screenToRemote(_ point: CGPoint, in geometry: GeometryProxy) -> CGPoint {
        guard displayWidth > 0, displayHeight > 0 else { return .zero }

        let viewSize = geometry.size
        let imageAspect = CGFloat(displayWidth) / CGFloat(displayHeight)
        let viewAspect = viewSize.width / viewSize.height

        var imageRect: CGRect

        if imageAspect > viewAspect {
            // Image is wider - fit to width
            let height = viewSize.width / imageAspect
            let y = (viewSize.height - height) / 2
            imageRect = CGRect(x: 0, y: y, width: viewSize.width, height: height)
        } else {
            // Image is taller - fit to height
            let width = viewSize.height * imageAspect
            let x = (viewSize.width - width) / 2
            imageRect = CGRect(x: x, y: 0, width: width, height: viewSize.height)
        }

        // Account for scale and offset
        imageRect = imageRect.applying(CGAffineTransform(scaleX: scale, y: scale))
        imageRect = imageRect.offsetBy(dx: offset.width, dy: offset.height)

        // Convert point relative to displayed image
        let relX = (point.x - imageRect.minX) / imageRect.width
        let relY = (point.y - imageRect.minY) / imageRect.height

        // Add display offset for multi-monitor support
        return CGPoint(
            x: relX * CGFloat(displayWidth) + CGFloat(displayOffsetX),
            y: relY * CGFloat(displayHeight)
        )
    }

    private func remoteToScreen(_ point: CGPoint, in geometry: GeometryProxy) -> CGPoint {
        guard displayWidth > 0, displayHeight > 0 else { return .zero }

        let viewSize = geometry.size
        let imageAspect = CGFloat(displayWidth) / CGFloat(displayHeight)
        let viewAspect = viewSize.width / viewSize.height

        var imageRect: CGRect

        if imageAspect > viewAspect {
            let height = viewSize.width / imageAspect
            let y = (viewSize.height - height) / 2
            imageRect = CGRect(x: 0, y: y, width: viewSize.width, height: height)
        } else {
            let width = viewSize.height * imageAspect
            let x = (viewSize.width - width) / 2
            imageRect = CGRect(x: x, y: 0, width: width, height: viewSize.height)
        }

        imageRect = imageRect.applying(CGAffineTransform(scaleX: scale, y: scale))
        imageRect = imageRect.offsetBy(dx: offset.width, dy: offset.height)

        // Adjust for display offset
        let adjustedX = point.x - CGFloat(displayOffsetX)
        let relX = adjustedX / CGFloat(displayWidth)
        let relY = point.y / CGFloat(displayHeight)

        return CGPoint(
            x: imageRect.minX + relX * imageRect.width,
            y: imageRect.minY + relY * imageRect.height
        )
    }
}
