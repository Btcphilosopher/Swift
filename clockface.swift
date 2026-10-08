import SwiftUI
import WidgetKit

// ============================================================
// 中文时钟表盘 Widget
// ============================================================

struct 时钟条目: TimelineEntry {
    let date: Date
}

// MARK: - Provider

struct 时钟Provider: TimelineProvider {

    func placeholder(in context: Context) -> 时钟条目 {
        时钟条目(date: Date())
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (时钟条目) -> Void
    ) {
        completion(
            时钟条目(date: Date())
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<时钟条目>) -> Void
    ) {

        let 当前时间 = Date()
        var entries: [时钟条目] = []

        // 每分钟更新一次
        for 分钟 in 0..<60 {

            let 日期 = Calendar.current.date(
                byAdding: .minute,
                value: 分钟,
                to: 当前时间
            )!

            entries.append(
                时钟条目(date: 日期)
            )
        }

        let 时间线 = Timeline(
            entries: entries,
            policy: .atEnd
        )

        completion(时间线)
    }
}


// MARK: - 表盘

struct 中文表盘: View {

    let date: Date

    private var 日历: Calendar {
        Calendar.current
    }

    private var 时: Int {
        日历.component(.hour, from: date)
    }

    private var 分: Int {
        日历.component(.minute, from: date)
    }

    private var 秒: Int {
        日历.component(.second, from: date)
    }

    var body: some View {

        GeometryReader { geometry in

            let 尺寸 = min(
                geometry.size.width,
                geometry.size.height
            )

            ZStack {

                // 表盘背景
                Circle()
                    .fill(.black)

                // 外圈
                Circle()
                    .stroke(
                        .white.opacity(0.25),
                        lineWidth: 2
                    )

                // 刻度
                ForEach(0..<60) { 刻度 in

                    Rectangle()
                        .fill(
                            刻度 % 5 == 0
                            ? .white
                            : .white.opacity(0.35)
                        )
                        .frame(
                            width: 刻度 % 5 == 0 ? 2 : 1,
                            height: 刻度 % 5 == 0
                                ? 尺寸 * 0.055
                                : 尺寸 * 0.025
                        )
                        .offset(
                            y: -尺寸 * 0.425
                        )
                        .rotationEffect(
                            .degrees(
                                Double(刻度) * 6
                            )
                        )
                }

                // 中文数字
                VStack(spacing: 2) {

                    Text("十二")
                        .font(.system(
                            size: 尺寸 * 0.075,
                            weight: .medium,
                            design: .serif
                        ))

                    Spacer()
                }
                .padding(.top, 尺寸 * 0.095)

                // 小时针
                指针(
                    长度: 尺寸 * 0.24,
                    宽度: 尺寸 * 0.018
                )
                .rotationEffect(
                    .degrees(
                        Double(时 % 12) * 30
                        + Double(分) * 0.5
                        - 180
                    )
                )

                // 分针
                指针(
                    长度: 尺寸 * 0.34,
                    宽度: 尺寸 * 0.012
                )
                .rotationEffect(
                    .degrees(
                        Double(分) * 6
                        - 180
                    )
                )

                // 秒针
                Rectangle()
                    .fill(.red)
                    .frame(
                        width: 1,
                        height: 尺寸 * 0.37
                    )
                    .offset(
                        y: -尺寸 * 0.185
                    )
                    .rotationEffect(
                        .degrees(
                            Double(秒) * 6
                            - 180
                        )
                    )

                // 中心轴
                Circle()
                    .fill(.white)
                    .frame(
                        width: 尺寸 * 0.035,
                        height: 尺寸 * 0.035
                    )

                // 中文日期
                VStack {

                    Spacer()

                    Text(中文日期(date))
                        .font(.system(
                            size: 尺寸 * 0.065,
                            weight: .medium,
                            design: .serif
                        ))
                        .padding(.bottom, 尺寸 * 0.12)
                }
            }
        }
    }


    private func 指针(
        长度: CGFloat,
        宽度: CGFloat
    ) -> some View {

        Rectangle()
            .fill(.white)
            .frame(
                width: 宽度,
                height: 长度
            )
            .offset(
                y: -长度 / 2
            )
    }


    private func 中文日期(
        _ date: Date
    ) -> String {

        let formatter = DateFormatter()

        formatter.locale = Locale(
            identifier: "zh_CN"
        )

        formatter.dateFormat = "M月d日"

        return formatter.string(
            from: date
        )
    }
}


// MARK: - Widget

struct 中文时钟Widget: Widget {

    let kind = "中文时钟Widget"

    var body: some WidgetConfiguration {

        StaticConfiguration(
            kind: kind,
            provider: 时钟Provider()
        ) { entry in

            中文表盘(
                date: entry.date
            )
            .containerBackground(
                .black,
                for: .widget
            )
        }
        .configurationDisplayName("中文时钟")
        .description("传统机械表盘风格的中文时钟")
        .supportedFamilies([
            .systemSmall,
            .systemMedium
        ])
    }
}


// MARK: - Widget Bundle

@main
struct 中文时钟WidgetBundle: WidgetBundle {

    var body: some Widget {
        中文时钟Widget()
    }
}

