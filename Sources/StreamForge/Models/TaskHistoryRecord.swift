import Foundation

/// 历史记录：仅元数据，不含日志正文。用于"再次下载"重建任务。
struct TaskHistoryRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var input: InputSource
    var options: DownloadOptions
    var saveDir: String
    var finishedAt: Date
    var outcome: TaskOutcome
    var bytesTotal: Int64?
    var elapsedSeconds: TimeInterval

    /// 重建任务时的输入与选项（tmp 目录每次重新生成，不复用）。
    func makeTask(tmpDir: String) -> DownloadTask {
        DownloadTask(id: UUID(),
                     input: input,
                     options: options,
                     phase: .queued,
                     progress: .empty,
                     saveDir: saveDir,
                     tmpDir: tmpDir)
    }
}
