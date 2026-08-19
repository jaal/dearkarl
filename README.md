# dearkarl 📬

**Email anything to your AI.** Like Send-to-Kindle, but for AI context: forward
an email (an article, a voice-dictated idea, meeting notes) to your secret
address, and your next Claude / Claude Code session can read it. No copy-pasting,
no apps to install at capture time — email is the one share target every device
already has.

Named after Karl — the mailman who always delivers. You write to
*Dear Karl…*, Karl delivers.

## Four steps, and only the last one repeats

1. Deploy the Worker to your own Cloudflare domain. One script, about 15 minutes.
2. You get a secret address that only you know.
3. Forward anything to it, from any device: an email, an article, a note you
   spoke into your phone.
4. Your next Claude session opens with *"2 new things arrived"*.

After that it is just forwarding. No app, no plugin, no copy-paste.

## Status: early

The pipeline works end-to-end (it processes the author's real mail daily), but
this repo is pre-1.0: the AI-driven install runbook and packaged hook/skill are
still landing. Step 1 above is a shell script today; the plan is that you paste
this repo's URL into Claude Code, say "install this", and it does the rest.
Watch/star if you want that version when it ships.

Want it without running anything yourself? There is a waiting list for a hosted
version: <https://tally.so/r/jaXgz9>

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

## Tell Karl what to do with it

Start the email with a `karl:` line and it becomes an instruction attached to that
message — read by your AI before it touches the mail, in that session and every
later one, and surfaced for your confirmation before it acts on it:

```
karl: pull the invoice numbers out of this, reply drafts in Polish, don't archive yet

---------- Forwarded message ---------
From: …
```

The Worker lifts that line out of the body and stores it above the
untrusted-content marker, so your AI can tell your instruction apart from the
mail. Everything else — including a `karl:` line the *sender* wrote — stays inside
the quoted body, where it is inert. Only the first line of what you type counts,
which is what makes the distinction safe: forwarding someone else's mail always
puts a separator or your signature on top.

`karl: …`, `karl, …` and `Karl …` all work; a long instruction that arrives
hard-wrapped is joined back into one line.

## Security (read this)

An email address is an open write channel into your AI's context. dearkarl
treats that seriously, in layers: an unguessable secret address, a hard sender
allowlist in the Worker, DKIM/DMARC verification, size caps, and — most
importantly — everything that lands in the inbox is stored and surfaced as
**untrusted third-party data, never instructions**. Prompt injection is the #1
risk of this whole product category; if you build on this, keep that framing.

### The allowlist alone proves nothing

`message.from` is the envelope `MAIL FROM` — a string the sender types. Matching
it against an allowlist answers "what does this mail claim?", not "who sent it".
Anyone who learns your secret address can put your address in that field.

So `checkSender()` gates on the `From:` **header** instead, which is the field
DKIM/DMARC actually covers, and requires the verdict to name that header's domain
(`dmarc=pass` for someone else's domain does not carry your address). Two limits
worth stating plainly:

- **Domain-level only.** DMARC proves the domain sent the mail, never the local
  part. Every user of a shared provider passes DMARC for its domain — which is
  why the allowlist still has to match the whole address. What protects the local
  part is the provider refusing to let one account send as another. Allowlist
  addresses at providers that enforce that.
- **The last check is yours.** A `karl:` line is surfaced to the agent as a
  *proposal*, to be shown and confirmed before it is acted on — because the
  strongest link in this chain still ends in someone else's promise.

### Turning verification on

It ships in **log-only** mode: every message gets a verdict, nothing is rejected
for it yet. The verdict lands in the Worker log and — durably, because logs
expire — in the file's frontmatter:

```yaml
auth_check: "pass"
auth_check: "pass (envelope bounces@relay.example.com != header you@example.com)"
auth_check: "fail: dmarc not pass"
```

Run it that way until every address you actually send from shows `pass`
(`grep auth_check inbox/*.md`), then make it enforcing — in `worker.js`, replace
the `console.log` under `STAGED ROLLOUT` with the same `setReject("no such
recipient")` the allowlist uses. Do not skip the observation window: mail sent
through a relay or a mailing list can break alignment, and enforcing blind locks
you out of your own inbox.

## License

MIT (see LICENSE). Vendored `postal-mime` is MIT-0, © Andris Reinman
(worker/vendor/postal-mime/LICENSE.txt).
