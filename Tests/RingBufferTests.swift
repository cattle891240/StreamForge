import Foundation

/// `RingBuffer`：每任务日志上限（默认 5000 条）的环形覆盖行为（架构 §8.1）。
func registerRingBufferTests() {
    suite("RingBuffer") {

        test("empty-buffer") {
            let buffer = RingBuffer<Int>(capacity: 3)
            expectEqual(buffer.count, 0)
            expectEqual(buffer.totalAppended, 0)
            expectEqual(buffer.toArray, [])
            expectNil(buffer.newest)
            expectFalse(buffer.isFull)
        }

        test("append-until-full-keeps-insertion-order") {
            var buffer = RingBuffer<Int>(capacity: 3)
            for value in [1, 2, 3] { buffer.append(value) }
            expectEqual(buffer.toArray, [1, 2, 3], "0 = 最旧")
            expectEqual(buffer.count, 3)
            expectEqual(buffer.totalAppended, 3)
            expectTrue(buffer.isFull)
            expectEqual(buffer.newest, 3)
        }

        test("overwrite-drops-oldest") {
            var buffer = RingBuffer<Int>(capacity: 3)
            for value in 1...5 { buffer.append(value) }
            expectEqual(buffer.toArray, [3, 4, 5], "写满后覆盖最旧元素")
            expectEqual(buffer.count, 3)
            expectEqual(buffer.totalAppended, 5, "totalAppended 记录真实写入量")
            expectEqual(buffer.newest, 5)
        }

        test("wrap-around-repeatedly") {
            var buffer = RingBuffer<Int>(capacity: 2)
            for round in 0..<4 {
                buffer.append(round * 10)
                buffer.append(round * 10 + 1)
            }
            expectEqual(buffer.toArray, [30, 31])
            expectEqual(buffer.totalAppended, 8)
        }

        test("subscript-is-oldest-first") {
            var buffer = RingBuffer<String>(capacity: 3)
            for value in ["a", "b", "c", "d"] { buffer.append(value) }
            expectEqual(buffer[0], "b")
            expectEqual(buffer[1], "c")
            expectEqual(buffer[2], "d")
        }

        test("append-contents-of") {
            var buffer = RingBuffer<Int>(capacity: 3)
            buffer.append(contentsOf: [1, 2, 3, 4, 5])
            expectEqual(buffer.toArray, [3, 4, 5])
            expectEqual(buffer.totalAppended, 5)
        }

        test("capacity-one") {
            var buffer = RingBuffer<Int>(capacity: 1)
            buffer.append(7)
            expectEqual(buffer.toArray, [7])
            buffer.append(8)
            expectEqual(buffer.toArray, [8])
            expectEqual(buffer.count, 1)
            expectEqual(buffer.totalAppended, 2)
        }

        test("remove-all-clears-state") {
            var buffer = RingBuffer<Int>(capacity: 3)
            buffer.append(contentsOf: [1, 2, 3, 4])
            buffer.removeAll()
            expectEqual(buffer.toArray, [])
            expectEqual(buffer.count, 0)
            expectFalse(buffer.isFull)
            buffer.append(9)
            expectEqual(buffer.toArray, [9], "清空后写入必须从 0 开始")
        }

        test("log-capacity-5000-drops-oldest") {
            // 架构 §8.1：默认上限 5000 条/任务。
            let capacity = 5000
            var buffer = RingBuffer<Int>(capacity: capacity)
            for value in 0..<(capacity + 10) { buffer.append(value) }
            expectEqual(buffer.count, capacity)
            expectEqual(buffer.toArray.first, 10)
            expectEqual(buffer.toArray.last, capacity + 9)
            expectEqual(buffer.totalAppended, capacity + 10)
        }
    }
}
