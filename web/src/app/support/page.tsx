import { cookies } from "next/headers";
import { Bi } from "@/components/Bi";
import { SupportActions } from "@/components/SupportActions";
import { activeWebPlan, WEB_PRICES, type WebPlan } from "@/lib/billing";
import { isConfigured } from "@/lib/firebase";
import { billingConfig } from "@/lib/stripe";
import { userRef } from "@/lib/users";
import { readSessionUid, SESSION_COOKIE, webAuthConfig } from "@/lib/webSession";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const PLANS: { id: WebPlan; ja: string; en: string; descJa: string[]; descEn: string }[] = [
  { id: "adFree", ja: "広告なし", en: "No ads", descJa: ["待機の時間を、より静かに"], descEn: "A calmer time while you wait" },
  { id: "support", ja: "ふとを応援", en: "Support Futo", descJa: ["ふとの開発と運営を支える", "広告非表示も含む"], descEn: "Supports Futo's development and running, includes no ads" },
];

const STATUS_TEXT: Record<string, { ja: string; en: string }> = {
  success: { ja: "ありがとうございます　反映まで、少しかかることがあります", en: "Thank you, it may take a moment to take effect" },
  failed: { ja: "ログインできませんでした　もう一度お試しください", en: "Couldn't log in, please try again" },
  unavailable: { ja: "現在、利用できません", en: "Not available right now" },
};

/** ふとを応援（Web）。ログインして加入すると、アプリでも、同じアカウントで広告が出なくなる。 */
export default async function SupportPage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  const { status } = await searchParams;
  const billing = billingConfig() !== null;
  const login = webAuthConfig() !== null && isConfigured();
  const uid = login ? await readSessionUid((await cookies()).get(SESSION_COOKIE)?.value) : null;
  const data = uid ? (await userRef(uid).get()).data() : undefined;
  const current = activeWebPlan(data as { webPlan?: never });
  const notice = status ? STATUS_TEXT[status] : undefined;

  return (
    <>
      <div className="card">
        <p className="who"><Bi ja="ふとを応援" en="Support Futo" /></p>
        <p className="muted"><Bi ja="どちらも任意です　基本の機能は、ずっと無料です" en="Both are optional, the basic features stay free" /></p>
        <p className="muted"><Bi ja="アプリで同じ Google アカウントにログインすると、広告が表示されなくなります" en="Log in with the same Google account in the app and ads are hidden" /></p>
      </div>

      {notice && <p className="notice"><Bi ja={notice.ja} en={notice.en} /></p>}

      {!billing || !login ? (
        <div className="card unavailable">
          <h2><Bi ja="準備中です" en="Coming soon" /></h2>
        </div>
      ) : !uid ? (
        <div className="card">
          <p><Bi ja="加入するには、Google でログインします" en="Log in with Google to subscribe" /></p>
          <div className="btns"><a className="btn" href="/api/web/login"><Bi ja="Google でログイン" en="Log in with Google" /></a></div>
        </div>
      ) : (
        <>
          {PLANS.map((plan) => (
            <div className="card" key={plan.id}>
              <div className="row">
                <strong><Bi ja={plan.ja} en={plan.en} /></strong>
                <span><Bi ja={`${WEB_PRICES[plan.id]}円 / 月`} en={`¥${WEB_PRICES[plan.id]} / month`} /></span>
              </div>
              <p className="muted"><Bi ja={plan.descJa.join("　")} en={plan.descEn} /></p>
              <div className="btns">
                {current === plan.id ? (
                  <strong className="muted"><Bi ja="加入中" en="Subscribed" /></strong>
                ) : current ? null : (
                  <SupportActions mode="subscribe" plan={plan.id} />
                )}
              </div>
            </div>
          ))}
          <div className="card">
            <div className="btns">
              {current && <SupportActions mode="manage" />}
              <SupportActions mode="logout" />
            </div>
            <p className="muted"><Bi ja="2つのプランは、同時には加入できません　変更や解約は、契約の管理から" en="You can't subscribe to both at once, change or cancel from Manage subscription" /></p>
          </div>
        </>
      )}

      <p className="muted" style={{ textAlign: "center" }}>
        <a href="/legal"><Bi ja="特定商取引法に基づく表記" en="Legal notice (Japan)" /></a>
      </p>
    </>
  );
}
