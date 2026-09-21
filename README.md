# Offline build site (tech demo)

Runnable model of an air-gapped Nix build site: Hydra rebuilds a
product from source on machines that have no network access to the outside
world. The only thing that ever crosses the air gap is a bundle of
fixed-output derivations (FODs), scanned and signed
before it enters. Everything that leaves the site is signed by a chain of keys
that ends in a single release key.

Inspired by [Demonstrably Secure Software Supply Chains with Nix](https://nixcademy.com/posts/secure-supply-chain-with-nix/).

```
VLAN 1 (online world)               VLAN 2 (air-gapped build site)
┌──────────────────────────┐        ┌─────────────────────────────────────────┐
│ internet ─http─▶ scanner │  USB   │ fodcache                                │
└──────────────────────────┘ ═════▶ │   │                                     │
                             stick  │   ▼                                     │
                                    │ hydra ──ssh serve──▶ builder1           │
                                    │   │                                     │
                                    │   │ pull (ssh, read-only, pinned)       │
  no node sits on both VLANs        │   ▼                                     │
                                    │ signer                                  │
                                    │   │                                     │
                                    │   ▼                                     │
                                    │ cache ──http──▶ client                  │
                                    │                                         │
                                    └─────────────────────────────────────────┘
```

## Run it

```console
# the full story as an automated test (8 VMs, ~10.5 GB RAM)
nix flake check -L

# interactive demo: interactive driver REPL
nix run .#demo
```

In the driver REPL, run `run_tests()` followed by `demo()`.
