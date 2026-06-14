/**
 * WhatsApp template catalogue (mirrors backend/app/docs/whatsapp_templates_catalogue.md).
 * Used by the Admin > WhatsApp Templates preview page.
 *
 * Each entry represents a base template that ships in BOTH languages (_sw + _en).
 * Placeholders are positional ({{1}}..{{N}}) matched to the named keys in
 * `placeholders` in order.
 */

export type TemplateButton = {
  label_sw: string;
  label_en: string;
  prefix: string;
  suffixKey: string; // sample data key for the {{1}} suffix
};

export type WaTemplate = {
  num: string;
  key: string; // e.g. nuru_guest_invitation
  name_sw: string;
  name_en: string;
  status: "new" | "existing" | "updated";
  category: "UTILITY" | "AUTHENTICATION";
  body_sw: string;
  body_en: string;
  placeholders: string[]; // ordered, length = number of {{N}}
  button?: TemplateButton;
  backendRef: string;
};

export const SAMPLE: Record<string, string> = {
  guest_name: "Asha Mwinyi",
  organizer_name: "Juma Kibwana",
  organiser_name: "Juma Kibwana",
  event_name: "Harusi ya Asha & Juma",
  event_date_and_time: "Jumamosi, 15 Machi 2026, 16:00",
  event_venue: "Serena Hotel, Dar es Salaam",
  member_name: "Neema Lyimo",
  role: "Katibu wa Kamati",
  custom_message: "Karibu sana.",
  new_user_name: "Baraka Mushi",
  registered_by_name: "Juma Kibwana",
  password: "Nuru2026!",
  meeting_title: "Kikao cha Kamati",
  scheduled_date_and_time: "Jumatano, 4 Machi 2026, 19:00",
  meeting_redirect_token: "mtk_8s3f2hq91zP",
  contributor_name: "Asha Mwinyi",
  currency: "TZS",
  amount: "50,000",
  amount_text: "TZS 50,000",
  recorder_name: "Juma Kibwana",
  total_paid: "150,000",
  total_paid_text: "TZS 150,000",
  balance: "100,000",
  balance_text: "TZS 100,000",
  organizer_phone: "+255712345678",
  target: "200,000",
  target_text: "TZS 200,000",
  total_target: "300,000",
  total_target_text: "TZS 300,000",
  increase: "100,000",
  increase_text: "TZS 100,000",
  pledge_amount: "200,000",
  pledge_amount_text: "TZS 200,000",
  transaction_code: "NRU-9F3K2",
  payer_name: "Asha Mwinyi",
  purpose: "Harusi ya Asha & Juma",
  payee_label: "pochi yako ya Nuru",
  method: "M-Pesa",
  target_label: "Harusi ya Asha & Juma",
  payer_phone: "+255712345678",
  vendor_name: "DJ Mark Sound",
  vendor_first_name: "Mark",
  client_name: "Juma Kibwana",
  service_title: "Sauti na DJ",
  service_amount: "500,000",
  service_amount_text: "TZS 500,000",
  code: "482913",
  minutes: "10",
  requester_first_name: "Juma",
  service_name: "Sauti na DJ",
  recipient_first_name: "Neema",
  provider_name: "Mark",
  category: "Chakula",
  // Button suffixes
  rsvp_code: "A1B2C3",
  share_token: "tok_abc123",
  receipt_path: "tok_abc123/r/NRU-9F3K2",
  setup_token: "Zk3p9XqLm2Vb6tN8rH4sJ",
};

const SIGN = "\n\nPlan Smarter. Celebrate Better.";

export const TEMPLATES: WaTemplate[] = [
  {
    num: "1/2",
    key: "nuru_guest_invitation",
    name_sw: "nuru_guest_invitation_sw",
    name_en: "nuru_guest_invitation_en",
    status: "existing",
    category: "UTILITY",
    body_sw:
      "MWALIKO\n\nHabari {{1}},\n\n{{2}} amekualika kwenye {{3}}.\n\nTarehe: {{4}}\nMahali: {{5}}\n\nTafadhali thibitisha uwepo wako kupitia kitufe hapa chini." + SIGN,
    body_en:
      "INVITATION\n\nHello {{1}},\n\n{{2}} has invited you to {{3}}.\n\nWhen: {{4}}\nWhere: {{5}}\n\nPlease confirm your attendance using the button below." + SIGN,
    placeholders: ["guest_name", "organizer_name", "event_name", "event_date_and_time", "event_venue"],
    button: { label_sw: "Thibitisha Mwaliko", label_en: "Confirm Invitation", prefix: "https://nuru.tz/rsvp/", suffixKey: "rsvp_code" },
    backendRef: "utils/whatsapp.py::wa_guest_invited; utils/sms.py::sms_guest_added",
  },
  {
    num: "3/4",
    key: "nuru_committee_invite",
    name_sw: "nuru_committee_invite_sw",
    name_en: "nuru_committee_invite_en",
    status: "new",
    category: "UTILITY",
    body_sw:
      "KAMATI YA TUKIO\n\nHabari {{1}}, {{2}} amekuongeza kama {{3}} kwenye {{4}}. {{5}} Fungua Nuru kuona majukumu yako na taarifa muhimu za tukio." + SIGN,
    body_en:
      "EVENT COMMITTEE\n\nHello {{1}}, {{2}} has added you as {{3}} for {{4}}. {{5}} Open Nuru to see your tasks and important event updates." + SIGN,
    placeholders: ["member_name", "organizer_name", "role", "event_name", "custom_message"],
    backendRef: "utils/sms.py::sms_committee_invite",
  },
  {
    num: "5/6",
    key: "nuru_welcome_registered_by",
    name_sw: "nuru_welcome_registered_by_sw",
    name_en: "nuru_welcome_registered_by_en",
    status: "updated",
    category: "UTILITY",
    body_sw:
      "KARIBU NURU\n\nHabari {{1}},\n\n{{2}} amekusajiri kwenye Nuru.\n\nAkaunti yako imeundwa kikamilifu. Bonyeza kitufe hapa chini kuweka nenosiri lako kwa usalama na kuingia kwenye Nuru." + SIGN,
    body_en:
      "WELCOME TO NURU\n\nHello {{1}},\n\n{{2}} has added you to Nuru.\n\nYour account is ready. Tap the button below to securely set your password and sign in to Nuru." + SIGN,
    placeholders: ["new_user_name", "registered_by_name"],
    button: { label_sw: "Weka Nenosiri", label_en: "Set Password", prefix: "https://nuru.tz/set-password/", suffixKey: "setup_token" },
    backendRef: "api/routes/users.py (inline registration) + utils/account_setup.create_setup_token + utils/whatsapp.wa_welcome_registered_by",
  },
  {
    num: "7/8",
    key: "nuru_meeting_invitation",
    name_sw: "nuru_meeting_invitation_sw",
    name_en: "nuru_meeting_invitation_en",
    status: "existing",
    category: "UTILITY",
    body_sw:
      "MWALIKO WA KIKAO\n\nUmealikwa kwenye kikao cha {{1}} kwa ajili ya {{2}}.\n\nKikao kimepangwa kufanyika {{3}}.\n\nBonyeza kitufe hapa chini kujiunga." + SIGN,
    body_en:
      "MEETING INVITATION\n\nYou have been invited to {{1}} for {{2}}.\n\nThe meeting is scheduled for {{3}}.\n\nTap the button below to join." + SIGN,
    placeholders: ["meeting_title", "event_name", "scheduled_date_and_time"],
    button: { label_sw: "Jiunge na Kikao", label_en: "Join Meeting", prefix: "https://nuru.tz/m/", suffixKey: "meeting_redirect_token" },
    backendRef: "utils/whatsapp.py::wa_meeting_invitation",
  },


  {
    num: "9/10",
    key: "nuru_contribution_recorded_with_balance",
    name_sw: "nuru_contribution_recorded_with_balance_sw",
    name_en: "nuru_contribution_recorded_with_balance_en",
    status: "existing",
    category: "UTILITY",
    body_sw:
      "MALIPO YAMEPOKELEWA\n\nHabari {{1}},\n\nTumepokea mchango wako wa {{2}} kutoka kwa {{3}} kwa ajili ya {{4}}.\n\nJumla uliyolipa: {{5}}\nSalio lililobaki: {{6}}\n\nKwa msaada, mpigie mratibu wa tukio kupitia {{7}}." + SIGN,
    body_en:
      "PAYMENT RECEIVED\n\nHello {{1}},\n\nWe have received your contribution of {{2}} from {{3}} for {{4}}.\n\nTotal paid: {{5}}\nRemaining balance: {{6}}\n\nFor help, call the organiser on {{7}}." + SIGN,
    placeholders: ["contributor_name", "amount_text", "recorder_name", "event_name", "total_paid_text", "balance_text", "organizer_phone"],
    backendRef: "utils/whatsapp.py::wa_contribution_recorded",
  },
  {
    num: "11/12",
    key: "nuru_contribution_recorded_pledge_complete",
    name_sw: "nuru_contribution_recorded_pledge_complete_sw",
    name_en: "nuru_contribution_recorded_pledge_complete_en",
    status: "new",
    category: "UTILITY",
    body_sw:
      "AHADI IMEKAMILIKA\n\nHabari {{1}},\n\nTumepokea mchango wako wa {{2}} kutoka kwa {{3}} kwa ajili ya {{4}}.\n\nHongera kwa kukamilisha ahadi yako ya {{5}}. Asante kwa mchango wako muhimu.\n\nKwa msaada, mpigie mratibu wa tukio kupitia {{6}}." + SIGN,
    body_en:
      "PLEDGE COMPLETED\n\nHello {{1}},\n\nWe have received your contribution of {{2}} from {{3}} for {{4}}.\n\nCongratulations on completing your pledge of {{5}}. Thank you for your support.\n\nFor help, call the organiser on {{6}}." + SIGN,
    placeholders: ["contributor_name", "amount_text", "recorder_name", "event_name", "target_text", "organizer_phone"],
    backendRef: "utils/whatsapp.py::wa_contribution_recorded (pledge-completed)",
  },
  {
    num: "13/14",
    key: "nuru_contribution_target_set",
    name_sw: "nuru_contribution_target_set_sw",
    name_en: "nuru_contribution_target_set_en",
    status: "new",
    category: "UTILITY",
    body_sw:
      "AHADI YA MCHANGO\n\nHabari {{1}}, tumepokea ahadi yako ya mchango kwa ajili ya {{2}} kiasi cha {{3}}. Asante kwa ukarimu wako. Kwa msaada, mpigie mratibu wa tukio kupitia {{4}}." + SIGN,
    body_en:
      "CONTRIBUTION PLEDGE\n\nHello {{1}}, we have received your contribution pledge for {{2}} amounting to {{3}}. Thank you for your generosity. For help, call the event organiser on {{4}}." + SIGN,
    placeholders: ["contributor_name", "event_name", "target_text", "organizer_phone"],
    backendRef: "utils/sms.py::sms_contribution_target_set",
  },
  {
    num: "14a/14b",
    key: "nuru_contribution_target_updated",
    name_sw: "nuru_contribution_target_updated_sw",
    name_en: "nuru_contribution_target_updated_en",
    status: "new",
    category: "UTILITY",
    body_sw:
      "AHADI YA MCHANGO\n\nHabari {{1}}, tumepokea ongezeko la ahadi yako ya mchango kwa ajili ya {{2}} kiasi cha {{3}}. Jumla ya ahadi yako ni {{4}}. Asante kwa ukarimu wako. Kwa msaada, mpigie mratibu wa tukio kupitia {{5}}." + SIGN,
    body_en:
      "CONTRIBUTION PLEDGE\n\nHello {{1}}, we have received an increase to your contribution pledge for {{2}} amounting to {{3}}. Your total pledge is now {{4}}. Thank you for your generosity. For help, call the event organiser on {{5}}." + SIGN,
    placeholders: ["contributor_name", "event_name", "increase_text", "total_target_text", "organizer_phone"],
    backendRef: "utils/sms.py::sms_contribution_target_updated",
  },
  {
    num: "15/16",
    key: "nuru_contribution_thank_you",
    name_sw: "nuru_contribution_thank_you_sw",
    name_en: "nuru_contribution_thank_you_en",
    status: "existing",
    category: "UTILITY",
    body_sw:
      "ASANTE KWA MCHANGO\n\nHabari {{1}}, asante kwa mchango wako wa {{2}} kwa ajili ya {{3}}. {{4}} Kwa msaada, mpigie mratibu wa tukio kupitia {{5}}." + SIGN,
    body_en:
      "THANK YOU\n\nHello {{1}}, thank you for your contribution of {{2}} towards {{3}}. {{4}} For help, call the organiser on {{5}}." + SIGN,
    placeholders: ["contributor_name", "amount_text", "event_name", "custom_message", "organizer_phone"],
    backendRef: "utils/whatsapp.py::wa_thank_you",
  },
  {
    num: "17/18",
    key: "nuru_guest_contribution_invite",
    name_sw: "nuru_guest_contribution_invite_sw",
    name_en: "nuru_guest_contribution_invite_en",
    status: "new",
    category: "UTILITY",
    body_sw:
      "MWALIKO WA KUCHANGIA\n\nHabari {{1}},\n\n{{2}} anakualika kuchangia {{3}}.\n\nKiasi cha ahadi: {{4}}\n\nBonyeza kitufe hapa chini kulipa kwa usalama kupitia Nuru." + SIGN,
    body_en:
      "CONTRIBUTION INVITATION\n\nHello {{1}},\n\n{{2}} has invited you to contribute towards {{3}}.\n\nPledged amount: {{4}}\n\nTap the button below to pay securely through Nuru." + SIGN,
    placeholders: ["contributor_name", "organiser_name", "event_name", "pledge_amount_text"],
    button: { label_sw: "Lipa Sasa", label_en: "Pay Now", prefix: "https://nuru.tz/c/", suffixKey: "share_token" },
    backendRef: "utils/whatsapp.py::wa_contribution_target_set (guest)",
  },
  {
    num: "19/20",
    key: "nuru_guest_contribution_receipt",
    name_sw: "nuru_guest_contribution_receipt_sw",
    name_en: "nuru_guest_contribution_receipt_en",
    status: "updated",
    category: "UTILITY",
    body_sw:
      "MALIPO YAMEFANIKIWA\n\nHabari {{1}}, asante.\n\nMalipo yako ya {{2}} kwa ajili ya {{3}} yamefanikiwa.\n\nJumla uliyolipa: {{4}}\nSalio lililobaki: {{5}}\nKumbukumbu ya muamala: {{6}}\n\nBonyeza kitufe hapa chini kuona risiti yako." + SIGN,
    body_en:
      "PAYMENT SUCCESSFUL\n\nHello {{1}}, thank you.\n\nYour payment of {{2}} for {{3}} was successful.\n\nTotal paid: {{4}}\nRemaining balance: {{5}}\nTransaction reference: {{6}}\n\nTap the button below to view your receipt." + SIGN,
    placeholders: ["contributor_name", "amount_text", "event_name", "total_paid_text", "balance_text", "transaction_code"],
    button: { label_sw: "Ona Risiti", label_en: "View Receipt", prefix: "https://nuru.tz/c/", suffixKey: "receipt_path" },
    backendRef: "utils/sms.py::sms_guest_contribution_receipt",
  },
  {
    num: "21/22",
    key: "nuru_payment_received_generic",
    name_sw: "nuru_payment_received_generic_sw",
    name_en: "nuru_payment_received_generic_en",
    status: "new",
    category: "UTILITY",
    body_sw:
      "MALIPO YAMEINGIA\n\nUmepokea {{1}} kutoka kwa {{2}} kwa ajili ya {{3}}. Kumbukumbu ya muamala: {{4}}." + SIGN,
    body_en:
      "PAYMENT RECEIVED\n\nYou have received {{1}} from {{2}} for {{3}}. Transaction reference: {{4}}." + SIGN,
    placeholders: ["amount_text", "payer_name", "purpose", "transaction_code"],
    backendRef: "utils/sms.py::sms_payment_received_generic",
  },
  {
    num: "23/24",
    key: "nuru_payment_confirmation_payer",
    name_sw: "nuru_payment_confirmation_payer_sw",
    name_en: "nuru_payment_confirmation_payer_en",
    status: "new",
    category: "UTILITY",
    body_sw:
      "MALIPO YAMEFANIKIWA\n\nHabari {{1}}, malipo yako ya {{2}} kwa ajili ya {{3}} yamefanikiwa. Kumbukumbu ya muamala: {{4}}. Tafadhali hifadhi ujumbe huu kwa kumbukumbu zako." + SIGN,
    body_en:
      "PAYMENT SUCCESSFUL\n\nHello {{1}}, your payment of {{2}} for {{3}} was successful. Transaction reference: {{4}}. Please keep this message for your records." + SIGN,
    placeholders: ["payer_name", "amount_text", "purpose", "transaction_code"],
    backendRef: "utils/sms.py::sms_payment_confirmation_payer",
  },
  {
    num: "25/26",
    key: "nuru_organiser_contribution_received",
    name_sw: "nuru_organiser_contribution_received_sw",
    name_en: "nuru_organiser_contribution_received_en",
    status: "new",
    category: "UTILITY",
    body_sw:
      "MCHANGO UMEPOKELEWA\n\nHabari {{1}}, umepokea mchango wa {{2}} kutoka kwa {{3}} kwa ajili ya {{4}}. Kumbukumbu ya muamala: {{5}}." + SIGN,
    body_en:
      "CONTRIBUTION RECEIVED\n\nHello {{1}}, you have received a contribution of {{2}} from {{3}} for {{4}}. Transaction reference: {{5}}." + SIGN,
    placeholders: ["organizer_name", "amount_text", "contributor_name", "event_name", "transaction_code"],
    backendRef: "utils/sms.py::sms_organiser_contribution_received",
  },
  {
    num: "27/28",
    key: "nuru_vendor_booking_paid",
    name_sw: "nuru_vendor_booking_paid_sw",
    name_en: "nuru_vendor_booking_paid_en",
    status: "updated",
    category: "UTILITY",
    body_sw:
      "MALIPO YA HUDUMA\n\nHabari {{1}},\n\nUmepokea malipo ya {{2}} kutoka kwa {{3}} kwa ajili ya huduma yako {{4}}.\n\nKiasi cha huduma kilichokubaliwa: {{5}}\nJumla uliyolipwa: {{6}}\nSalio lililobaki: {{7}}\n\nKumbukumbu ya muamala: {{8}}" + SIGN,
    body_en:
      "SERVICE PAYMENT RECEIVED\n\nHello {{1}},\n\nYou have received {{2}} from {{3}} for your service {{4}}.\n\nAgreed service amount: {{5}}\nReceived so far: {{6}}\nRemaining balance: {{7}}\n\nTransaction reference: {{8}}" + SIGN,
    placeholders: ["vendor_name", "amount_text", "client_name", "service_title", "service_amount_text", "total_paid_text", "balance_text", "transaction_code"],
    backendRef: "utils/sms.py::sms_vendor_booking_paid",
  },
  {
    num: "29/30",
    key: "nuru_admin_payment_alert",
    name_sw: "nuru_admin_payment_alert_sw",
    name_en: "nuru_admin_payment_alert_en",
    status: "new",
    category: "UTILITY",
    body_sw:
      "[Nuru Admin]\n\n[Nuru Admin] {{1}} zimepokelewa kupitia {{2}} kwa ajili ya {{3}} {{4}}. Mlipaji: {{5}} ({{6}}). Ref: {{7}}." + SIGN,
    body_en:
      "[Nuru Admin]\n\n[Nuru Admin] {{1}} received via {{2}} for {{3}} {{4}}. Payer: {{5}} ({{6}}). Ref: {{7}}." + SIGN,
    placeholders: ["amount_text", "method", "purpose", "target_label", "payer_name", "payer_phone", "transaction_code"],
    backendRef: "utils/sms.py::sms_admin_payment_alert",
  },
  {
    num: "31/32",
    key: "nuru_vendor_otp_claim",
    name_sw: "nuru_vendor_otp_claim_sw",
    name_en: "nuru_vendor_otp_claim_en",
    status: "new",
    category: "AUTHENTICATION",
    body_sw:
      "Meta AUTHENTICATION template · Copy Code button, security recommendation enabled, expiration 10 minutes.\n\nPlaceholders: {{1}} = code only.\nWhatsApp payload sends only the OTP code; no vendor name, organiser, amount, service, event, or minutes.",
    body_en:
      "Meta AUTHENTICATION template · Copy Code button, security recommendation enabled, expiration 10 minutes.\n\nPlaceholders: {{1}} = code only.\nWhatsApp payload sends only the OTP code; no vendor name, organiser, amount, service, event, or minutes.",
    placeholders: ["code"],
    backendRef: "api/routes/offline_payments.py (WA action vendor_otp_claim) - utils/sms.py::sms_vendor_otp_claim (SMS unchanged)",
  },
  {
    num: "33/34",
    key: "nuru_vendor_otp_resend",
    name_sw: "nuru_vendor_otp_resend_sw",
    name_en: "nuru_vendor_otp_resend_en",
    status: "new",
    category: "AUTHENTICATION",
    body_sw:
      "Meta AUTHENTICATION template · Copy Code button, security recommendation enabled, expiration 10 minutes.\n\nPlaceholders: {{1}} = code only.\nWhatsApp payload sends only the OTP code; no vendor name, organiser, amount, service, event, or minutes.",
    body_en:
      "Meta AUTHENTICATION template · Copy Code button, security recommendation enabled, expiration 10 minutes.\n\nPlaceholders: {{1}} = code only.\nWhatsApp payload sends only the OTP code; no vendor name, organiser, amount, service, event, or minutes.",
    placeholders: ["code"],
    backendRef: "api/routes/offline_payments.py (WA action vendor_otp_resend) - utils/sms.py::sms_vendor_otp_resend (SMS unchanged)",
  },
  {
    num: "35/36",
    key: "nuru_vendor_confirmation_receipt",
    name_sw: "nuru_vendor_confirmation_receipt_sw",
    name_en: "nuru_vendor_confirmation_receipt_en",
    status: "new",
    category: "UTILITY",
    body_sw:
      "MALIPO YAMETHIBITISHWA\n\nHabari {{1}}, umethibitisha kupokea {{2}} kutoka kwa {{3}} kwa ajili ya {{4}}. Kiasi kilichobaki ni {{5}}." + SIGN,
    body_en:
      "PAYMENT CONFIRMED\n\nHello {{1}}, you have confirmed receiving {{2}} from {{3}} for {{4}}. Remaining amount: {{5}}." + SIGN,
    placeholders: ["vendor_first_name", "amount_text", "organiser_name", "event_name", "balance_text"],
    backendRef: "utils/sms.py::sms_vendor_confirmation_receipt",
  },
  {
    num: "37/38",
    key: "nuru_vendor_confirmation_receipt_full",
    name_sw: "nuru_vendor_confirmation_receipt_full_sw",
    name_en: "nuru_vendor_confirmation_receipt_full_en",
    status: "new",
    category: "UTILITY",
    body_sw:
      "MALIPO YAMEKAMILIKA\n\nHabari {{1}}, umethibitisha kupokea {{2}} kutoka kwa {{3}} kwa ajili ya {{4}}. Sasa umelipwa kikamilifu." + SIGN,
    body_en:
      "PAYMENT COMPLETED\n\nHello {{1}}, you have confirmed receiving {{2}} from {{3}} for {{4}}. You have now been paid in full." + SIGN,
    placeholders: ["vendor_first_name", "amount_text", "organiser_name", "event_name"],
    backendRef: "utils/sms.py::sms_vendor_confirmation_receipt_full",
  },
  {
    num: "39/40",
    key: "nuru_organiser_committee_vendor_confirmed",
    name_sw: "nuru_organiser_committee_vendor_confirmed_sw",
    name_en: "nuru_organiser_committee_vendor_confirmed_en",
    status: "new",
    category: "UTILITY",
    body_sw:
      "MALIPO YAMETHIBITISHWA\n\nHabari {{1}}, {{2}} amethibitisha kupokea {{3}} kutoka kwa {{4}} kwa ajili ya {{5}}. Kiasi kilichobaki ni {{6}}. Fungua Nuru kuona taarifa kamili." + SIGN,
    body_en:
      "PAYMENT CONFIRMED\n\nHello {{1}}, {{2}} has confirmed receiving {{3}} from {{4}} for {{5}}. Remaining amount: {{6}}. Open Nuru for full details." + SIGN,
    placeholders: ["recipient_first_name", "vendor_name", "amount_text", "organiser_name", "event_name", "balance_text"],
    backendRef: "utils/sms.py::sms_organiser_committee_vendor_confirmed",
  },
  {
    num: "41/42",
    key: "nuru_expense_recorded",
    name_sw: "nuru_expense_recorded_sw",
    name_en: "nuru_expense_recorded_en",
    status: "existing",
    category: "UTILITY",
    body_sw:
      "GHARAMA MPYA\n\nHabari {{1}}, {{2}} amerekodi matumizi mapya ya {{3}} kwenye kipengele cha {{4}} kwa ajili ya {{5}}. Fungua Nuru kuona mchanganuo kamili." + SIGN,
    body_en:
      "NEW EXPENSE RECORDED\n\nHello {{1}}, {{2}} has recorded a new expense of {{3}} under {{4}} for {{5}}. Open Nuru to see the full breakdown." + SIGN,
    placeholders: ["recipient_first_name", "recorder_name", "amount_text", "category", "event_name"],
    backendRef: "utils/whatsapp.py::wa_expense_recorded",
  },
  {
    num: "43/44",
    key: "nuru_service_booking_notification",
    name_sw: "nuru_service_booking_notification_sw",
    name_en: "nuru_service_booking_notification_en",
    status: "existing",
    category: "UTILITY",
    body_sw:
      "OMBI JIPYA LA HUDUMA\n\nHabari {{1}}, {{2}} ameomba huduma yako \"{{3}}\" kwa ajili ya {{4}}. Fungua Nuru kukagua na kujibu ombi hili." + SIGN,
    body_en:
      "NEW SERVICE BOOKING\n\nHello {{1}}, {{2}} has booked your service \"{{3}}\" for {{4}}. Open Nuru to review and respond." + SIGN,
    placeholders: ["provider_name", "client_name", "service_name", "event_name"],
    backendRef: "utils/whatsapp.py::wa_booking_notification",
  },
  {
    num: "45/46",
    key: "nuru_booking_accepted",
    name_sw: "nuru_booking_accepted_sw",
    name_en: "nuru_booking_accepted_en",
    status: "existing",
    category: "UTILITY",
    body_sw:
      "OMBI LA HUDUMA LIMEKUBALIWA\n\nHabari {{1}}, habari njema. {{2}} amekubali ombi lako la huduma \"{{3}}\" kwa ajili ya {{4}}. Fungua Nuru kuona hatua zinazofuata." + SIGN,
    body_en:
      "BOOKING ACCEPTED\n\nHello {{1}}, good news. {{2}} has accepted your booking for \"{{3}}\" at {{4}}. Open Nuru to see the next steps." + SIGN,
    placeholders: ["requester_first_name", "vendor_name", "service_name", "event_name"],
    backendRef: "utils/whatsapp.py::wa_booking_accepted",
  },
];

/**
 * Replace {{N}} with the sample value for the placeholder at position N-1.
 * Returns the rendered string and a list of any placeholder indices that
 * could not be resolved (missing sample data or out-of-range index).
 */
export function renderTemplate(
  body: string,
  placeholders: string[],
  sample: Record<string, string>,
  overrides?: Record<string, string>,
): { rendered: string; missing: string[]; unresolved: number[] } {
  const missing: string[] = [];
  const unresolved: number[] = [];
  const data = { ...sample, ...(overrides || {}) };
  const rendered = body.replace(/\{\{(\d+)\}\}/g, (_m, n: string) => {
    const idx = parseInt(n, 10) - 1;
    const key = placeholders[idx];
    if (!key) {
      unresolved.push(idx + 1);
      return `{{${n}}}`;
    }
    const val = data[key];
    if (val === undefined || val === "") {
      if (!missing.includes(key)) missing.push(key);
      return `{{${n}:${key}}}`;
    }
    return val;
  });
  return { rendered, missing, unresolved };
}

/**
 * Validate every placeholder index referenced in body falls within
 * `placeholders.length`. Catches off-by-one mistakes in the catalogue.
 */
export function validatePlaceholders(t: WaTemplate): string[] {
  const issues: string[] = [];
  const collect = (body: string, lang: string) => {
    const indices = new Set<number>();
    const counts = new Map<number, number>();
    body.replace(/\{\{(\d+)\}\}/g, (_m, n: string) => {
      const index = parseInt(n, 10);
      indices.add(index);
      counts.set(index, (counts.get(index) || 0) + 1);
      return _m;
    });
    counts.forEach((count, i) => {
      if (count > 1) {
        issues.push(`[${lang}] {{${i}}} is reused ${count} times in body`);
      }
    });
    indices.forEach((i) => {
      if (i < 1 || i > t.placeholders.length) {
        issues.push(`[${lang}] {{${i}}} has no placeholder mapping (have ${t.placeholders.length})`);
      }
    });
    // Detect placeholders defined but never used
    t.placeholders.forEach((name, idx) => {
      if (!indices.has(idx + 1)) {
        issues.push(`[${lang}] mapping #${idx + 1} (${name}) defined but never used in body`);
      }
    });
  };
  collect(t.body_sw, "sw");
  collect(t.body_en, "en");
  return issues;
}
