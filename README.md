# Offline Build Site — a Hydra supply-chain tech demo

A complete, runnable model of an **air-gapped Nix build site**: Hydra rebuilds a
product from source on machines that have no network access to the outside
world. The only thing that ever crosses the air gap is a **bundle of
fixed-output derivations** (FODs) — the source code — scanned and signed
before it enters. Everything that leaves the site is signed by a chain of keys
that ends in a single release key.

Inspired by [Secure Supply Chain with Nix](https://nixcademy.com/posts/secure-supply-chain-with-nix/).

```
VLAN 1 (online world)               VLAN 2 (air-gapped build site)
┌──────────────────────────┐        ┌─────────────────────────────────────────┐
│ internet ─http─▶ scanner │  USB   │ fodcache  import check: verify bundle   │
│ (nginx:    (fod-scanner: │ ═════▶ │   │       CA paths only                 │
│ sources,   scan FODs,    │ stick  │   ▼ substitute, never build             │
│ bundles)   sign paths    │        │ hydra ──ssh serve──▶ builder1           │
│            + the bundle) │        │   │                 (signs its output)  │
└──────────────────────────┘        │   │ pull (ssh, read-only, pinned)       │
  no node sits on both VLANs        │   ▼                                     │
  separate hosts on purpose:        │ signer  closure audit: scanner sig on   │
  compromising the source host      │ (inbound: nothing)  every CA path,      │
  alone cannot produce a bundle     │   │     builder sig on the rest → sign  │
                                    │   ▼ with the release key, then rsync    │
                                    │ cache ──http──▶ client                  │
                                    │ (nginx)      (trusts release key ONLY)  │
                                    └─────────────────────────────────────────┘
```

## Run it

```console
# the full story as an automated test (8 VMs, ~10.5 GB RAM)
nix flake check -L

# interactive demo: interactive driver REPL, Hydra UI on http://localhost:3000
nix run .#demo
```

In the driver REPL, `run_tests()` loads the stage helpers and prints a
menu; it does not run the story. For that, run `demo()`.

## The trust model

Two independent properties are established for every released artifact:

**Input trust: what went in.**
Sources enter the site as fixed-output derivations, so their *integrity* is
anchored in content hashes: a tampered source can never match its pinned hash.
But a hash proves only "these are the bytes you pinned", not "someone vetted
these bytes". *Approval* therefore comes from the scanning system, which scans
every source and signs each store path (nix key) plus the bundle as a whole
(`ssh-keygen -Y`).

An important subtlety: Nix **accepts content-addressed paths without any signature**, 
even with `require-sigs = true` signature checking short-circuits for CA paths. 
A scanner signature on FODs is therefore unenforceable by nix.conf alone. 
Enforcement lives in two explicit checks:

- **The import check, at the air-gap boundary.** `fod-cache-import` verifies the bundle's
  detached SSH signature against a pinned `allowed_signers` file before
  anything is unpacked, and refuses any path that is not content-addressed.
- **The closure audit, at release.** `signer-release` audits the *entire closure* of a
  build: every CA path must carry a scanner signature, every built path a
  builder signature. Only then does it re-sign with the release key and push.

**Output trust: what came out.**
Every builder signs what it builds. The signer verifies those signatures when it
pulls from Hydra, audits the closure, signs with the release key, and
pushes to the release cache. Clients trust **exactly one key**: the release
key. Released narinfos carry the whole provenance chain — scanner, builder,
and release signatures side by side.

## Attack surface

| machine  | inbound                                                  |
|----------|----------------------------------------------------------|
| fodcache | nginx :80 (static files)                                 |
| hydra    | UI :3000; sshd restricted to read-only `nix-store --serve` for the signer |
| builders | sshd only, one user, forced `nix-store --serve --write`; **no substituters** (the demo runs one; production runs N) |
| signer   | **nothing** — it only initiates connections              |
| cache    | nginx :80; sshd restricted to one rrsync-jailed uploader |

All SSH host keys are pinned on the connecting side; firewalls are on
everywhere; the nix sandbox stays enabled on every machine.

## The tools

- **`fod-bundler`** — evaluates a Hydra jobset expression with `nix-eval-jobs`
  (same restrictions as Hydra's evaluator), walks the derivation closures,
  filters the fixed-output derivations, realizes them (the only step that
  touches the network) and exports them as a `file://` binary cache bundle.
  `--exclude` keeps unapproved jobs out of the bundle.
- **`fod-scanner`** — imports a bundle (CA paths only), scans every path
  (a stand-in for your real scanner), and on success signs
  each path with the scanner's nix key and the bundle with the scanner's SSH
  key. One violation → nothing gets signed.
- **`fod-cache-import`** (on the fodcache) — the import check, see above.
- **`signer-release`** (on the signer) — the closure audit, see above.

## Release discovery (what to pull, and when)

The signer accepts no inbound connections, so nothing can tell it to release.
It has to be driven from its own console. An operator reads the store path of
a finished build off Hydra's UI and runs `signer-release <path>`, which pulls
that path's closure over the pinned ssh channel and audits it. The
release cadence is the operator's decision.

## Reusing the modules

Every role is a reusable NixOS module under `nixosModules.*`:
`common`, `mirror`, `scanner`, `fodCache`, `builder`, `hydraCoordinator`,
`signer`, `releaseCache`, `client`. Each one configures itself under
`offline-build-site.<role>` — `offline-build-site.scanner.nixKeyFile`,
`offline-build-site.signer.trustedBuilderKeys`, and so on. The test
(`tests/offline-site.nix`) doubles as the reference for wiring them up.

**⚠️ Demo keys.** `demo-keys/` contains throwaway keys committed
to this repo so the demo is reproducible — treat them like the snake-oil keys
in nixpkgs. For anything real: generate fresh keys (`nix key generate-secret`
for the nix keys, `ssh-keygen -t ed25519` for the SSH keys), provision them
with agenix/sops-nix, and point the module options at the decrypted paths. The
module options take file paths for exactly this reason.

For production you would additionally want: a real scanner in place of
`fod-scanner`'s marker grep, and monitoring on both gates (a refused 
bundle or a failed closure audit should alert).
