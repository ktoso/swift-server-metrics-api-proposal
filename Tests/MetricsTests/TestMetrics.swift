//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Metrics API open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Metrics API project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Metrics API project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@testable import CoreMetrics
@testable import class CoreMetrics.Timer
import Foundation

internal class TestMetrics: MetricsFactory {
    private let lock = NSLock() // TODO: consider lock per cache?
    var _counters = [String: CounterHandler]()
    subscript(counter label: String) -> CounterHandler? {
        return self._counters["counters.\(label)"]
    }

    var _recorders = [String: RecorderHandler]()
    subscript(recorder label: String) -> RecorderHandler? {
        return self._recorders["recorders.\(label)"]
    }
    
    var _timers = [String: TimerHandler]()
    subscript(timer label: String) -> TimerHandler? {
        return self._timers["timers.\(label)"]
    }
    

    public func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
        return self.make(label: "counters.\(label)", dimensions: dimensions, registry: &self._counters, maker: TestCounter.init)
    }

    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler {
        let maker = { (label: String, dimensions: [(String, String)]) -> RecorderHandler in
            TestRecorder(label: "recorders.\(label)", dimensions: dimensions, aggregate: aggregate)
        }
        return self.make(label: "recorders.\(label)", dimensions: dimensions, registry: &self._recorders, maker: maker)
    }

    public func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
        return self.make(label: "timers.\(label)", dimensions: dimensions, registry: &self._timers, maker: TestTimer.init)
    }

    private func make<Item>(label: String, dimensions: [(String, String)], registry: inout [String: Item], maker: (String, [(String, String)]) -> Item) -> Item {
        return self.lock.withLock {
            if let item = registry[label] {
                return item
            } else {
                let item = maker(label, dimensions)
                registry[label] = item // FIXME: This would cause to override with a zeroed out metric... is this really what we want?
                return item
            }
        }
    }

    public func release(label: String) {
        if label.starts(with: "counters.") {
            self._counters.removeValue(forKey: label)
        } else if label.starts(with: "recorders.") {
            self._recorders.removeValue(forKey: label)
        } else if label.starts(with: "timers.") {
            self._timers.removeValue(forKey: label)
        } else {
            return // nothing to do, not a metric that we created/stored
        }
    }
}

internal class TestCounter: CounterHandler, Equatable {
    let id: String
    let label: String
    let dimensions: [(String, String)]

    let lock = NSLock()
    var values = [(Date, Int64)]()

    init(label: String, dimensions: [(String, String)]) {
        self.id = NSUUID().uuidString
        self.label = label
        self.dimensions = dimensions
    }

    func increment<DataType: BinaryInteger>(_ value: DataType) {
        self.lock.withLock {
            self.values.append((Date(), Int64(value)))
        }
//        print("adding \(value) to \(self.label)")
    }

    func reset() {
        self.lock.withLock {
            self.values = []
        }
    }

    public static func == (lhs: TestCounter, rhs: TestCounter) -> Bool {
        return lhs.id == rhs.id
    }
}

internal class TestRecorder: RecorderHandler, Equatable {
    let id: String
    let label: String
    let dimensions: [(String, String)]
    let aggregate: Bool

    let lock = NSLock()
    var values = [(Date, Double)]()

    init(label: String, dimensions: [(String, String)], aggregate: Bool) {
        self.id = NSUUID().uuidString
        self.label = label
        self.dimensions = dimensions
        self.aggregate = aggregate
    }

    func record<DataType: BinaryInteger>(_ value: DataType) {
        self.record(Double(value))
    }

    func record<DataType: BinaryFloatingPoint>(_ value: DataType) {
        self.lock.withLock {
            // this may loose precision but good enough as an example
            values.append((Date(), Double(value)))
        }
//        print("recoding \(value) in \(self.label)")
    }

    public static func == (lhs: TestRecorder, rhs: TestRecorder) -> Bool {
        return lhs.id == rhs.id
    }
}

internal class TestTimer: TimerHandler, Equatable {
    let id: String
    let label: String
    let dimensions: [(String, String)]

    let lock = NSLock()
    var values = [(Date, Int64)]()

    init(label: String, dimensions: [(String, String)]) {
        self.id = NSUUID().uuidString
        self.label = label
        self.dimensions = dimensions
    }

    func recordNanoseconds(_ duration: Int64) {
        self.lock.withLock {
            values.append((Date(), duration))
        }
//        print("recoding \(duration) \(self.label)")
    }

    public static func == (lhs: TestTimer, rhs: TestTimer) -> Bool {
        return lhs.id == rhs.id
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        self.lock()
        defer {
            self.unlock()
        }
        return body()
    }
}
