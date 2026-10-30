import SwiftUI

/// 起動時に約1秒見せるスプラッシュ。OSの起動画面（LaunchScreen.storyboard）と同じ画像なので、切れ目なくつながる。
/// 画像は縦長の1枚。iPhoneの縦では画面いっぱいに、横長の画面（iPadの横など）では、拡大せずに中央に収め、左右は同じ緑の地につなげる。
struct SplashView: View {
    /// 画像の縁の色に近い緑（横長のとき、左右の地に使う）
    private let base = Color(red: 28 / 255, green: 116 / 255, blue: 108 / 255)

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width / max(geo.size.height, 1) > 0.6
            ZStack {
                base
                if wide {
                    Image("Splash")
                        .resizable()
                        .scaledToFit()
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                               .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing))
                } else {
                    Image("Splash")
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
