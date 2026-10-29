import SwiftUI

struct OnboardingView: View {
    let model: AppModel

    var body: some View {
        CenteredScroll {
            VStack(spacing: 24) {
                HStack(spacing: 10) {
                    LeafMark(size: 30)
                    Text("ふと")
                        .font(.largeTitle.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }

                VStack(spacing: 12) {
                    Text("使う前に、ひと呼吸。")
                        .font(.title2.weight(.medium))
                    Text("何に使いたいか確かめてから、自分で選ぶためのアプリです。")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .lineSpacing(5)
                }

                VStack(spacing: 12) {
                    Button("実機で設定する") { model.completeOnboarding(mode: .device) }
                        .buttonStyle(FutoButtonStyle())
                    Button("デモで試す") { model.completeOnboarding(mode: .demo) }
                        .buttonStyle(FutoButtonStyle(prominent: false))
                }
                .padding(.top, 8)

                Text("デモでは、実際のアプリは制限されません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
