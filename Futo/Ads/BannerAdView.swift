import GoogleMobileAds
import SwiftUI

/// アダプティブバナー1枚。読み込みの成否にかかわらず、枠の大きさは変えない（画面やボタンの位置が動かない）。
/// 画面から外れたら（`dismantleUIView`）、デリゲートを外し、バナーを取り除く（表示・更新を止める）。
struct BannerAdView: UIViewRepresentable {
    let size: AdSize

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(origin: .zero, size: size.size))
        container.backgroundColor = .clear
        let banner = BannerView(adSize: size)
        banner.adUnitID = AdsConfig.bannerUnitID
        banner.rootViewController = AdsService.topViewController()
        banner.delegate = context.coordinator
        banner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            banner.topAnchor.constraint(equalTo: container.topAnchor),
        ])
        context.coordinator.banner = banner
        banner.load(AdsService.makeRequest())
        return container
    }

    func updateUIView(_ view: UIView, context: Context) {}

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.banner?.delegate = nil
        coordinator.banner?.removeFromSuperview()
        coordinator.banner = nil
    }

    /// 読み込みの失敗・成功は、画面に何も影響させない（待機や解除の条件にもしない）。
    final class Coordinator: NSObject, BannerViewDelegate {
        var banner: BannerView?
    }
}

/// 待機の画面の最下部の広告枠。
/// 広告が使えるかは、画面が現れた時点で決め、画面にいる間は変えない（途中で枠が増減して、位置が動かないように）。
/// 前面でなくなる・画面を離れたら、バナーを取り除く。
struct WaitBannerSlot: View {
    @Environment(AdsService.self) private var ads
    @Environment(SupportStore.self) private var support
    @Environment(\.scenePhase) private var scenePhase
    /// 画面が現れた時点で、広告を要求してよいか
    @State private var eligible = false
    @State private var decided = false
    @State private var visible = true

    private var width: CGFloat { min(UIScreen.main.bounds.width, Layout.columnWidth) }

    var body: some View {
        let size = AdsService.bannerSize(width: width)
        Group {
            if decided, eligible {
                ZStack {
                    if visible, scenePhase == .active { BannerAdView(size: size) }
                }
                .frame(width: size.size.width, height: size.size.height)
                .accessibilityLabel(tr("広告"))
            }
        }
        .onAppear {
            if !decided {
                // 「広告なし」「ふとを応援」に加入していれば、広告は出さない（加入状況の確認前も出さない）
                eligible = support.entitlementsLoaded && !support.adsRemoved && ads.startIfAllowed()
                decided = true
            }
            visible = true
        }
        .onDisappear { visible = false }
    }
}
