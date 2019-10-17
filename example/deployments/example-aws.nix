with import <nixpkgs> {};
let
  inherit (pkgs.lib)
    attrValues filter filterAttrs flatten foldl' hasAttrByPath listToAttrs
    mapAttrs' nameValuePair recursiveUpdate unique;

  inherit (globals.ec2) credentials;
  inherit (credentials) accessKeyId;
  inherit (iohk-ops-lib.physical) aws;

  cluster = import ../clusters/example.nix pkgs {
    inherit (aws) targetEnv;
    tiny = aws.t2nano;
    large = aws.t3xlarge;
  };

  nodes = filterAttrs (name: node:
    ((node.deployment.targetEnv or null) == "ec2")
    && ((node.deployment.ec2.region or null) != null)) cluster;

  regions =
    unique (map (node: node.deployment.ec2.region) (attrValues nodes));

  securityGroups = with aws.security-groups; [
    allow-all
    allow-ssh
    # allow-deployer-ssh
    allow-monitoring-collection
    allow-public-www-https
  ];

  importSecurityGroup = region: securityGroup:
    securityGroup { inherit region accessKeyId; };

  mkEC2SecurityGroup = region:
    foldl' recursiveUpdate { }
    (map (importSecurityGroup region) securityGroupFiles);

  settings = {
    resources = {
      ec2SecurityGroups =
        foldl' recursiveUpdate { } (map mkEC2SecurityGroup regions);

      elasticIPs = mapAttrs' (name: node:
        nameValuePair "${name}-ip" {
          inherit accessKeyId;
          inherit (node.deployment.ec2) region;
        }) nodes;

      ec2KeyPairs = listToAttrs (map (region:
        nameValuePair "${config.deployment.name}-${region}" { inherit region accessKeyId; })
        regions);
    };
  };
in
  cluster // settings
