defmodule TedWeb.LegalPage do
  @moduledoc false

  @spec terms(keyword(), keyword()) :: String.t()
  def terms(legal, _opts \\ []) do
    page(
      "Terms of service",
      "The terms for using a hosted Ted instance.",
      legal,
      """
      <section><h2>The service</h2><p>Ted stores coaching profiles, daily check-ins, meals, workouts, and generated plans. A self-hosted installation is operated under the self-hoster's own terms.</p><p>The hosted service may be free or paid. A user will see the applicable price before any paid subscription begins.</p></section>
      <section><h2>Coaching, not healthcare</h2><p>Ted supports ordinary strength and nutrition habits. It does not diagnose illness, prescribe treatment, or replace a doctor, registered dietitian, physiotherapist, or another qualified professional. Stop an activity and seek appropriate care when pain, injury, disordered eating, pregnancy, or another health concern requires it.</p></section>
      <section><h2>Your records</h2><p>You keep ownership of the data you provide. You give the operator only the limited permission needed to store, process, transmit, and display it to operate Ted. You are responsible for accurate inputs, safe exercise choices, and maintaining any backup you require.</p></section>
      <section><h2>Your decision and responsibility</h2><p>Ted provides general educational guidance from the information you choose to record. You decide whether a suggestion is appropriate and safe for you and accept the risks of acting on it. To the fullest extent permitted by law, the operator and contributors are not liable for injury, loss, or another adverse outcome caused by relying on generated guidance, incomplete or inaccurate inputs, or use outside Ted's intended ordinary coaching scope. Nothing in these terms excludes or limits liability where the law does not permit that exclusion or limitation.</p></section>
      <section><h2>Acceptable use and availability</h2><p>Do not use Ted to break the law, infringe rights, distribute malware, evade rate limits, or interfere with other people. The early service has no guaranteed availability level and may change or stop after reasonable notice where practicable.</p></section>
      <section><h2>Provider</h2>#{provider_details(legal)}</section>
      """
    )
  end

  @spec privacy(keyword(), keyword()) :: String.t()
  def privacy(legal, _opts \\ []) do
    page(
      "Privacy policy",
      "What a hosted Ted instance processes and why.",
      legal,
      """
      <section><h2>Controller</h2>#{provider_details(legal)}<p>This notice covers the hosted instance run by that operator. A self-hoster is responsible for its own notice.</p></section>
      <section><h2>Data processed</h2><ul><li>Account and Telegram connection identifiers.</li><li>Coaching profiles, check-ins, weight, sleep, readiness, meal estimates, workouts, and notes.</li><li>Hashed authentication credentials, scopes, expiry times, and security events.</li><li>Network addresses, request times, routes, response status, and short-lived abuse-prevention counters.</li><li>Anonymous page and named interaction events when audience measurement is enabled. Coaching values, account identifiers, credentials, and form values are not included.</li></ul></section>
      <section><h2>Purpose and retention</h2><p>Account and coaching data are processed to provide the requested service. Security and request data are processed to prevent abuse, diagnose failures, and protect the service. Records are retained while the service is provided and then removed or anonymized when no longer needed, subject to backup and legal obligations.</p></section>
      <section><h2>Your rights</h2><p>Depending on the circumstances, you may request access, correction, deletion, restriction, portability, or object to processing. Send requests to <a href="mailto:#{email(legal)}">#{email(legal)}</a>. You may also complain to a competent data protection authority.</p></section>
      <section><h2>Automated decisions</h2><p>Ted's plan is a coaching recommendation. It does not make decisions with legal or similarly significant effects.</p></section>
      """
    )
  end

  @spec cookies(keyword(), keyword()) :: String.t()
  def cookies(legal, _opts \\ []) do
    page(
      "Cookie terms",
      "Browser storage and anonymous audience measurement.",
      legal,
      """
      <section><h2>No advertising cookies</h2><p>Ted does not run advertising technology or measure people across websites. Anonymous audience measurement may be enabled without sending account, coaching, credential, or form values.</p></section>
      <section><h2>Operational sessions</h2><p>The agent claim flow uses a secure browser session cookie. The web application programming interface and Model Context Protocol server use authorization headers. Third-party clients such as Telegram have their own storage and privacy behavior.</p></section>
      <section><h2>Questions</h2><p>Send questions to <a href="mailto:#{email(legal)}">#{email(legal)}</a>.</p></section>
      """
    )
  end

  defp page(title, introduction, legal, content) do
    TedWeb.Theme.inject("""
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><link rel="icon" href="/favicon.ico" sizes="any"><link rel="icon" type="image/png" sizes="32x32" href="/assets/favicon-32.png"><link rel="apple-touch-icon" sizes="180x180" href="/assets/apple-touch-icon.png"><title>#{escape(title)} · Ted</title><style>
    /* ted-theme */
    * { box-sizing: border-box; } body { margin: 0; background: var(--paper); color: var(--ink); font: var(--text-root)/var(--leading-normal) var(--serif); } a { color: var(--accent); } .legal { width: min(760px, calc(100% - 40px)); margin: 0 auto; } header, footer { display: flex; justify-content: space-between; gap: 24px; padding: 24px 0; border-bottom: 1px solid var(--rule); font: var(--text-small) var(--sans); } nav { display: flex; gap: 16px; } main { padding: 72px 0; } h1 { margin: 0 0 16px; font: 650 var(--text-heading)/1 var(--sans); letter-spacing: var(--tracking-heading); } .intro { color: var(--muted); font-size: var(--text-lead); } section { padding: 28px 0; border-top: 1px solid var(--rule); } h2 { margin-top: 0; font: 600 var(--text-subheading)/1.2 var(--sans); } address { font-style: normal; } footer { border-top: 1px solid var(--rule); border-bottom: 0; color: var(--muted); }
    </style></head><body><div class="legal"><header><a href="/"><strong>ted.</strong></a><nav><a href="/terms">Terms</a><a href="/privacy">Privacy</a><a href="/cookies">Cookies</a></nav></header><main><h1>#{escape(title)}</h1><p class="intro">#{escape(introduction)}</p>#{content}</main><footer><span>Effective #{escape(Keyword.fetch!(legal, :effective_date))}</span><a href="/">Return to Ted</a></footer></div></body></html>
    """)
  end

  defp provider_details(legal) do
    """
    <address><strong>#{escape(Keyword.fetch!(legal, :operator_name))}</strong><br>#{address(legal)}<br>Email: <a href="mailto:#{email(legal)}">#{email(legal)}</a></address>
    """
  end

  defp address(legal),
    do: legal |> Keyword.fetch!(:operator_address) |> escape() |> String.replace("\n", "<br>")

  defp email(legal), do: legal |> Keyword.fetch!(:contact_email) |> escape()

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
