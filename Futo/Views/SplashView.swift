import SwiftUI

/// 起動時に約1秒見せるスプラッシュ。OSの起動画面（LaunchScreen.storyboard）と同じ画像なので、切れ目なくつながる。
struct SplashView: View {
    var body: some View {
        Color(red: 25 / 255, green: 100 / 255, blue: 89 / 255)
            .overlay {
                Image("Splash")
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
