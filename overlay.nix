final: prev: {
  demo-keys = final.callPackage ./demo-keys { };
  demo-project = final.callPackage ./demo-project { };
  fod-bundler = final.callPackage ./pkgs/fod-bundler { };
  fod-scanner = final.callPackage ./pkgs/fod-scanner { };
}
