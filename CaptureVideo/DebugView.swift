//
//  DebugView.swift
//  CaptureVideo
//
//  Created by Oleksii Kolomiiets on 17.06.2024.
//

import UIKit

class DebugView: UIView {
    var presetLabel: UILabel!
    var rateLabel: UILabel!

    private var preset: String
    private var rate: String
    private let debugFrameRateHelper: DebugFrameRateHelper = .init()

    init(preset: String, rate: String) {
        self.preset = preset
        self.rate = rate

        super.init(frame: .zero)

        setUp()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUp() {
        presetLabel = UILabel()
        presetLabel.text = preset
        presetLabel.textColor = .systemYellow
        addSubview(presetLabel)

        rateLabel = UILabel()
        rateLabel.text = rate
        rateLabel.textColor = .systemYellow
        addSubview(rateLabel)

        presetLabel.translatesAutoresizingMaskIntoConstraints = false
        rateLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            presetLabel.topAnchor.constraint(equalTo: topAnchor),
            presetLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            rateLabel.topAnchor.constraint(equalTo: topAnchor),
            rateLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    func updateFPSValue() {
        debugFrameRateHelper.newFrameDropped()

        DispatchQueue.main.async { [weak self] in
            if let fps = self?.debugFrameRateHelper.fps {
                self?.rateLabel.text = "FPS: \(fps)"
            }
        }
    }
}

final class DebugFrameRateHelper {
    var fps: Int {
        get {
            return fpsValue.load()
        }
    }

    private var dates: [Date] = []
    private let queue = DispatchQueue(label: "com.debugFrameRateHelper.queue", attributes: .concurrent)
    private let fpsValue = AtomicInteger()

    func newFrameDropped() {
        let current = Date()

        // Perform the update in a barrier block to ensure thread safety
        queue.async(flags: .barrier) {
            self.dates.append(current)

            // Remove dates older than 1 second
            let oneSecondAgo = current.addingTimeInterval(-1)
            self.dates.removeAll { $0 < oneSecondAgo }

            // Update fps count
            self.fpsValue.store(self.dates.count)
        }
    }
}

final class AtomicInteger {
    private var value: Int32 = 0

    func load() -> Int {
        return Int(OSAtomicAdd32(0, &value))
    }

    func store(_ newValue: Int) {
        OSAtomicCompareAndSwap32(value, Int32(newValue), &value)
    }
}
