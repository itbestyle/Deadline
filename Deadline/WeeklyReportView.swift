import SwiftUI

struct WeeklyReportView: View {
    let deadlines: [Deadline]
    private let engine = PressureInsightsEngine()
    @Environment(\.dismiss) private var dismiss

    private var report: WeeklyPressureReport {
        engine.makeReport(from: deadlines)
    }

    private var overloadTint: Color {
        if report.overloadIndex >= 70 { return .red }
        if report.overloadIndex >= 40 { return .orange }
        return .green
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("Weekly Pressure Report"))
                        .font(.title2.weight(.bold))

                    HStack(spacing: 10) {
                        metricCard(title: L("Индекс"), value: "\(report.overloadIndex)%", tint: overloadTint, emphasized: true)
                        metricCard(title: L("Активные"), value: "\(report.totalActive)", tint: .indigo)
                    }

                    HStack(spacing: 10) {
                        metricCard(title: L("Изм. к прошлой неделе"), value: "\(report.overloadDeltaPercent > 0 ? "+" : "")\(report.overloadDeltaPercent)%", tint: report.overloadDeltaPercent <= 0 ? .green : .red)
                        metricCard(title: L("Серия без просрочек"), value: report.noOverdueStreakWeeks == 0 ? "—" : "\(report.noOverdueStreakWeeks)", tint: report.noOverdueStreakWeeks >= 3 ? .green : .orange)
                    }

                    Text(overloadDeltaSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(report.overloadDeltaPercent > 0 ? .red : .secondary)
                        .padding(.horizontal, 4)

                    HStack(spacing: 10) {
                        metricCard(title: L("Критичные 24ч"), value: "\(report.criticalCount)", tint: .red)
                        metricCard(title: L("72ч окно"), value: "\(report.mediumCount)", tint: .orange)
                    }

                    HStack(spacing: 10) {
                        metricCard(title: L("Просрочено"), value: "\(report.overdueCount)", tint: .pink)
                        metricCard(title: L("Сдано / 7д"), value: "\(report.completedLast7Days)", tint: .green)
                    }

                    if let day = report.overloadDayLabel {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .foregroundStyle(.orange)
                            Text(String(format: L("Пик нагрузки: %@"), day))
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    HStack(spacing: 8) {
                        Image(systemName: report.weekAssessment == L("Неделя под контролем") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(report.weekAssessment == L("Неделя под контролем") ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(report.weekAssessment)
                                .font(.subheadline.weight(.semibold))
                            Text(report.weekAssessmentReason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Text(L("Умные инсайты"))
                        .font(.headline)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(report.insights.indices, id: \.self) { index in
                            let text = report.insights[index]
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.indigo)
                                Text(text)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(16)
                .iPadReadableContent(maxWidth: 720)
            }
            .navigationTitle(L("Weekly Report"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label(L("Назад"), systemImage: "chevron.left")
                    }
                }
            }
        }
    }

    private var overloadDeltaSummary: String {
        if report.previousOverloadIndex > 0, report.overloadIndex >= report.previousOverloadIndex * 2 {
            return L("Давление удвоилось по сравнению с прошлой неделей")
        }
        if report.overloadDeltaPercent > 0 {
            return String(format: L("Давление выросло на %d%% к прошлой неделе"), abs(report.overloadDeltaPercent))
        }
        if report.overloadDeltaPercent < 0 {
            return String(format: L("Давление снизилось на %d%% к прошлой неделе"), abs(report.overloadDeltaPercent))
        }
        return L("Давление без изменений относительно прошлой недели")
    }

    private func metricCard(title: String, value: String, tint: Color, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(emphasized ? tint.opacity(0.65) : Color.clear, lineWidth: emphasized ? 1.5 : 0)
        )
    }
}
