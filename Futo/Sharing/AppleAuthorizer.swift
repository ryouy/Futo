import AuthenticationServices
import CryptoKit
import UIKit

/// 「Appleで続ける」の要求に使う nonce（乱数）。Appleには、ハッシュだけを渡し、Firebaseには、元の乱数を渡す。
enum AppleNonce {
    static func make() -> (raw: String, hashed: String) {
        let raw = PKCE.randomString(byteCount: 16)
        return (raw, SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined())
    }
}

/// ボタンを使わずに、Appleの認証を始める（アカウント削除の前の、本人の確認で使う）。
/// 結果は、await で受け取る。取りやめは `AuthError.cancelled`。
@MainActor
final class AppleAuthorizer: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var controller: ASAuthorizationController?

    struct Result { var identityToken: String; var rawNonce: String; var authorizationCode: String? }

    /// 求める情報は、なし（本人かどうかの確認だけ）。
    func authorize() async throws -> Result {
        let nonce = AppleNonce.make()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        request.nonce = nonce.hashed
        let authorization: ASAuthorization = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
        controller = nil
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8) else {
            throw AuthError.failed
        }
        return Result(identityToken: token, rawNonce: nonce.raw,
                      authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) })
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            continuation?.resume(returning: authorization)
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            let canceled = (error as? ASAuthorizationError)?.code == .canceled
            if !canceled { AuthLog.failure(stage: "apple.reauth", detail: AuthLog.describe(error)) }
            continuation?.resume(throwing: canceled ? AuthError.cancelled : AuthError.failed)
            continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
