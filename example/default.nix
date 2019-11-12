{ sourcePaths ? import ./nix/sources.nix
, system ? builtins.currentSystem
, crossSystem ? null
, config ? {}
}@args: with import ./nix args; {
  shell = mkShell {
    buildInputs = [ niv nixops nix ];
    passthru = {
      gen-graylog-creds = iohk-ops-lib.scripts.gen-graylog-creds { staticPath = ./static; };
    };
  };
}
