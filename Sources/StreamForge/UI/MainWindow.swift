import SwiftUI

/// 主窗口：三栏 NavigationSplitView + 工具栏（design.md 附录 A.1）。
/// 只做布局与事件转发，业务动作全部交给 `AppEnvironment`。
struct MainWindow: View {

    @EnvironmentObject private var env: AppEnvironment

    @State private var filter: TaskFilter = .all
    @State private var searchText = ""
    @State private var isDropTargeted = false

    private var tasks: [DownloadTask] { env.queue.tasks }

    var body: some View {
        DropZoneOverlay(isTargeted: $isDropTargeted, onReceive: handleDrop) {
            NavigationSplitView {
                SidebarView(filter: $filter, counts: TaskFilter.counts(from: tasks))
                    .navigationSplitViewColumnWidth(min: 180, ideal: SFSize.sidebarWidth)
            } content: {
                TaskListView(filter: filter, searchText: searchText)
                    .navigationSplitViewColumnWidth(min: 380, ideal: 460)
                    .searchable(text: $searchText, placement: .toolbar, prompt: "按文件名或链接搜索")
            } detail: {
                TaskDetailView(task: env.selectedTask())
                    .navigationSplitViewColumnWidth(min: 420, ideal: SFSize.detailWidth)
            }
            .toolbar { toolbarContent }
        }
        .sheet(isPresented: $env.composerPresented) {
            NewTaskSheet().environmentObject(env)
        }
        .sheet(isPresented: $env.dependencySheetPresented) {
            DependencyView().environmentObject(env)
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                env.composerPresented = true
            } label: {
                Label("新建任务", systemImage: SFSymbol.newTask)
            }
            .buttonStyle(.borderedProminent)
            .help("新建下载任务（Command-N）")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                for task in tasks where task.phase.canResume { env.resume(task.id) }
            } label: {
                Label("全部开始", systemImage: SFSymbol.startAll)
            }
            .disabled(!tasks.contains { $0.phase.canResume })
            .help("开始所有排队、暂停与已停止的任务")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                for task in tasks where task.phase.canPause && !task.options.isLive {
                    env.pause(task.id)
                }
            } label: {
                Label("全部暂停", systemImage: SFSymbol.pauseAll)
            }
            .disabled(!tasks.contains { $0.phase.canPause && !$0.options.isLive })
            .help("暂停所有下载中的任务（直播任务不支持暂停）")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                if let id = env.selectedTaskID { env.stopKeepingTemp(id) }
            } label: {
                Label("停止选中", systemImage: SFSymbol.stop)
            }
            .disabled(env.selectedTask()?.phase.canPause != true)
            .help("停止选中任务并保留已下载分片")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                if let id = env.selectedTaskID { env.remove(id) }
            } label: {
                Label("移除", systemImage: SFSymbol.remove)
            }
            .disabled(env.selectedTaskID == nil)
            .help("从列表移除选中任务（文件保留）")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                env.dependencySheetPresented = true
            } label: {
                Label("依赖状态", systemImage: dependencySymbol)
            }
            .foregroundStyle(dependencyColor)
            .help("查看 N_m3u8DL-RE 与 ffmpeg 的安装状态")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("设置", systemImage: SFSymbol.settings)
            }
            .help("打开设置（Command-,）")
        }
    }

    private var dependencySymbol: String {
        env.dependencies.missingRequired.isEmpty ? SFSymbol.dependencyShield : SFSymbol.dependencyMissing
    }

    private var dependencyColor: Color {
        env.dependencies.missingRequired.isEmpty ? SFColor.labelSecondary : SFColor.warning
    }

    private func handleDrop(_ sources: [InputSource]) {
        for source in sources {
            env.createTask(input: source,
                           options: env.settings.defaultOptions,
                           saveDir: nil,
                           saveName: nil)
        }
    }
}
