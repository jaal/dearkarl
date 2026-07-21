# dearkarl 📬

**Email anything to your AI.** Like Send-to-Kindle, but for AI context: forward
an email (an article, a voice-dictated idea, meeting notes) to your secret
address, and your next Claude / Claude Code session can read it. No copy-pasting,
no apps to install at capture time — email is the one share target every device
already has.

Named after Karl — the mailman who always delivers. You write to
*Dear Karl…*, Karl delivers.

## Status: early

The pipeline works end-to-end (it processes the author's real mail daily), but
this repo is pre-1.0: the AI-driven install runbook and packaged hook/skill are
still landing. Watch/star if you want the "tell Claude: install this" experience
when it ships.

## How it works

```
your phone ──forward──▶ secret@your-domain
                              │  Cloudflare Email Routing (free)
                              ▼
                        Email Worker      ← parses MIME → readable markdown
                              │             (postal-mime, vendored, no deps)
                              ▼
                   your PRIVATE GitHub repo   inbox/2026-07-20-…-subject.md
                              │
                              ▼
              your next AI session reads it
```

**The mailman principle: this is a pipe, not a warehouse.** Mail passes through
the Worker in memory for seconds and lands only in *your* repo. Nothing is
stored or logged server-side (metadata-only logs, bounce-don't-queue on
failure), and the code is right here so the claim is verifiable.

## What you need

- A domain on Cloudflare (Email Routing is free; a subdomain works — the deploy
  script refuses to touch a zone that already receives mail)
- A GitHub account + a **private** repo for your inbox
- `CLOUDFLARE_API_TOKEN` and a fine-grained GitHub PAT (Contents:RW, that one
  repo only)

Then: `cd worker && ZONE_NAME=… GITHUB_REPO=… ALLOWED_SENDERS=… ./deploy.sh`

## Security (read this)

An email address is an open write channel into your AI's context. dearkarl
treats that seriously, in layers: an unguessable secret address, a hard sender
allowlist in the Worker, SPF/DMARC verdicts captured, size caps, and — most
importantly — everything that lands in the inbox is stored and surfaced as
**untrusted third-party data, never instructions**. Prompt injection is the #1
risk of this whole product category; if you build on this, keep that framing.

## License

MIT (see LICENSE). Vendored `postal-mime` is MIT-0, © Andris Reinman
(worker/vendor/postal-mime/LICENSE.txt).
