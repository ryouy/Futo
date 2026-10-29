import SwiftUI

struct OnboardingView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("ふと")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.accent)
                Text("使う前に、ひと呼吸。")
                    .font(.title2.bold())
                Text("スマホを開く前に、何に使いたいか確かめる。自分のペースで、使い方を選ぶためのアプリです。")
                Text("この試作では、アプリの制限と、使う前の振り返りを試せます。一時解除はまだできません。")
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Button("実機で設定する") { model.completeOnboarding(mode: .device) }
                        .buttonStyle(FutoButtonStyle())
                    Button("デモで試す") { model.completeOnboarding(mode: .demo) }
                        .buttonStyle(FutoButtonStyle(prominent: false))
                }
                .padding(.top, 8)

                Text("「デモで試す」では、実際のアプリは制限されません。「実機で設定する」では、Screen Timeの許可と、制限するアプリの選択を行います。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
