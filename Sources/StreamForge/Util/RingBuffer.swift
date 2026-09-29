import Foundation

/// 定长环形缓冲：写满后覆盖最旧元素。用于每任务日志上限（默认 5000 条）。
struct RingBuffer<Element> {
    let capacity: Int
    private var storage: [Element?]
    private var writeIndex = 0
    private(set) var count = 0
    private(set) var totalAppended = 0

    init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer 容量必须为正")
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    mutating func append(_ element: Element) {
        storage[writeIndex] = element
        writeIndex = (writeIndex + 1) % capacity
        if count < capacity { count += 1 }
        totalAppended += 1
    }

    mutating func append(contentsOf elements: [Element]) {
        for element in elements { append(element) }
    }

    /// 最旧 → 最新。
    var toArray: [Element] {
        guard count > 0 else { return [] }
        let start = (writeIndex - count + capacity) % capacity
        var result: [Element] = []
        result.reserveCapacity(count)
        for offset in 0..<count {
            if let element = storage[(start + offset) % capacity] { result.append(element) }
        }
        return result
    }

    /// 0 = 最旧。
    subscript(index: Int) -> Element {
        precondition(index >= 0 && index < count, "下标越界")
        let start = (writeIndex - count + capacity) % capacity
        return storage[(start + index) % capacity]!
    }

    var newest: Element? {
        guard count > 0 else { return nil }
        return storage[(writeIndex - 1 + capacity) % capacity]
    }

    var isFull: Bool { count == capacity }

    mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        writeIndex = 0
        count = 0
    }
}
