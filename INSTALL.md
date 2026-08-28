# INSTALL.md — the dearkarl install runbook

**This file is written for an AI agent.** If you are a human reading it, you can
follow it too, but it is phrased as instructions to the agent doing the work.

Read it to the end before running anything. Two steps are irreversible, and one
of them can take over mail for a domain.

---

## What you are about to build

```
the user's phone ──forward──▶ a secret address on their domain
                                    │  Cloudflare Email Routing (free)
                                    ▼
                              an Email Worker      ← parses MIME → markdown
                                    │
                                    ▼
                     their PRIVATE GitHub repo   inbox/2026-…-subject.md
                                    │
                                    ▼
                       their next AI session announces it
```

Nothing in this install contacts a dearkarl server, because there isn't one.
Everything runs in the user's own Cloudflare and GitHub accounts.

Budget about 15 minutes, most of it waiting for the user to click through token
screens.

## Rules you do not break while doing this

`CLAUDE.md` has the full list. The four that this procedure can break:

1. **Never ask the user to paste a secret into the chat.** Tokens are entered in
   the user's own terminal with `! export NAME=...` and read from the
   environment. You never see the value and it never enters the transcript.
2. **Never write the secret address into a file, a commit, or a config you
   create.** Not in the private inbox repo either. Step 3 has a mode where you
   never see it at all — offer that one first.
3. **Never enable Email Routing on a zone that already receives mail.**
   `deploy.sh` refuses; do not work around it. Ask for a subdomain instead.
4. **Stop and ask at every decision point marked ⏸.** Do not pick a default and
   mention it afterwards.

---

## Step 0 — Preflight

Run all of these before changing anything. Report what is missing as one list,
not one message per failure.

```bash
command -v git curl python3 bash        # deploy.sh needs these
gh auth status                          # GitHub CLI, logged in
```

Then check the Cloudflare side. You need the zone to exist already — this
runbook does not register domains.

⏸ **Ask the user:**

> 1. Which domain on Cloudflare should receive the mail? A subdomain is fine and
>    is safer — `karl.example.com` rather than `example.com`.
> 2. Does that domain currently receive email anywhere? (If yes, we use a
>    subdomain instead — turning on Email Routing would redirect the real mail.)
> 3. Which address will you forward *from*? Give every address you might send
>    from — phone, laptop, work. Only these are accepted.
> 4. What should the private inbox repo be called? Default: `dearkarl-inbox`.

Notes for you while they answer:

- **Question 2 is the dangerous one.** If they are unsure, check for yourself
  once you have the API token (Step 3) — `deploy.sh` also refuses on its own,
  which is the real backstop.
- **Question 3:** the allowlist matches the whole address, and the Worker also
  checks the `From:` header against DMARC. Addresses at providers that let one
  account forge another's `From:` are weaker; Gmail, Fastmail, HEY and Proton
  are fine.
- Nothing they answer here is a secret. Do not treat these like tokens.

---

## Step 1 — Create the private inbox repo

This is where their mail will live. It must be private.

```bash
gh repo create <name> --private --add-readme
git clone https://github.com/<owner>/<name>.git ~/<path>
mkdir -p ~/<path>/inbox ~/<path>/archive
```

Ask where they want it cloned; `~/Projects/github/<name>` is a reasonable
suggestion, not a default you pick silently.

Add a `.gitignore` with `.DS_Store`, and commit the empty `inbox/` and
`archive/` directories (a `.gitkeep` in each). Push.

⏸ **Confirm with the user that the repo shows as Private on GitHub** before you
put a token anywhere near it.

---

## Step 2 — The two tokens

Both are least-privilege. Do not offer a broader one because it is fewer clicks.

**Cloudflare API token** — dash.cloudflare.com → My Profile → API Tokens →
Create Token → Custom token. Exactly three permissions:

| Scope | Permission | Level |
|---|---|---|
| Account | Workers Scripts | Edit |
| Zone | Zone | Read |
| Zone | Email Routing Rules | Edit |

Restrict the zone resources to the one domain from Step 0.

**GitHub fine-grained PAT** — github.com → Settings → Developer settings →
Personal access tokens → Fine-grained tokens. Repository access: **only** the
inbox repo. Permissions: **Contents → Read and write**. Nothing else. This token
goes into the Worker, so it is the one that matters most: it can write to that
repo and nowhere else.

⏸ **Tell the user to run these in their own terminal**, and say plainly that you
will not see the values:

```
! export CLOUDFLARE_API_TOKEN=<paste here, in your terminal>
! export GITHUB_TOKEN_FOR_WORKER=<paste here, in your terminal>
```

Verify they landed without printing them:

```bash
[ -n "${CLOUDFLARE_API_TOKEN:-}" ] && echo "cf token: set" || echo "cf token: MISSING"
[ -n "${GITHUB_TOKEN_FOR_WORKER:-}" ] && echo "gh token: set" || echo "gh token: MISSING"
```

If your shell does not carry the variables between commands, ask the user to run
Step 3's command themselves in the same terminal where they exported them, and
to paste back the output **minus the last line** (the last line contains the
secret address).

---

## Step 3 — The secret address, then deploy

⏸ **Ask the user which they prefer** — this is a real choice, not a formality:

> **A. You pick the address (recommended).** You choose something unguessable,
> export it in your terminal, and I never see it. Nothing about it ever enters
> this conversation.
>
> **B. Let the script generate one.** It prints the address once, here in this
> session. Faster, but the address then exists in this transcript.

For **A**, tell them to run, in their own terminal:

```
! export SEND_TO_ADDRESS=karl-<something-random>@<their-domain>
```

Suggest they make the random part long and meaningless — this address *is* the
password. Anyone who learns it can put mail in front of their AI, and the
allowlist is the only thing behind it.

Then deploy. This is the irreversible step: it uploads the Worker, enables Email
Routing on the zone, and creates the route.

```bash
cd worker
ZONE_NAME=<their-zone> \
GITHUB_REPO=<owner>/<inbox-repo> \
ALLOWED_SENDERS=<addr1>,<addr2> \
./deploy.sh
```

For **mode A**, suppress the final line so the address never reaches you:

```bash
./deploy.sh | grep -v 'Your secret address'
```

**Expected output**, in order: `account=… zone=…`, `no MX records — safe to
enable Email Routing.`, `upload ok`, `enabled`, `route ok`.

**If it stops at the MX check** — `!! … already has N MX record(s) … STOPPING` —
that is the guard doing its job. The domain receives mail. Go back to Step 0 and
use a subdomain. Do not delete their MX records.

---

## Step 4 — Install the client

Two pieces, both in `client/`. The hook announces new mail into the next
session; the skill reads and archives it.

```bash
mkdir -p ~/.claude/hooks ~/.claude/skills/inbox
cp client/hooks/session-inbox.sh ~/.claude/hooks/dearkarl-session-inbox.sh
chmod +x ~/.claude/hooks/dearkarl-session-inbox.sh
cp client/skills/inbox/SKILL.md ~/.claude/skills/inbox/SKILL.md
```

Then **substitute the placeholders**:

- In `~/.claude/skills/inbox/SKILL.md`, replace every `__INBOX_PATH__` with the
  absolute path to the inbox repo. Check none remain:
  `grep -c __INBOX_PATH__ ~/.claude/skills/inbox/SKILL.md` must print `0`.
- Merge the two hook entries from `client/settings.snippet.json` into
  `~/.claude/settings.json`, replacing `__INBOX_PATH__` and `__HOOK_PATH__`.
  **Merge — do not overwrite the file.** If it already has a `hooks` key with
  `SessionStart` or `UserPromptSubmit` arrays, append to those arrays.
- Copy the same two entries into `<inbox repo>/.claude/settings.json` as well,
  so the hook also fires on Claude Desktop and claude.ai/code, where
  `~/.claude` does not exist. Both registrations point at the same script; it is
  written to survive firing twice.

Sanity-check the JSON before moving on:

```bash
python3 -c "import json;json.load(open('$HOME/.claude/settings.json'));print('ok')"
```

---

## Step 5 — The watched test (do not skip this)

Nothing above proves mail arrives. This does.

⏸ **Ask the user to send one email** to the secret address, from one of the
allowlisted addresses, with a subject like `test from install`. Ask them to make
the first line:

```
karl: this is the install test, nothing to do
```

so the trusted-region path gets exercised too.

Then wait and watch — mail usually lands within 30 seconds:

```bash
cd <inbox repo> && git pull --quiet && ls -la inbox/
```

**Success looks like** a new `inbox/<timestamp>-test-from-install.md`
containing:

- frontmatter with `status: unread` and an `auth_check:` line
- a `karl: this is the install test…` line **above** the
  `> Untrusted third-party content` banner
- the message body inside the fence below it

Show the user the frontmatter and the `karl:` line. **Do not paste the whole
file into the conversation** — it is their mail.

**If nothing arrives**, work through this in order:

| Symptom | Cause | Fix |
|---|---|---|
| Sender got a bounce, "no such recipient" | Their `From:` is not on the allowlist | Redeploy with the address added (see below) |
| Sender got "message too large" | Over 5 MB raw | Expected; try a smaller mail |
| No bounce, no file | Worker ran, GitHub write failed | Cloudflare dashboard → Workers → `dearkarl-email` → Logs; a 403/404 means the PAT lacks Contents:RW on that repo |
| No bounce, no file, no log line at all | Route not matching | Cloudflare → the zone → Email → Routing rules; check the address matches exactly |

Finally, confirm the announcement path works: start a new session in any
project and check that it opens with `dearkarl inbox: 1 unread email(s)`.

---

## Step 6 — Hand over

Tell the user, in your own words:

1. **Where their address is.** If mode A, they have it; if mode B, tell them to
   save it in a password manager now, and that you are not going to repeat it.
2. **The allowlist is the only lock.** Adding an address means a redeploy.
3. **What `karl:` does** — first line of any mail becomes an instruction
   attached to that message, and their AI will show it and ask before acting.
4. **Verification is currently log-only.** Every message gets a sender verdict
   in `auth_check:`, but nothing is rejected for a bad one yet. Tell them to run
   `grep auth_check inbox/*.md` after a week; once every address they really
   send from reads `pass`, they can turn it enforcing — `README.md` §"Turning
   verification on" has the one-line change. Do not do it for them now:
   enforcing before the observation window locks them out of their own inbox.
5. **Nothing phones home.** No update check, no telemetry. If they want the next
   version they pull this repo.

---

## Changing something later

**`deploy.sh` cannot be re-run once Email Routing is live.** Its MX guard sees
the routing records it created and aborts before the upload — by design, but it
means "add an address to the allowlist" is not a re-run. Do a script-only
upload instead, which touches neither DNS nor routes:

```bash
curl -sS -X PUT \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/scripts/dearkarl-email" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -F 'metadata={"main_module":"worker.js","compatibility_date":"2026-07-01","bindings":[
        {"type":"plain_text","name":"ALLOWED_SENDERS","text":"<new,list>"},
        {"type":"plain_text","name":"GITHUB_REPO","text":"<owner>/<repo>"},
        {"type":"inherit","name":"GITHUB_TOKEN"}
      ]};type=application/json' \
  -F "worker.js=@worker.js;filename=worker.js;type=application/javascript+module" \
  -F "vendor/postal-mime/postal-mime.js=@vendor/postal-mime/postal-mime.js;filename=vendor/postal-mime/postal-mime.js;type=application/javascript+module" \
  -F "vendor/postal-mime/text-format.js=@vendor/postal-mime/text-format.js;filename=vendor/postal-mime/text-format.js;type=application/javascript+module"
```

Two things that will bite you if you improvise this:

- `{"type":"inherit","name":"GITHUB_TOKEN"}` keeps the existing secret. Omit it
  and the Worker silently drops to log-only mode — mail stops landing and
  nothing bounces.
- `filename=` must be the **full module path**. curl otherwise sends the
  basename, the `./vendor/...` import fails to resolve, and Cloudflare rejects
  the upload with "No such module".

## Uninstalling

```
Cloudflare → the zone → Email → Routing → delete the rule, disable Email Routing
Cloudflare → Workers → delete dearkarl-email
GitHub    → revoke the fine-grained PAT
~/.claude → remove the two hook entries, the hook script, and skills/inbox/
```

The inbox repo is theirs; the mail in it is plain markdown and stays readable
with nothing of ours installed.
