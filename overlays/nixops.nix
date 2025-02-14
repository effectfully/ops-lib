self: super: {
  nixops = (import (self.sourcePaths.nixops-core + "/release.nix") {
    nixpkgs = self.path;
    p = p:
      let
        pluginSources = with self.sourcePaths; [ nixops-libvirtd ];
        plugins = map (source: p.callPackage (source + "/release.nix") { })
          pluginSources;
      in [ p.aws ] ++ plugins;
  }).build.${self.stdenv.system};
}
