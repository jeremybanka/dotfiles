# Tailscale Direct Guest Access

This guide walks through the exact setup we validated for direct
`phone -> scrubs guest` access over Tailscale SSH.

It is written for the real starting point we hit in practice:

- you already have a scrubs guest such as `wayforge`
- you already use Tailscale a little, but have not deeply customized it
- you are looking at Tailscale's web UI, not the local app
- your tailnet policy is still close to the default unrestricted example

## What You Get

After this setup:

- `just bootstrap wayforge` enrolls the guest in your tailnet automatically
- the guest keeps its existing host-local Lima SSH path for Mac workflows
- the guest also gets a Tailscale name such as
  `wayforge.tail3bbc88.ts.net`
- you can SSH to the guest directly from your phone without enabling a real
  guest password

## Before You Start

Make sure these are true:

- the guest already bootstraps successfully with `just bootstrap <instance>`
- you are signed into the Tailscale web admin for the same tailnet your phone
  will use
- your phone already has the Tailscale app and can join that tailnet

## Part 1: Update Tailscale Policy

### Open the Right Screen

1. Go to [login.tailscale.com](https://login.tailscale.com).
2. Open `Access controls`.
3. Switch to `JSON editor`.

If you see a greyed out `Convert to grants` button, that is fine. It means your
tailnet already uses `grants`, which is what we want.

### If Your Policy Still Looks Like the Default Example

You do not need to replace the entire file.

Leave your current unrestricted `grants` rule alone for now if your tailnet is
still simple and personal. Just add:

1. a real `tagOwners` section
2. one extra SSH rule for `tag:scrubs`

### Add `tagOwners`

Near the top, turn the commented example into a real section:

```json
"tagOwners": {
  "tag:scrubs": ["autogroup:admin"]
},
```

This means tailnet admins are allowed to assign the `tag:scrubs` tag to
devices.

### Add an SSH Rule for Scrubs Guests

Keep your existing self-SSH rule. Then add another rule inside the `"ssh"`
array:

```json
{
  "action": "accept",
  "src": ["autogroup:member"],
  "dst": ["tag:scrubs"],
  "users": ["jem"]
}
```

Change `jem` if your guest username is different.

### Minimal Working Example

If your current file still looks close to the default, the relevant parts
should end up looking like this:

```json
{
  "tagOwners": {
    "tag:scrubs": ["autogroup:admin"]
  },
  "grants": [
    { "src": ["*"], "dst": ["*"], "ip": ["*"] }
  ],
  "ssh": [
    {
      "action": "check",
      "src": ["autogroup:member"],
      "dst": ["autogroup:self"],
      "users": ["autogroup:nonroot", "root"]
    },
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["tag:scrubs"],
      "users": ["jem"]
    }
  ]
}
```

Then click `Save`.

## Part 2: Create the Tailscale OAuth Credential

### Open the Credential UI

1. Go to `Settings`.
2. Open `Trust credentials`.
3. Create a new credential.
4. Choose `OAuth`.

### Important UI Notes

- The free-text field is currently labeled `Description`, not `Name`.
- The scope picker starts collapsed and is easy to misread.
- The permission you want lives under `Keys`.

### Choose the Correct Scope

Set:

- `Keys -> Auth Keys -> Write`

Do not rely on:

- `Keys -> OAuth Keys -> Write`

That one sounds close, but it is the wrong permission for this bootstrap flow.

If Tailscale asks you to limit the credential to tags, choose:

- `tag:scrubs`

Generate the credential and copy the client secret.

## Part 3: Store the Secret on Your Mac

From the repo root:

```sh
cd /Users/jem/dotfiles
just scrubs-auth-set-tailscale personal
```

Paste the OAuth client secret when prompted.

Then verify scrubs can see it:

```sh
just scrubs-auth-status personal
```

You want the Tailscale line to say `present`.

## Part 4: Configure `vms/settings.env`

Make sure [settings.env](/Users/jem/dotfiles/vms/settings.env) contains:

```sh
SCRUBS_TAILSCALE_OAUTH_SECRET_KEYCHAIN_SERVICE__PERSONAL=scrubs-tailscale-oauth-secret-personal
SCRUBS_TAILSCALE_OAUTH_SECRET_KEYCHAIN_ACCOUNT__PERSONAL=tailscale
SCRUBS_TAILSCALE_TAGS=tag:scrubs
SCRUBS_TAILSCALE_PREAUTHORIZED=true
SCRUBS_TAILSCALE_EPHEMERAL=false
```

If your guest username is not your macOS username, also set:

```sh
SCRUBS_GUEST_USER=jem
SCRUBS_BOOTSTRAP_USER=jem
```

Replace `jem` with the real guest username if needed.

## Part 5: Bootstrap the Guest

If the guest already exists, just re-bootstrap it:

```sh
just bootstrap wayforge
```

This now does all of the following from Nix guest configuration:

- installs and enables Tailscale
- seals the OAuth secret into clean guest auth storage
- joins the tailnet as a tagged node
- enables Tailscale SSH

## Part 6: Verify the Guest Joined

Check status in the guest:

```sh
limactl shell wayforge -- sudo tailscale status
```

Success looks like a normal peer list with `wayforge` included, for example:

```text
100.x.y.z  wayforge  wayforge.tail3bbc88.ts.net  linux  -
```

If the output is only:

```text
Logged out.
```

go straight to the troubleshooting section below.

## Part 7: Connect from Your Phone

1. Make sure your phone is connected to the same Tailscale tailnet.
2. Open your SSH client on the phone.
3. Connect to the guest's MagicDNS name, for example:

```text
wayforge.tail3bbc88.ts.net
```

4. Use the guest username, for example:

```text
jem
```

5. If the client insists on password-style auth, try:

```text
username: jem+password
password: anything
```

That is a Tailscale SSH compatibility trick. It does not mean the guest has a
real password set.

## Troubleshooting

### `Logged out.` After Bootstrap

On current scrubs, this should usually be fixed automatically.

If it still happens, check the autoconnect service:

```sh
limactl shell wayforge -- sudo systemctl status tailscaled-autoconnect --no-pager
```

The two most likely causes are:

- wrong OAuth credential scope
- guest DNS was not ready when `tailscaled-autoconnect` first ran

### Wrong Scope Symptoms

If you accidentally chose:

- `Keys -> OAuth Keys -> Write`

instead of:

- `Keys -> Auth Keys -> Write`

the guest can stay logged out even though the secret was stored correctly.

Fix the credential, store the new secret again with:

```sh
just scrubs-auth-set-tailscale personal
```

then re-run:

```sh
just bootstrap wayforge
```

### DNS Startup Race

We hit a real issue where `tailscaled-autoconnect` started before guest DNS was
ready and failed to resolve `api.tailscale.com`.

That race is now handled in scrubs by waiting for:

- `network-online.target`
- `systemd-resolved.service`
- `nss-lookup.target`

and restarting `tailscaled-autoconnect` on failure.

If you are testing an older guest generation, re-bootstrap it with the latest
scrubs code.

### SSH Denied Even Though the Node Is Online

Usually this means your tailnet `ssh` rule does not allow the right guest user.

Check that the policy rule uses the actual guest username, for example:

```json
"users": ["jem"]
```

### Need More Detail

These commands are the most useful next checks:

```sh
limactl shell wayforge -- sudo tailscale status
limactl shell wayforge -- sudo systemctl status tailscaled tailscaled-autoconnect --no-pager
```

## Why This Setup Works Well

- it keeps guest password auth disabled
- it does not expose guest SSH to the public internet
- it keeps Tailscale in clean Nix guest configuration
- it preserves the existing Lima-local host workflow

## Appendix: UX Lessons Captured

- `Access controls -> JSON editor` was the right place for policy work
- the greyed-out `Convert to grants` button was harmless and meant grants were
  already in use
- `Description` was the real label in the OAuth credential UI
- the scope picker was easiest to misread under the collapsed `Keys` section
- `Auth Keys -> Write` was correct
- `OAuth Keys -> Write` was wrong for this flow
- an initial `Logged out.` did not mean the whole design was wrong; it exposed a
  boot-order bug that scrubs now handles automatically
