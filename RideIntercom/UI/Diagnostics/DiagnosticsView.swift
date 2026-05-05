import SwiftUI

struct DiagnosticsView: View {
    @Bindable var viewModel: IntercomViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    LiveTransmitPipelineView(viewModel: viewModel)
                    LiveReceivePipelineView(viewModel: viewModel)
                    DiagnosticsOverviewGrid(rows: viewModel.diagnosticsOverviewRows)
                }
                .padding(AppSpacing.l)
            }
            .accessibilityIdentifier("diagnosticsScrollView")
        }
    }
}
