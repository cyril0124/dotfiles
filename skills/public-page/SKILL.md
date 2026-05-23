---
name: public-page
description: Publish static HTML files or static site directories to temporary public URLs with automatic TTL expiry, without platform auth or local tunnels. Uses PageDrop by default and can fall back to Aired. Use when the user wants a public web page, shareable demo, hosted HTML report, or non-local preview without using a personal hosting account; do not use for permanent production sites or dynamic backends.
---

# Public Page

Publish a static page/site to a temporary public URL with automatic expiration.

## When to use

Use this skill when the user asks for:

- a public webpage link, not `localhost`
- a quick hosted HTML report or comparison page
- a shareable static demo without using a personal hosting account
- a temporary public page that should expire automatically
- an alternative when authenticated deployment platforms are unavailable or unwanted

Do not use it for dynamic servers, databases, authenticated apps, long-term production hosting, or private/sensitive content. Never publish personal privacy data, secrets, credentials, private notes, internal documents, or any non-public user data.

## Providers

Default fallback order:

1. PageDrop — supports TTL, password, HTML/Markdown/ZIP/PDF; default provider.
2. Aired — supports TTL, PIN, update/delete tokens; fallback for HTML and small pages.

Use TTL-capable providers only. Do not use permanent/no-expiry mode for this skill unless the user explicitly asks.

## Limits

- PageDrop: TTL supported, HTML JSON body conservatively 5 MB, ZIP/PDF 10 MB, 50 files per ZIP, 10 creates/minute/IP.
- Aired: TTL supported, default 7 days, max page size 2 MB, 5 uploads/hour/IP.

## Quick start

Auto provider fallback, default TTL target 72 hours:

```bash
bash skills/public-page/scripts/deploy.sh ./index.html
```

Static directory containing `index.html`:

```bash
bash skills/public-page/scripts/deploy.sh ./site
```

Choose a provider:

```bash
bash skills/public-page/scripts/deploy.sh ./index.html --provider pagedrop --ttl 1d
bash skills/public-page/scripts/deploy.sh ./index.html --provider aired --ttl 24h
```

## Workflow

1. Create or locate the static artifact.
   - Single-page reports should usually be one `index.html` with inline CSS/JS.
   - Multi-file sites must contain `index.html` at the root.
2. Confirm the content is safe to publish publicly.
   - Check for personal privacy data, names, phone numbers, addresses, emails, IDs, account identifiers, tokens, API keys, private notes, internal URLs, and confidential business data.
   - If any sensitive or non-public data is present, stop and ask the user before publishing.
3. Deploy with `scripts/deploy.sh`.
4. Verify the returned URL is reachable with a HEAD request.
5. Tell the user:
   - public URL
   - provider
   - expiration time
   - that it does not use a personal hosting account

## Output requirements

When deployment succeeds, return only the useful details:

```text
Public URL: https://...
Provider: pagedrop | aired
Expires: 72 hours / expires_at ...
Note: Hosted as a temporary public page; not localhost.
```

Do not expose provider update/delete tokens unless the user needs redeploy or deletion instructions; treat them like capability tokens.

## Common pitfalls

- Do not use a personal hosting account unless explicitly requested.
- Do not present a local tunnel as permanent hosting.
- Do not claim the URL is permanent; this skill is for TTL-expiring public pages.
- Do not upload personal privacy data, secrets, credentials, private notes, tokens, internal documents, or non-public user data.
- If PageDrop fails, surface the provider failure and then explicitly try Aired.
- Aired fallback in this script supports single HTML files only.
