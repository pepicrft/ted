defmodule TedWeb.Theme do
  @moduledoc """
  The shared stylesheet and navigation for Ted's browser surfaces.

  Ted keeps its browser interface deliberately small and document-like. Every
  element uses the same type size, while weight, spacing, rules, and a limited
  set of semantic colors provide hierarchy.
  """

  @styles ~S"""
  :root {
    color-scheme: light;
    --background: #ffffff;
    --surface: #f4f4f4;
    --text: #212529;
    --muted: #666666;
    --link: #007bff;
    --link-hover: #0056b3;
    --border: #888888;
    --border-soft: #dee2e6;
    --button: #e9ecef;
    --button-hover: #f8f9fa;
    --primary: #007bff;
    --primary-hover: #0069d9;
    --primary-border: #001933;
    --focus: #80bdff;
    --danger-background: #f8d7da;
    --danger-text: #721c24;
    --danger-border: #f5c6cb;
    --font: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    --font-size: 16px;
    --line-height: 1.5;
    --content-width: 960px;
    --form-width: 560px;
  }

  * { box-sizing: border-box; font-size: inherit; }
  html, body { min-height: 100%; margin: 0; }
  html, body, input, button, select, textarea { font: var(--font-size)/var(--line-height) var(--font); }
  body { background: var(--background); color: var(--text); }
  h1, h2, h3, h4, h5, h6, p, li, dt, dd, label, input, button, code, pre { font-size: inherit; }
  h1, h2, h3, h4, h5, h6 { line-height: inherit; }
  a { color: var(--link); }
  a:hover { color: var(--link-hover); }

  [data-part="site-header"] { border-bottom: 1px solid var(--border-soft); }
  [data-part="site-header"] nav {
    display: flex;
    align-items: baseline;
    gap: 1rem;
    width: min(var(--content-width), calc(100% - 2rem));
    margin: 0 auto;
    padding: .5rem 0;
  }
  [data-part="site-header"] a { color: var(--muted); text-decoration: none; }
  [data-part="site-header"] a:hover { color: var(--link-hover); text-decoration: underline; }
  [data-part="site-header"] [data-part="brand"] { color: var(--text); font-weight: 700; }

  input:not([type="hidden"]) {
    display: block;
    width: 100%;
    padding: .375rem;
    color: var(--text);
    background: var(--background);
    border: 1px solid var(--border);
    border-radius: 0;
  }
  input:not([type="hidden"]):focus {
    outline: 0;
    border-color: var(--focus);
    box-shadow: 0 0 0 .2rem rgb(0 123 255 / 25%);
  }
  button {
    display: inline-block;
    width: auto;
    padding: .1rem .75rem;
    color: #ffffff;
    background: var(--primary);
    border: 1px solid var(--primary-border);
    border-radius: 0;
    cursor: pointer;
  }
  button:hover { background: var(--primary-hover); }
  """

  @header """
  <header data-part="site-header">
    <nav aria-label="Ted">
      <a href="/" data-part="brand">ted</a>
      <a href="/docs">operations</a>
      <a href="/auth.md">auth.md</a>
      <a href="/terms">terms</a>
    </nav>
  </header>
  """

  @doc "The shared browser stylesheet, ready to be inlined in a style block."
  @spec styles() :: String.t()
  def styles, do: @styles

  @doc "Shared navigation for Ted's browser pages."
  @spec header() :: String.t()
  def header, do: @header

  @doc "Replaces the shared-style marker in an inline stylesheet."
  @spec inject(String.t()) :: String.t()
  def inject(css) when is_binary(css), do: String.replace(css, "/* ted-theme */", @styles)
end
