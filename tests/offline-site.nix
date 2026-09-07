{ pkgs, lib, ... }:
let
  keys = ../demo-keys;
  pub = f: lib.trim (builtins.readFile (keys + "/${f}"));

  demoProject = pkgs.callPackage ../demo-project { };

  setupJobset = pkgs.writeShellApplication {
    name = "setup-demo-jobset";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      export EXPR_PATH=${demoProject}/nix
      ${builtins.readFile ./setup-demo-jobset.sh}
    '';
  };
in
{
  name = "offline-build-site";

  defaults = {
    imports = [ ../modules/common.nix ];
    environment.systemPackages = [
      pkgs.curl
      pkgs.jq
    ];
  };

  nodes = {
    internet = {
      imports = [ ../modules/mirror.nix ];
      virtualisation = {
        vlans = [ 1 ];
        memorySize = 1536;
      };
      offline-build-site.mirror = {
        enable = true;
        webRoot = "${demoProject}/webroot";
      };
    };

    scanner = {
      imports = [ ../modules/scanner.nix ];
      virtualisation = {
        vlans = [ 1 ];
        memorySize = 1536;
      };
      offline-build-site.scanner = {
        enable = true;
        nixKeyFile = "${keys + "/cache/scanner.sec"}";
        sshKeyFile = "${keys + "/ssh/scanner-sign"}";
      };
    };

    fodcache = {
      imports = [ ../modules/fod-cache.nix ];
      virtualisation = {
        vlans = [ 2 ];
        memorySize = 512;
      };
      offline-build-site.fodCache = {
        enable = true;
        allowedSignersFile = "${keys + "/ssh/allowed_signers"}";
      };
    };

    hydra = {
      imports = [ ../modules/hydra-coordinator.nix ];
      virtualisation = {
        vlans = [ 2 ];
        memorySize = 3072;
        diskSize = 2048;
        cores = 2;
      };
      offline-build-site.hydra = {
        enable = true;
        fodCacheUrl = "http://fodcache";
        scannerPublicKey = pub "cache/scanner.pub";
        builders = [
          {
            hostName = "builder1";
            publicHostKeyFile = keys + "/ssh/host-builder1.pub";
          }
        ];
        queueRunnerKeyFile = "${keys + "/ssh/queue-runner"}";
        serveReadOnlyKeys = [ (pub "ssh/signer-hydra.pub") ];
        hostKeyFile = "${keys + "/ssh/host-hydra"}";
      };
      environment.systemPackages = [ setupJobset ];
    };

    builder1 = {
      imports = [ ../modules/builder.nix ];
      virtualisation = {
        vlans = [ 2 ];
        memorySize = 1536;
      };
      # fail fast when a build tries to reach the (unreachable) network
      nix.settings = {
        download-attempts = 1;
        connect-timeout = 5;
      };
      offline-build-site.builder = {
        enable = true;
        signingKeyFile = "${keys + "/cache/builder1.sec"}";
        queueRunnerPublicKey = pub "ssh/queue-runner.pub";
        hostKeyFile = "${keys + "/ssh/host-builder1"}";
      };
    };

    signer = {
      imports = [ ../modules/signer.nix ];
      virtualisation = {
        vlans = [ 2 ];
        memorySize = 1024;
      };
      offline-build-site.signer = {
        enable = true;
        hydra = {
          host = "hydra";
          keyFile = "${keys + "/ssh/signer-hydra"}";
        };
        trustedBuilderKeys = [ (pub "cache/builder1.pub") ];
        scannerPublicKeys = [ (pub "cache/scanner.pub") ];
        releaseSecretKeyFile = "${keys + "/cache/release.sec"}";
        push = {
          host = "cache";
          keyFile = "${keys + "/ssh/signer-cache"}";
        };
        knownHostsFile = "${keys + "/ssh/known_hosts"}";
      };
    };

    cache = {
      imports = [ ../modules/release-cache.nix ];
      virtualisation = {
        vlans = [ 2 ];
        memorySize = 512;
      };
      offline-build-site.releaseCache = {
        enable = true;
        uploaderKeys = [ (pub "ssh/signer-cache.pub") ];
        hostKeyFile = "${keys + "/ssh/host-cache"}";
      };
    };

    client = {
      imports = [ ../modules/client.nix ];
      virtualisation = {
        vlans = [ 2 ];
        memorySize = 1024;
      };
      offline-build-site.client = {
        enable = true;
        cacheUrl = "http://cache";
        releasePublicKey = pub "cache/release.pub";
      };
    };
  };

  # interactive only, so `nix flake check` never binds host port 3000
  interactive.nodes.hydra.virtualisation.forwardPorts = [
    {
      from = "host";
      host.port = 3000;
      guest.port = 3000;
    }
  ];

  testScript = ''
    import builtins
    import contextlib
    import json
    import sys
    import time

    INTERACTIVE = "--interactive" in sys.argv
    S = {}


    # the interactive REPL never sees test_script()'s namespace, so helpers
    # go on builtins to be callable by bare name on stage
    def stage(fn):
        setattr(builtins, fn.__name__, fn)
        return fn


    def api(path):
        # --location: /job/.../latest redirects to /build/<id>
        return f"curl --silent --fail --location --header 'Accept: application/json' http://localhost:3000{path}"


    def latest(job):
        return json.loads(hydra.succeed(api(f"/job/demo/main/{job}/latest")))


    def wait_job(job, timeout=300):
        hydra.wait_until_succeeds(
            api(f"/job/demo/main/{job}/latest")
            + " | jq --exit-status '.finished == 1 and .buildstatus == 0'",
            timeout=timeout,
        )


    # escape codes only on stage: CI's log is a file
    C = dict.fromkeys(["dim", "bold", "hot", "good", "bad", "off"], "")
    if INTERACTIVE:
        C = {"dim": "\033[90m", "bold": "\033[1m", "hot": "\033[33m",
             "good": "\033[32m", "bad": "\033[31m", "off": "\033[0m"}


    def head(title):
        print(f"\n{C['dim']}# {title}{C['off']}")


    def run(m, cmd, show=None, echo=(), check=True):
        """echo the command the way the slides show it, then run it"""
        # note the space: "$" glued to "{" would start a nix interpolation here
        prompt = f"{C['dim']}{m.name}$ {C['off']}"
        print(f"\n{prompt}{C['bold']}{show or cmd}{C['off']}")
        status, out = m.execute(cmd)
        for line in out.splitlines():
            if any(k in line for k in echo):
                print(f"  {C['hot']}{line.strip()}{C['off']}")
        if check:
            assert status == 0, out
            return out
        return status, out


    def banner(lines, title="", tone="hot"):
        w = max(max(len(l) for l in lines), len(title) + 2)
        c, off = C[tone], C["off"]
        seg = "\u2500 " + title + " " + "\u2500" * (w - len(title) - 1) if title else "\u2500" * (w + 2)
        print()
        print(f"  {c}\u250c{seg}\u2510{off}")
        for l in lines:
            print(f"  {c}\u2502{off} {l:<{w}} {c}\u2502{off}")
        print(f"  {c}\u2514{'\u2500' * (w + 2)}\u2518{off}")


    def fact(key, value, tone=None):
        v = f"{C[tone]}{value}{C['off']}" if tone else value
        print(f"  {C['dim']}{key:<15}{C['off']} {v}")


    # the driver's per-command log buries what matters on a projector, and
    # nested() ignores the log level, so the logger itself is the only lever.
    # off in CI, where that transcript is the debugging record
    @contextlib.contextmanager
    def hushed(message, attributes={}):
        # silence looks like a hang, so a slow command still says so
        start = time.monotonic()
        try:
            yield
        finally:
            took = time.monotonic() - start
            if took > 3:
                print(f"  ... {message.removeprefix('must ')[:58]}  ({took:.0f}s)")


    @stage
    def quiet(on=True):
        """stage only: drop the driver's per-command transcript"""
        for lg in getattr(log, "logger_list", []):
            if not hasattr(lg, "nested"):
                continue
            if on:
                lg._loud_nested = getattr(lg, "_loud_nested", lg.nested)
                lg.nested = hushed
            elif hasattr(lg, "_loud_nested"):
                lg.nested = lg._loud_nested


    class Block:
        # rows printed one by one get shredded by the driver's log lines
        def __init__(self, title):
            self.title = title
            self.lines = []

        def __enter__(self):
            return self

        def add(self, line=""):
            self.lines.append(line)

        def __exit__(self, *exc):
            if exc[0] is None:
                head(self.title)
                for line in self.lines:
                    print(line)


    def real_build_steps(build_id):
        return int(hydra.succeed(
            "sudo --user postgres psql hydra --tuples-only --no-align --command"
            f" 'select count(*) from buildsteps where build = {build_id} and type = 0;'"
        ))


    ALL = [internet, scanner, fodcache, hydra, builder1, signer, cache, client]


    @stage
    def preheat():
        """wait for the machines that started booting with the driver"""
        head("preheat: waiting for all eight machines")
        for m in ALL:
            m.wait_for_unit("multi-user.target")
        hydra.wait_for_unit("hydra-init.service")
        print("site up, hydra initialised - nothing is on the fod cache yet")


    @stage
    def boot_online():
        """the online world comes up"""
        head("the online world")
        internet.wait_for_unit("nginx.service")
        internet.wait_for_open_port(80)
        scanner.wait_for_unit("multi-user.target")
        internet.succeed("curl --silent --fail http://internet/src/libserialcomm-2.4.rs >/dev/null")
        print("internet serving sources; scanner ready")


    @stage
    def bundle():
        """collect every fixed-output derivation (the only network step)"""
        run(
            internet,
            "fod-bundler --expr ${demoProject}/nix/release.nix"
            " --out /var/lib/fod-bundles/cache"
            " --tarball /var/lib/fod-bundles/fod-bundle.tar.zst 2>&1",
            show="fod-bundler --expr release.nix --tarball fod-bundle.tar.zst",
            echo=(">> realizing",),
        )
        n = int(internet.succeed("ls /var/lib/fod-bundles/cache/*.narinfo | wc --lines"))
        assert n == 3, n
        internet.succeed("test -z \"$(grep --files-without-match '^CA: fixed:' /var/lib/fod-bundles/cache/*.narinfo)\"")
        internet.succeed("! grep --quiet '^Sig:' /var/lib/fod-bundles/cache/*.narinfo")
        S["fod_paths"] = internet.succeed(
            "sed --quiet 's/^StorePath: //p' /var/lib/fod-bundles/cache/*.narinfo"
        ).split()
        assert len(S["fod_paths"]) == 3, S["fod_paths"]
        with Block("the whole online world, in 3 files") as b:
            for p in S["fod_paths"]:
                b.add("  " + p)
            b.add()
            b.add(f"CA: fixed:      {n}/{n}")
            b.add(f"Sig:            0/{n}")


    @stage
    def scan():
        """1b: scan every path, then sign the paths and the bundle"""
        scanner.succeed(
            "curl --silent --fail http://internet/bundles/fod-bundle.tar.zst --output /root/fod-bundle.tar.zst"
        )
        out = run(
            scanner,
            "scan-fod-bundle /root/fod-bundle.tar.zst /root/signed-bundle.tar.zst 2>&1",
            echo=(">> wrote signed bundle",),
        )
        scanner.succeed("test -s /root/signed-bundle.tar.zst.sig")
        fact("scanned", f"{out.count(': ok')}/3 ok")
        fact("path Sig:", "3  demo-scanner-1", tone="hot")
        fact("bundle sig", "signed-bundle.tar.zst.sig")


    @stage
    def carry():
        """the usb stick: the driver is the only thing that crosses the gap"""
        scanner.copy_from_machine("/root/signed-bundle.tar.zst")
        scanner.copy_from_machine("/root/signed-bundle.tar.zst.sig")
        fodcache.wait_for_unit("multi-user.target")
        fodcache.copy_from_host(
            str(scanner.out_dir / "signed-bundle.tar.zst"), "/root/bundle.tar.zst"
        )
        fodcache.copy_from_host(
            str(scanner.out_dir / "signed-bundle.tar.zst.sig"), "/root/bundle.tar.zst.sig"
        )
        hop = "scanner  -->  [ usb stick ]  -->  fodcache"
        banner(
            [
                hop,
                f"{'vlan 1':<{hop.index('fodcache')}}vlan 2",
                "",
                "signed-bundle.tar.zst  +  signed-bundle.tar.zst.sig",
                "two files. nothing else ever crosses.",
            ],
            title="across the air gap",
        )


    @stage
    def import_bundle():
        """verify the bundle signature before anything is unpacked"""
        run(
            fodcache,
            "fod-cache-import /root/bundle.tar.zst /root/bundle.tar.zst.sig 2>&1",
            echo=("Good ",),
        )
        imported = fodcache.succeed("ls /var/lib/fod-cache/*.narinfo | wc --lines").strip()
        fact("signature", "ok, scanner@demo", tone="good")
        fact("imported", f"{imported} paths")
        fodcache.wait_for_unit("nginx.service")
        fodcache.wait_for_open_port(80)
        fodcache.succeed("curl --silent --fail http://fodcache/nix-cache-info")


    @stage
    def sabotage():
        """strip ONE scanner signature: nix will still substitute it"""
        head("sabotage: one source loses its scanner signature")
        ni = fodcache.succeed("grep --files-with-matches 'audit-log-exporter' /var/lib/fod-cache/*.narinfo").split()
        assert len(ni) == 1, ni
        ni = ni[0]
        fact("narinfo", ni.split("/")[-1])
        fact("before", fodcache.succeed(f"grep '^Sig:' {ni}").strip())
        fodcache.succeed(f"sed --in-place '/^Sig:/d' {ni}")
        fact("after", "(no Sig: line)")
        fact("CA:", fodcache.succeed(f"grep '^CA:' {ni}").strip().removeprefix("CA: "))
        total = int(fodcache.succeed("grep --no-filename '^Sig:' /var/lib/fod-cache/*.narinfo | wc --lines"))
        assert total == 2, total
        fact("fod cache Sig:", f"3 -> {total}")
        S["sabotaged"] = True


    @stage
    def air_gap():
        """prove the gap in both directions"""
        for m in [hydra, builder1, signer, cache, client]:
            m.wait_for_unit("multi-user.target")
        with Block("the air gap is real") as b:
            b.add("from      to        result")
            for m, name in [(hydra, "hydra"), (builder1, "builder1")]:
                m.fail("curl --silent --fail --connect-timeout 3 http://internet/ >/dev/null")
                b.add(f"{name:9} internet  FAIL (no route to host)")
            internet.fail("curl --silent --fail --connect-timeout 3 http://fodcache/nix-cache-info >/dev/null")
            b.add("internet  fodcache  FAIL (no route to host)")
            hydra.succeed("curl --silent --fail http://fodcache/nix-cache-info >/dev/null")
            b.add("hydra     fodcache  ok")
            for p in S["fod_paths"]:
                hydra.fail(f"nix path-info {p}")
                builder1.fail(f"test -e {p}")
            signer.fail("systemctl is-active sshd.service")
            b.add()
            b.add("FOD paths present on hydra: 0/3")


    @stage
    def hydra_up():
        """create the jobset and wait for the first evaluation"""
        head("hydra: jobset and first evaluation")
        hydra.wait_for_unit("postgresql.target")
        hydra.wait_for_unit("hydra-init.service")
        hydra.wait_for_unit("hydra-queue-runner.service")
        hydra.wait_for_unit("hydra-evaluator.service")
        hydra.wait_for_open_port(3000)
        hydra.execute("hydra-create-user admin --role admin --password admin")
        hydra.succeed("setup-demo-jobset")
        hydra.wait_until_succeeds(
            api("/jobset/demo/main/evals") + " | jq --exit-status '.evals | length > 0'", timeout=180
        )
        print("evaluated. UI: http://localhost:3000  (admin/admin)")


    JOBS = ["libserialcomm-src", "pump-controller-src", "audit-log-exporter-src",
            "pump-controller", "audit-log-exporter",
            "infusion-pump-fw", "infusion-pump-fw-plus"]


    @stage
    def builds():
        """wait for every job, printing progress so nothing looks frozen"""
        head("building, with no network at all")
        for job in JOBS:
            wait_job(job)
            print(f"  {job:26} ok")
        print(f"all {len(JOBS)} green")


    @stage
    def proof():
        """what every job actually did: substituted, or built and by whom"""
        rows = []
        for job in JOBS:
            b = latest(job)
            n = real_build_steps(b["id"])
            out = b["buildoutputs"]["out"]["path"]
            (pi,) = json.loads(hydra.succeed(f"nix path-info --json {out}")).values()
            ca = bool(pi.get("ca"))
            signers = [x.split(":")[0] for x in (pi.get("signatures") or [])]
            if job.endswith("-src"):
                assert n == 0, f"{job} has {n} real build steps -> was BUILT, not substituted"
                assert ca, f"{job} output is not content-addressed: {pi}"
                sabotaged = bool(S.get("sabotaged")) and job == "audit-log-exporter-src"
                assert ("demo-scanner-1" in signers) != sabotaged, signers
                signed_by = "NO  <- sabotaged" if sabotaged else "demo-scanner-1"
                verdict = "SUBSTITUTED"
            else:
                # the control: the products did run build steps, so the zeros
                # above cannot pass by miscounting
                assert n > 0, f"{job} ran no build steps -> was not built here"
                assert not ca, f"{job} output is content-addressed: {pi}"
                assert "demo-builder1-1" in signers, signers
                signed_by = "demo-builder1-1"
                verdict = "BUILT on builder1"
            rows.append(f"{job:22} {n:>5}  {'yes' if ca else 'no':4} {signed_by:18} {verdict}")

        S["product"] = latest("infusion-pump-fw")["buildoutputs"]["out"]["path"]
        # hydra holds no signing key, so every signature above is a builder's
        hydra.fail("grep --quiet '^secret-key-files' /etc/nix/nix.conf")

        with Block("what hydra actually did") as b:
            b.add(f"{'job':22} {'steps':>5}  {'ca':4} {'signed by':18} verdict")
            for r in rows:
                b.add(r)


    @stage
    def audit(job, must_fail=False):
        """one job: pull, audit the closure, sign, push"""
        b = latest(job)
        path = b["buildoutputs"]["out"]["path"]
        head(f"closure audit: demo/main/{job}")
        status, out = run(signer, f"signer-release {path} 2>&1", check=False)
        hashpart = path.removeprefix("/nix/store/")[:32]
        if must_fail:
            assert status != 0, f"the signer released {job}, which it must refuse"
            cache.fail(f"test -e /var/lib/release-cache/{hashpart}.narinfo")
            for line in out.splitlines():
                if "REFUS" in line.upper():
                    fact("reason", line.strip().split("REFUSED:")[-1].strip())
            fact("RESULT", f"REFUSED - {hashpart}.narinfo absent from the cache", tone="bad")
        else:
            assert status == 0, out
            cache.wait_until_succeeds(
                f"test -e /var/lib/release-cache/{hashpart}.narinfo", timeout=60
            )
            sigs = cache.succeed(f"grep '^Sig:' /var/lib/release-cache/{hashpart}.narinfo")
            assert "demo-release-1:" in sigs and "demo-builder1-1:" in sigs, sigs
            fact("RESULT", f"RELEASED - /var/lib/release-cache/{hashpart}.narinfo", tone="good")
            for line in sigs.strip().split("\n"):
                fact("", line.strip())
            S["product"] = path
        return path


    @stage
    def punchline():
        """the closure audit: release what passes, refuse what does not"""
        audit("infusion-pump-fw")
        if S.get("sabotaged"):
            audit("infusion-pump-fw-plus", must_fail=True)
            print("\nsame jobset, same hydra, both green.")
            print("one of them was built from a source nobody approved.")


    @stage
    def consume():
        """the client trusts exactly one key, and then runs what it got"""
        head("the client: one trusted key")
        product = S["product"]
        client.succeed("curl --silent --fail http://cache/nix-cache-info", timeout=60)
        run(client, f"nix-store --realise {product}")
        fact("realise", "ok - client trusts demo-release-1 only", tone="good")
        out = client.succeed(f"sh {product}", timeout=60)
        assert "ready." in out, out
        with Block(f"$ sh {product.split('-', 1)[-1]}") as b:
            for line in out.strip().split("\n"):
                b.add("  " + line)


    @stage
    def client_refuses():
        """CI-only: strip the release signature and watch the client refuse"""
        head("the client: strip the release signature")
        product = S["product"]
        hashpart = product.removeprefix("/nix/store/")[:32]
        cache.succeed(
            f"cp /var/lib/release-cache/{hashpart}.narinfo /root/narinfo.bak"
            f" && sed --in-place '/^Sig:/d' /var/lib/release-cache/{hashpart}.narinfo"
        )
        # the client must forget the path to ask the cache again; deleting
        # from a 9p store can take minutes, hence CI only
        client.succeed(f"nix-store --delete {product}", timeout=600)
        client.fail(f"nix-store --realise {product}", timeout=60)
        fact("Sig: stripped", "client REFUSES")
        cache.succeed(f"cp /root/narinfo.bak /var/lib/release-cache/{hashpart}.narinfo")
        client.succeed(f"nix-store --realise {product}", timeout=60)
        fact("Sig: restored", "client accepts")


    @stage
    def push():
        """force a re-evaluation"""
        hydra.succeed("curl --silent --fail --request POST http://localhost:3000/api/push?jobsets=demo:main"
                      " --header 'Accept: application/json' >/dev/null")
        print("re-evaluation triggered")


    @stage
    def status():
        """safe at any time: every box, every job, the release cache"""
        head("status")
        for m, name in [(internet, "internet"), (scanner, "scanner"), (fodcache, "fodcache"),
                        (hydra, "hydra"), (builder1, "builder1"), (signer, "signer"),
                        (cache, "cache"), (client, "client")]:
            print(f"  {name:10} {'up' if m.booted else 'down'}")
        if hydra.booted:
            for job in JOBS:
                st, out = hydra.execute(api(f"/job/demo/main/{job}/latest") + " | jq --raw-output .buildstatus")
                print(f"  {job:26} {out.strip() if st == 0 else 'no build yet'}")
        if cache.booted:
            st, out = cache.execute("ls /var/lib/release-cache/*.narinfo 2>/dev/null | wc --lines")
            print(f"  release cache: {out.strip()} narinfo(s)")


    # one beat per machine boundary: a 20-minute slot cannot carry thirteen pauses
    @stage
    def seed():
        """internet + scanner: the online world shrinks into one signed bundle"""
        boot_online()
        bundle()
        scan()


    @stage
    def cross():
        """the boundary: carry it over, import it, prove the gap"""
        carry()
        import_bundle()
        air_gap()


    @stage
    def prove():
        """hydra: evaluate, build with no network, show what it actually did"""
        hydra_up()
        builds()
        proof()


    @stage
    def release():
        """signer + client: one released, one refused, one trusted key"""
        punchline()
        consume()


    # one source of truth for the order: CI runs it straight through,
    # demo() walks it a beat at a time
    STEPS = [
        ("the online world shrinks into one signed bundle", seed),
        ("across the air gap (which is, indeed, made of air)", cross),
        ("hydra builds it with no network at all", prove),
        ("released, signed, and the client takes it", release),
    ]

    MENU = """
    offline build site

      demo()    step through the story, pausing before each beat
    """


    @stage
    def demo(start=1):
        """walk the story, blocking before each beat"""
        serial_stdout_off()
        quiet()
        for i, (title, fn) in enumerate(STEPS, start=1):
            if i < start:
                continue
            print(f"\n\n[{i}/{len(STEPS)}]  next: {title}")
            try:
                input("         enter to run  -  ctrl-c to stop > ")
            except (EOFError, KeyboardInterrupt):
                print(f"\nstopped before step {i}. resume with: demo({i})")
                return
            try:
                fn()
            except KeyboardInterrupt:
                print(f"\ninterrupted in step {i}. retry with: demo({i})")
                return
        print("\noffline build site demo: all checks hold")


    @stage
    def run_all():
        for _, fn in STEPS:
            fn()
            # CI only: real proofs the test must keep, but an arc too many
            # for a 20-minute stage
            if fn is cross:
                sabotage()
            if fn is release:
                client_refuses()
        print("\noffline build site demo: all checks hold")


    # nothing waits here: by the time a stage needs a machine it has had a head start
    start_all()

    if INTERACTIVE:
        serial_stdout_off()
        print(MENU)
    else:
        run_all()
  '';
}
