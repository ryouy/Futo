import SwiftUI

struct OnboardingView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    LeafMark(size: 30)
                    Text("ふと")
                        .font(.largeTitle.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.top, 24)

                Text("使う前に、ひと呼吸。")
                    .font(.title2.weight(.medium))

                VStack(alignment: .leading, spacing: 14) {
                    Text("スマホを開く前に、何に使いたいか確かめる。自分のペースで、使い方を選ぶためのアプリです。")
                    Text("この試作では、アプリの制限と、使う前の振り返りを試せます。一時解除は実機のみの試験機能です。")
                        .foregroundStyle(.secondary)
                }
                .lineSpacing(5)
                .card()

                VStack(spacing: 12) {
                    Button("実機で設定する") { model.completeOnboarding(mode: .device) }
                        .buttonStyle(FutoButtonStyle())
                    Button("デモで試す") { model.completeOnboarding(mode: .demo) }
                        .buttonStyle(FutoButtonStyle(prominent: false))
                }

                Text("デモでは、実際のアプリは制限されません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
