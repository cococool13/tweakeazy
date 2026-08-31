# site/

The toolkit's landing page. Live at
[tweakeazy-site.cohencool.workers.dev](https://tweakeazy-site.cohencool.workers.dev).

Hand-written HTML, CSS and JS — no build step, no dependencies. What is in
this folder is exactly what gets served.

## Deploying

A push to `main` that touches `site/**` publishes it. Toolkit-only commits do
not redeploy the page.

To publish by hand:

```bash
npx wrangler@4 pages deploy site --project-name=tweakeazy --branch=main
```

`--branch=main` is what makes it a production deploy. Leave it off and Pages
files the upload as a preview, which succeeds, prints a URL, and never moves
the live site.

## `_headers`

Cache and security headers live in `_headers`, at the root of this folder
because that is where Pages reads it from in whatever directory it is handed.

**Every matching rule is applied and concatenated.** Two rules setting
`Cache-Control` on the same path produce one header with two `max-age`s, and
the browser takes the first — so keep each rule's path set disjoint rather
than relying on a later rule to override an earlier one.

## History

This page was previously hosted on Netlify and lived in no repository. It was
recovered from the deployed files in August 2026 when the site moved to
Cloudflare Pages, then brought in here so it has a source of truth. The
original host config was not retrievable, so `_headers` was reconstructed from
the response headers the live site was actually serving.
