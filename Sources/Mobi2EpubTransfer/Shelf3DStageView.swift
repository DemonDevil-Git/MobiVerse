import AppKit
import QuartzCore
import SwiftUI

struct Shelf3DItem {
    let id: UUID
    let title: String
    let coverImage: NSImage?
    let isDimmed: Bool
}

struct Shelf3DStageView: NSViewRepresentable {
    let items: [Shelf3DItem]
    let selectedID: UUID?
    let isDetailPresented: Bool
    let reduceMotion: Bool
    let isDark: Bool
    let onSelect: (UUID) -> Void
    let onOpen: (UUID) -> Void
    let onStep: (Int) -> Void
    let onClose: () -> Void

    func makeNSView(context: Context) -> Shelf3DStageNSView {
        let view = Shelf3DStageNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: Shelf3DStageNSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: Shelf3DStageNSView) {
        view.onSelect = onSelect
        view.onOpen = onOpen
        view.onStep = onStep
        view.onClose = onClose
        view.update(
            items: items,
            selectedID: selectedID,
            isDetailPresented: isDetailPresented,
            reduceMotion: reduceMotion,
            isDark: isDark
        )
    }
}

@MainActor
final class Shelf3DStageNSView: NSView {
    var onSelect: (UUID) -> Void = { _ in }
    var onOpen: (UUID) -> Void = { _ in }
    var onStep: (Int) -> Void = { _ in }
    var onClose: () -> Void = {}

    private let worldLayer = CATransformLayer()
    private let selectedShadowLayer = CALayer()
    private var nodes: [UUID: Book3DNode] = [:]
    private var items: [Shelf3DItem] = []
    private var selectedID: UUID?
    private var previousSelectedID: UUID?
    private var hoveredID: UUID?
    private var isDetailPresented = false
    private var reduceMotion = false
    private var isDark = false
    private var hasPresentedContent = false
    private var scrollAccumulator: CGFloat = 0
    private var mouseDownPoint: CGPoint?
    private var mouseDownBookID: UUID?
    private var draggedYaw: CGFloat?
    private var didDrag = false
    private var nodeWarmupTask: Task<Void, Never>?
    private let maximumRetainedNodeCount = 40

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true

        selectedShadowLayer.backgroundColor = NSColor.black.withAlphaComponent(0.065).cgColor
        selectedShadowLayer.cornerRadius = 18
        selectedShadowLayer.shadowColor = NSColor.black.cgColor
        selectedShadowLayer.shadowOpacity = 0.22
        selectedShadowLayer.shadowRadius = 18
        selectedShadowLayer.shadowOffset = CGSize(width: 0, height: -2)
        layer?.addSublayer(selectedShadowLayer)
        layer?.addSublayer(worldLayer)
        updatePerspective()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        worldLayer.frame = bounds
        CATransaction.commit()
        updatePerspective()
        layoutBooks(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )
        )
    }

    func update(
        items: [Shelf3DItem],
        selectedID: UUID?,
        isDetailPresented: Bool,
        reduceMotion: Bool,
        isDark: Bool
    ) {
        let selectionChanged = self.selectedID != selectedID
        let detailChanged = self.isDetailPresented != isDetailPresented
        let appearanceChanged = self.isDark != isDark
        let motionPreferenceChanged = self.reduceMotion != reduceMotion
        let itemIDsChanged = self.items.map(\.id) != items.map(\.id)
        if selectionChanged {
            previousSelectedID = self.selectedID
            hoveredID = nil
            draggedYaw = nil
            updateCursor()
        }
        if itemIDsChanged {
            nodeWarmupTask?.cancel()
            nodeWarmupTask = nil
        }

        self.items = items
        self.selectedID = selectedID ?? items.first?.id
        self.isDetailPresented = isDetailPresented
        self.reduceMotion = reduceMotion
        self.isDark = isDark

        let validIDs = Set(items.map(\.id))
        for (id, node) in nodes where !validIDs.contains(id) {
            node.layer.removeFromSuperlayer()
            nodes[id] = nil
        }

        updateShadowAppearance()
        let geometryChanged = selectionChanged
            || detailChanged
            || appearanceChanged
            || motionPreferenceChanged
            || itemIDsChanged
        if geometryChanged || !hasPresentedContent {
            layoutBooks(animated: hasPresentedContent && geometryChanged)
        } else {
            updateExistingNodeContents()
        }
        hasPresentedContent = !items.isEmpty
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        mouseDownPoint = point
        mouseDownBookID = bookID(at: point)
        draggedYaw = nil
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            isDetailPresented,
            !reduceMotion,
            let selectedID,
            mouseDownBookID == selectedID,
            let start = mouseDownPoint,
            let node = nodes[selectedID]
        else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let horizontalDistance = point.x - start.x
        if abs(horizontalDistance) > 2 { didDrag = true }
        let yaw = min(1.16, max(-1.16, -0.08 + horizontalDistance * 0.009))
        draggedYaw = yaw
        node.setInteractiveTransform(scale: selectedScale, yaw: yaw)
        selectedShadowLayer.opacity = Float(max(0.05, 0.18 - abs(yaw) * 0.08))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownPoint = nil
            mouseDownBookID = nil
        }

        if didDrag {
            draggedYaw = nil
            layoutBooks(animated: true)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        guard let id = mouseDownBookID ?? bookID(at: point) else { return }
        if id == selectedID {
            onOpen(id)
        } else {
            hoveredID = nil
            updateCursor()
            onSelect(id)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isDetailPresented else { return }
        let nextHoveredID = bookID(at: convert(event.locationInWindow, from: nil))
        guard hoveredID != nextHoveredID else { return }
        hoveredID = nextHoveredID
        updateCursor()
    }

    override func mouseExited(with event: NSEvent) {
        guard hoveredID != nil else { return }
        hoveredID = nil
        NSCursor.arrow.set()
    }

    override func scrollWheel(with event: NSEvent) {
        guard !isDetailPresented, items.count > 1 else { return }
        let dominantDelta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY
        scrollAccumulator += dominantDelta
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 22 : 1
        guard abs(scrollAccumulator) >= threshold else { return }
        let direction = scrollAccumulator > 0 ? -1 : 1
        scrollAccumulator = 0
        onStep(direction)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            onStep(-1)
        case 124:
            onStep(1)
        case 36, 49:
            if let selectedID { onOpen(selectedID) }
        case 53:
            if isDetailPresented { onClose() } else { super.keyDown(with: event) }
        default:
            super.keyDown(with: event)
        }
    }

    private func layoutBooks(animated: Bool) {
        guard bounds.width > 0, bounds.height > 0, let selectedID else {
            hideAllNodes()
            return
        }

        let centerY = bounds.midY + 3
        let scale = selectedScale
        let selectedHalfWidth = (nodes[selectedID]?.width ?? 140) * scale * 0.5
        let textRightEdge = 28 + min(190, max(120, bounds.width * 0.22))
        let browsingSelectedX = max(bounds.width * 0.44, textRightEdge + selectedHalfWidth + 22)
        let selectedX = isDetailPresented ? bounds.width * 0.255 : browsingSelectedX
        let spineStartX = max(selectedX + selectedHalfWidth + 30, bounds.width * 0.61)
        let spineAvailableWidth = max(0, bounds.maxX - spineStartX - 24)
        let displayOrder = spineDisplayOrder(around: selectedID, availableWidth: spineAvailableWidth)
        var requiredIDs = Set(displayOrder.map(\.id))
        requiredIDs.insert(selectedID)
        if let previousSelectedID { requiredIDs.insert(previousSelectedID) }
        ensureNodes(for: requiredIDs)

        let selectedYaw = draggedYaw ?? (isDetailPresented ? -0.08 : -0.045)

        for (id, node) in nodes {
            guard id == selectedID else { continue }
            let opacity: Float = node.item.isDimmed ? 0.46 : 1
            apply(
                node: node,
                position: CGPoint(x: selectedX, y: centerY),
                zPosition: 100,
                scale: scale,
                yaw: selectedYaw,
                opacity: opacity,
                animated: animated && draggedYaw == nil
            )
        }

        var spineX = spineStartX
        for (index, item) in displayOrder.enumerated() {
            guard let node = nodes[item.id], item.id != selectedID else { continue }
            if isDetailPresented {
                apply(
                    node: node,
                    position: CGPoint(x: bounds.width * 0.67 + CGFloat(index) * 12, y: centerY),
                    zPosition: CGFloat(30 - index),
                    scale: scale * 0.82,
                    yaw: .pi / 2,
                    opacity: 0,
                    animated: animated
                )
                continue
            }

            let spineScale = scale * 0.90
            let opacity: Float = item.isDimmed ? 0.36 : 0.92
            spineX += node.depth * spineScale * 0.5
            apply(
                node: node,
                position: CGPoint(x: spineX, y: centerY),
                zPosition: CGFloat(70 - index),
                scale: spineScale,
                yaw: .pi / 2,
                opacity: opacity,
                animated: animated
            )
            spineX += node.depth * spineScale * 0.5 + 8
        }

        for (id, node) in nodes where !requiredIDs.contains(id) {
            apply(
                node: node,
                position: CGPoint(x: bounds.maxX + 80, y: centerY),
                zPosition: 0,
                scale: scale * 0.82,
                yaw: .pi / 2,
                opacity: 0,
                animated: animated
            )
        }

        layoutShadow(selectedX: selectedX, centerY: centerY, scale: scale, animated: animated)
        schedulePruning(requiredIDs: requiredIDs)
        scheduleNodeWarmup()
    }

    private var selectedScale: CGFloat {
        let availableHeight = max(210, bounds.height - 108)
        let heightFitted = min(1.24, max(0.68, availableHeight / 238))
        let widthFitted = min(1.24, max(0.68, bounds.width / 620))
        let fitted = min(heightFitted, widthFitted)
        return fitted * (isDetailPresented ? 1.08 : 1)
    }

    private func spineDisplayOrder(around selectedID: UUID, availableWidth: CGFloat) -> [Shelf3DItem] {
        guard
            items.count > 1,
            let selectedIndex = items.firstIndex(where: { $0.id == selectedID })
        else {
            return []
        }

        let maximumCount = min(items.count - 1, min(7, max(1, Int(availableWidth / 42))))
        var result: [Shelf3DItem] = []
        var seen: Set<UUID> = [selectedID]

        let previousIndex = (selectedIndex - 1 + items.count) % items.count
        if seen.insert(items[previousIndex].id).inserted {
            result.append(items[previousIndex])
        }

        var offset = 1
        while result.count < maximumCount && offset < items.count {
            let index = (selectedIndex + offset) % items.count
            if seen.insert(items[index].id).inserted { result.append(items[index]) }
            offset += 1
        }
        return result
    }

    private func ensureNodes(for ids: Set<UUID>) {
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for id in ids {
            guard let item = itemByID[id] else { continue }
            if let node = nodes[id] {
                node.update(with: item, isDark: isDark, contentsScale: backingScale)
            } else {
                let node = Book3DNode(item: item, isDark: isDark, contentsScale: backingScale)
                nodes[id] = node
                node.layer.position = CGPoint(x: bounds.maxX + 80, y: bounds.midY)
                node.layer.opacity = 0
                worldLayer.addSublayer(node.layer)
            }
        }
    }

    private func updateExistingNodeContents() {
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for (id, node) in nodes {
            guard let item = itemByID[id] else { continue }
            node.update(with: item, isDark: isDark, contentsScale: backingScale)
        }
    }

    private func scheduleNodeWarmup() {
        guard items.count <= maximumRetainedNodeCount, nodeWarmupTask == nil else { return }
        let missingIDs = items.map(\.id).filter { nodes[$0] == nil }
        guard !missingIDs.isEmpty else { return }

        nodeWarmupTask = Task { @MainActor [weak self] in
            for id in missingIDs {
                guard let self, !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(12))
                guard !Task.isCancelled, self.items.contains(where: { $0.id == id }) else { continue }
                self.ensureNodes(for: [id])
            }
            self?.nodeWarmupTask = nil
        }
    }

    private func schedulePruning(requiredIDs: Set<UUID>) {
        guard items.count > maximumRetainedNodeCount else {
            previousSelectedID = nil
            return
        }
        let selectedSnapshot = selectedID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.selectedID == selectedSnapshot else { return }
            for (id, node) in self.nodes where !requiredIDs.contains(id) {
                node.layer.removeFromSuperlayer()
                self.nodes[id] = nil
            }
            if self.previousSelectedID != self.selectedID {
                self.previousSelectedID = nil
            }
        }
    }

    private func layoutShadow(selectedX: CGFloat, centerY: CGFloat, scale: CGFloat, animated: Bool) {
        let size = CGSize(width: 145 * scale, height: 18 * scale)
        let position = CGPoint(x: selectedX + 7 * scale, y: centerY - 112 * scale)
        let opacity: Float = isDetailPresented ? 0.20 : 0.15
        animatePosition(of: selectedShadowLayer, to: position, animated: animated)
        animateBounds(of: selectedShadowLayer, to: CGRect(origin: .zero, size: size), animated: animated)
        animateOpacity(of: selectedShadowLayer, to: opacity, animated: animated)
        selectedShadowLayer.cornerRadius = size.height / 2
    }

    private func apply(
        node: Book3DNode,
        position: CGPoint,
        zPosition: CGFloat,
        scale: CGFloat,
        yaw: CGFloat,
        opacity: Float,
        animated: Bool
    ) {
        var transform = CATransform3DIdentity
        transform = CATransform3DScale(transform, scale, scale, scale)
        transform = CATransform3DRotate(transform, yaw, 0, 1, 0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        node.layer.position = position
        node.layer.zPosition = zPosition
        node.layer.transform = transform
        node.layer.opacity = opacity
        CATransaction.commit()

        guard animated else {
            node.layer.removeAllAnimations()
            return
        }
        addSpringAnimation(to: node.layer, keyPath: "position", toValue: NSValue(point: position))
        addSpringAnimation(to: node.layer, keyPath: "transform", toValue: NSValue(caTransform3D: transform))
        addOpacityAnimation(to: node.layer, toValue: opacity)
    }

    private func addSpringAnimation(to layer: CALayer, keyPath: String, toValue: Any) {
        let animation = CASpringAnimation(keyPath: keyPath)
        if keyPath == "position" {
            animation.fromValue = NSValue(point: layer.presentation()?.position ?? layer.position)
        } else {
            animation.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
        }
        animation.toValue = toValue
        animation.mass = 1
        animation.stiffness = reduceMotion ? 420 : 185
        animation.damping = reduceMotion ? 42 : 24
        animation.initialVelocity = 0
        animation.duration = reduceMotion ? 0.18 : min(0.78, animation.settlingDuration)
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: keyPath)
    }

    private func addOpacityAnimation(to layer: CALayer, toValue: Float) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
        animation.toValue = toValue
        animation.duration = reduceMotion ? 0.14 : 0.28
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "opacity")
    }

    private func animatePosition(of layer: CALayer, to position: CGPoint, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = position
        CATransaction.commit()
        if animated { addSpringAnimation(to: layer, keyPath: "position", toValue: NSValue(point: position)) }
    }

    private func animateBounds(of layer: CALayer, to bounds: CGRect, animated: Bool) {
        let from = layer.presentation()?.bounds ?? layer.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = bounds
        CATransaction.commit()
        guard animated else { return }
        let animation = CABasicAnimation(keyPath: "bounds")
        animation.fromValue = NSValue(rect: from)
        animation.toValue = NSValue(rect: bounds)
        animation.duration = reduceMotion ? 0.18 : 0.55
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "bounds")
    }

    private func animateOpacity(of layer: CALayer, to opacity: Float, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        CATransaction.commit()
        if animated { addOpacityAnimation(to: layer, toValue: opacity) }
    }

    private func bookID(at point: CGPoint) -> UUID? {
        guard let rootLayer = layer else { return nil }

        // During an in-flight Core Animation transition, the model layer is
        // already at its destination while the user is clicking the visible
        // presentation layer. Hit-test the latter so rapid selections remain
        // responsive and interruptible.
        var candidate = (rootLayer.presentation() ?? rootLayer).hitTest(point)
        while let current = candidate {
            if let name = current.name, let id = UUID(uuidString: name) { return id }
            candidate = current.superlayer
        }
        return nil
    }

    private func updateCursor() {
        if hoveredID != nil { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    }

    private func updatePerspective() {
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / max(780, bounds.width * 1.15)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        worldLayer.sublayerTransform = perspective
        CATransaction.commit()
    }

    private func updateShadowAppearance() {
        selectedShadowLayer.backgroundColor = (isDark ? NSColor.black.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.055)).cgColor
        selectedShadowLayer.shadowOpacity = isDark ? 0.34 : 0.20
    }

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func hideAllNodes() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        nodes.values.forEach { $0.layer.opacity = 0 }
        selectedShadowLayer.opacity = 0
        CATransaction.commit()
    }
}

@MainActor
private final class Book3DNode {
    let layer = CATransformLayer()
    let width: CGFloat
    let height: CGFloat
    let depth: CGFloat
    private(set) var item: Shelf3DItem

    private let front = CALayer()
    private let back = CALayer()
    private let spine = CALayer()
    private let pages = CALayer()
    private let topPages = CALayer()
    private let bottomPages = CALayer()
    private let frontPlaceholder = CATextLayer()
    private let spineTitle = CATextLayer()
    private let frontGloss = CAGradientLayer()
    private let backShade = CALayer()
    private var appliedIsDark: Bool?
    private var appliedContentsScale: CGFloat = 0

    init(item: Shelf3DItem, isDark: Bool, contentsScale: CGFloat) {
        self.item = item
        let seed = item.id.uuidString.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0x7fff }
        width = 136 + CGFloat(seed % 7)
        height = 202 + CGFloat((seed / 7) % 9)
        depth = 17 + CGFloat((seed / 13) % 10)

        layer.name = item.id.uuidString
        layer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        buildGeometry(contentsScale: contentsScale)
        update(with: item, isDark: isDark, contentsScale: contentsScale)
    }

    func update(with item: Shelf3DItem, isDark: Bool, contentsScale: CGFloat) {
        let usesSameImage: Bool
        switch (self.item.coverImage, item.coverImage) {
        case (nil, nil):
            usesSameImage = true
        case let (current?, next?):
            usesSameImage = current === next
        default:
            usesSameImage = false
        }
        let hasSameAppearance = appliedIsDark == isDark
            && appliedContentsScale == contentsScale
            && self.item.title == item.title
            && usesSameImage
            && self.item.isDimmed == item.isDimmed
        if hasSameAppearance {
            self.item = item
            return
        }

        self.item = item
        appliedIsDark = isDark
        appliedContentsScale = contentsScale
        let coverColor = item.coverImage.flatMap(Self.averageColor) ?? Self.fallbackColor(for: item.id, isDark: isDark)
        let pageColor = isDark
            ? NSColor(red: 0.58, green: 0.55, blue: 0.46, alpha: 1)
            : NSColor(red: 0.90, green: 0.86, blue: 0.74, alpha: 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        front.contents = item.coverImage?.cgImage
        front.backgroundColor = coverColor.cgColor
        back.contents = item.coverImage?.cgImage
        back.backgroundColor = coverColor.blended(withFraction: 0.22, of: .black)?.cgColor ?? coverColor.cgColor
        spine.backgroundColor = coverColor.blended(withFraction: 0.14, of: .black)?.cgColor ?? coverColor.cgColor
        pages.backgroundColor = pageColor.cgColor
        topPages.backgroundColor = pageColor.blended(withFraction: 0.06, of: .white)?.cgColor ?? pageColor.cgColor
        bottomPages.backgroundColor = pageColor.blended(withFraction: 0.08, of: .black)?.cgColor ?? pageColor.cgColor
        frontPlaceholder.opacity = item.coverImage == nil ? 1 : 0
        frontPlaceholder.string = Self.attributedTitle(item.title, color: Self.contrastingColor(for: coverColor), fontSize: 15)
        spineTitle.string = Self.attributedTitle(item.title, color: Self.contrastingColor(for: coverColor), fontSize: 9)
        [front, back, spine, pages, topPages, bottomPages, frontPlaceholder, spineTitle].forEach {
            $0.contentsScale = contentsScale
        }
        layer.opacity = item.isDimmed ? 0.46 : layer.opacity
        CATransaction.commit()
    }

    func setInteractiveTransform(scale: CGFloat, yaw: CGFloat) {
        var transform = CATransform3DIdentity
        transform = CATransform3DScale(transform, scale, scale, scale)
        transform = CATransform3DRotate(transform, yaw, 0, 1, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        CATransaction.commit()
        layer.removeAnimation(forKey: "transform")
    }

    private func buildGeometry(contentsScale: CGFloat) {
        let center = CGPoint(x: width / 2, y: height / 2)
        configureFace(front, bounds: CGSize(width: width, height: height), position: center, z: depth / 2)
        configureFace(back, bounds: CGSize(width: width, height: height), position: center, z: -depth / 2)
        back.transform = CATransform3DMakeRotation(.pi, 0, 1, 0)

        configureFace(spine, bounds: CGSize(width: depth, height: height), position: CGPoint(x: 0, y: height / 2), z: 0)
        spine.transform = CATransform3DMakeRotation(-.pi / 2, 0, 1, 0)

        configureFace(pages, bounds: CGSize(width: depth, height: height - 6), position: CGPoint(x: width, y: height / 2), z: 0)
        pages.transform = CATransform3DMakeRotation(.pi / 2, 0, 1, 0)

        configureFace(topPages, bounds: CGSize(width: width - 6, height: depth), position: CGPoint(x: width / 2, y: height), z: 0)
        topPages.transform = CATransform3DMakeRotation(.pi / 2, 1, 0, 0)

        configureFace(bottomPages, bounds: CGSize(width: width - 6, height: depth), position: CGPoint(x: width / 2, y: 0), z: 0)
        bottomPages.transform = CATransform3DMakeRotation(-.pi / 2, 1, 0, 0)

        [back, spine, pages, topPages, bottomPages, front].forEach(layer.addSublayer)

        frontPlaceholder.frame = CGRect(x: 15, y: 18, width: width - 30, height: height - 36)
        frontPlaceholder.alignmentMode = .center
        frontPlaceholder.isWrapped = true
        frontPlaceholder.truncationMode = .end
        front.addSublayer(frontPlaceholder)

        frontGloss.frame = front.bounds
        frontGloss.colors = [
            NSColor.white.withAlphaComponent(0.16).cgColor,
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.10).cgColor
        ]
        frontGloss.locations = [0, 0.44, 1]
        frontGloss.startPoint = CGPoint(x: 0, y: 1)
        frontGloss.endPoint = CGPoint(x: 1, y: 0)
        front.addSublayer(frontGloss)

        backShade.frame = back.bounds
        backShade.backgroundColor = NSColor.black.withAlphaComponent(0.16).cgColor
        back.addSublayer(backShade)

        spineTitle.bounds = CGRect(x: 0, y: 0, width: height - 22, height: max(12, depth - 5))
        spineTitle.position = CGPoint(x: depth / 2, y: height / 2)
        spineTitle.setAffineTransform(CGAffineTransform(rotationAngle: .pi / 2))
        spineTitle.alignmentMode = .center
        spineTitle.truncationMode = .end
        spine.addSublayer(spineTitle)

        addPageTexture(to: pages)
        addPageTexture(to: topPages, vertical: true)
        [front, back].forEach {
            $0.cornerRadius = 4
            $0.masksToBounds = true
        }
        [front, back, spine, pages, topPages, bottomPages].forEach { $0.contentsScale = contentsScale }
    }

    private func configureFace(_ face: CALayer, bounds: CGSize, position: CGPoint, z: CGFloat) {
        face.bounds = CGRect(origin: .zero, size: bounds)
        face.position = position
        face.zPosition = z
        face.isDoubleSided = false
        face.magnificationFilter = .linear
        face.minificationFilter = .trilinear
        face.contentsGravity = .resizeAspectFill
    }

    private func addPageTexture(to face: CALayer, vertical: Bool = false) {
        let lineCount = vertical ? 7 : 13
        for index in 1..<lineCount {
            let line = CALayer()
            line.backgroundColor = NSColor.black.withAlphaComponent(index.isMultiple(of: 3) ? 0.08 : 0.035).cgColor
            if vertical {
                line.frame = CGRect(x: CGFloat(index) * face.bounds.width / CGFloat(lineCount), y: 0, width: 0.5, height: face.bounds.height)
            } else {
                line.frame = CGRect(x: 0, y: CGFloat(index) * face.bounds.height / CGFloat(lineCount), width: face.bounds.width, height: 0.5)
            }
            face.addSublayer(line)
        }
    }

    private static func attributedTitle(_ title: String, color: NSColor, fontSize: CGFloat) -> NSAttributedString {
        NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: color,
                .kern: fontSize < 10 ? 0.45 : 0.1
            ]
        )
    }

    private static func averageColor(of image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return NSColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }

    private static func fallbackColor(for id: UUID, isDark: Bool) -> NSColor {
        let palette: [NSColor] = isDark
            ? [
                NSColor(red: 0.21, green: 0.38, blue: 0.44, alpha: 1),
                NSColor(red: 0.39, green: 0.27, blue: 0.19, alpha: 1),
                NSColor(red: 0.30, green: 0.42, blue: 0.28, alpha: 1),
                NSColor(red: 0.43, green: 0.22, blue: 0.20, alpha: 1)
            ]
            : [
                NSColor(red: 0.25, green: 0.45, blue: 0.52, alpha: 1),
                NSColor(red: 0.56, green: 0.36, blue: 0.23, alpha: 1),
                NSColor(red: 0.38, green: 0.52, blue: 0.34, alpha: 1),
                NSColor(red: 0.64, green: 0.32, blue: 0.25, alpha: 1)
            ]
        let seed = id.uuidString.utf8.reduce(0) { ($0 &* 33 &+ Int($1)) & 0x7fff }
        return palette[seed % palette.count]
    }

    private static func contrastingColor(for color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return .white }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.58 ? NSColor.black.withAlphaComponent(0.76) : NSColor.white.withAlphaComponent(0.92)
    }
}

private extension NSImage {
    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
