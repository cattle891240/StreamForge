import Foundation
import Darwin

/// 从一对管道（stdout / stderr）增量读取内核输出。
///
/// 内核在非 TTY 模式下会把多条日志与多个进度帧粘连写入同一缓冲（契约 §3），
/// 读取层只负责把字节原样喂给解析层，**不做任何切分**——切分由 `OutputParser` 完成。
final class OutputPump {
    private let stdoutFD: Int32
    private let stderrFD: Int32
    private let queue: DispatchQueue
    private let onChunk: (_ isStderr: Bool, _ data: Data) -> Void
    private var sources: [DispatchSourceRead] = []
    private var cancelled = false

    init(
        stdoutFD: Int32,
        stderrFD: Int32,
        queue: DispatchQueue,
        onChunk: @escaping (_ isStderr: Bool, _ data: Data) -> Void
    ) {
        self.stdoutFD = stdoutFD
        self.stderrFD = stderrFD
        self.queue = queue
        self.onChunk = onChunk
    }

    func start() {
        guard !cancelled else { return }
        for descriptor in [(false, stdoutFD), (true, stderrFD)] {
            let isStderr = descriptor.0
            let fd = descriptor.1
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            source.setEventHandler { [weak self] in
                let n = read(fd, buffer, 4096)
                if n > 0 {
                    let data = Data(bytes: buffer, count: Int(n))
                    self?.onChunk(isStderr, data)
                } else {
                    source.cancel()
                }
            }
            source.setCancelHandler {
                close(fd)
                buffer.deallocate()
            }
            source.resume()
            sources.append(source)
        }
    }

    func cancel() {
        cancelled = true
        for source in sources { source.cancel() }
        sources.removeAll()
    }
}
