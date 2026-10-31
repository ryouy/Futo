import { Bi } from "@/components/Bi";
import { WEB_PRICES } from "@/lib/billing";

export const dynamic = "force-dynamic";

/** 特定商取引法に基づく表記。販売者の情報は、環境変数から出す（リポジトリには入れない）。未設定の間は、決済を始めない。 */
export default function LegalPage() {
  const seller = process.env.LEGAL_SELLER_NAME;
  const address = process.env.LEGAL_ADDRESS;
  const contact = process.env.LEGAL_CONTACT;
  const rows: { ja: string; en: string; valueJa: React.ReactNode; valueEn?: React.ReactNode }[] = [
    { ja: "販売事業者", en: "Seller", valueJa: seller ?? "準備中", valueEn: seller ?? "Coming soon" },
    { ja: "所在地", en: "Address", valueJa: address ?? "準備中", valueEn: address ?? "Coming soon" },
    { ja: "連絡先", en: "Contact", valueJa: contact ?? "準備中", valueEn: contact ?? "Coming soon" },
    { ja: "販売価格", en: "Price", valueJa: `広告なし ${WEB_PRICES.adFree}円 / 月、ふとを応援 ${WEB_PRICES.support}円 / 月（税込）`, valueEn: `No ads ¥${WEB_PRICES.adFree} / month, Support Futo ¥${WEB_PRICES.support} / month (tax included)` },
    { ja: "支払い方法", en: "Payment", valueJa: "クレジットカードなど（Stripe の決済画面に表示されるもの）", valueEn: "Credit card and others shown on the Stripe checkout" },
    { ja: "支払い時期", en: "When you pay", valueJa: "加入時に、初回の料金。以後、1か月ごとに自動で更新されます", valueEn: "The first charge when you subscribe, then renewed automatically every month" },
    { ja: "提供時期", en: "Delivery", valueJa: "お支払いの完了後、すぐにご利用いただけます", valueEn: "Available right after payment" },
    { ja: "解約", en: "Cancellation", valueJa: "「ふとを応援」ページの「契約の管理」から、いつでも解約できます　解約すると、次の更新から料金はかかりません", valueEn: "Cancel anytime from Manage subscription, no charge from the next renewal" },
    { ja: "返金", en: "Refunds", valueJa: "サービスの性質上、お支払い済みの料金は、原則として返金しません", valueEn: "Because of the nature of the service, paid fees are generally non-refundable" },
    { ja: "動作環境", en: "Requirements", valueJa: "iPhone（iOS 17 以降）の「ふと」アプリ", valueEn: "The Futo app on iPhone (iOS 17 or later)" },
  ];
  return (
    <div className="card">
      <h2><Bi ja="特定商取引法に基づく表記" en="Legal notice (Japan)" /></h2>
      {rows.map((row) => (
        <div className="row" key={row.ja}>
          <span className="muted"><Bi ja={row.ja} en={row.en} /></span>
          <span style={{ textAlign: "right" }}><Bi ja={row.valueJa} en={row.valueEn ?? row.valueJa} /></span>
        </div>
      ))}
    </div>
  );
}
