with import ../nix {};
let
  inherit (pkgs.lib)
    attrValues attrNames filter filterAttrs flatten foldl' hasAttrByPath listToAttrs
    mapAttrs' mapAttrs nameValuePair recursiveUpdate unique optional any concatMap;

  inherit (globals.ec2.credentials) accessKeyIds;
  inherit (iohk-ops-lib.physical) aws;

  cluster = import ../clusters/example.nix pkgs {
    inherit (aws) targetEnv;
    tiny = aws.t2nano;
    medium = aws.t2xlarge;
    large = aws.t3xlarge;
  };

  nodes = filterAttrs (name: node:
    ((node.deployment.targetEnv or null) == "ec2")
    && ((node.deployment.ec2.region or null) != null)) cluster;

  regions =
    unique (map (node: node.deployment.ec2.region) (attrValues nodes));

  orgs =
    unique (map (node: node.node.org) (attrValues nodes));

  securityGroups = with aws.security-groups; [
    {
      nodes = filterAttrs (_: n: n.node.roles.isMonitor) nodes;
      groups = [
        allow-public-www-https
        allow-graylog
      ];
    }
    {
      inherit nodes;
      groups = [
        allow-deployer-ssh
      ]
      ++ optional (any (n: n.node.roles.isMonitor) (attrValues nodes))
        allow-monitoring-collection;
    }
  ];

  importSecurityGroup =  node: securityGroup:
    securityGroup {
      inherit pkgs lib nodes;
      region = node.deployment.ec2.region;
      org = node.node.org;
      accessKeyId = pkgs.globals.ec2.credentials.accessKeyIds.${node.node.org};
    };


  importSecurityGroups = {nodes, groups}:
    mapAttrs
      (_: n: foldl' recursiveUpdate {} (map (importSecurityGroup n) groups))
      nodes;

  securityGroupsByNode =
    foldl' recursiveUpdate {} (map importSecurityGroups securityGroups);

  settings = {
    resources = {
      ec2SecurityGroups =
        foldl' recursiveUpdate {} (attrValues securityGroupsByNode);

      elasticIPs = mapAttrs' (name: node:
        nameValuePair "${name}-ip" {
          accessKeyId = accessKeyIds.${node.node.org};
          inherit (node.deployment.ec2) region;
        }) nodes;

      ec2KeyPairs = listToAttrs (concatMap (region:
        map (org:
          nameValuePair "example-keypair-${org}-${region}" {
            inherit region;
            accessKeyId = accessKeyIds.${org};
          }
        ) orgs)
        regions);
    };
    defaults = { name, resources, config, ... }: {
      _file = ./example-aws.nix;
      deployment.ec2 = {
        keyPair = resources.ec2KeyPairs."example-keypair-${config.node.org}-${config.deployment.ec2.region}";
        securityGroups = map (sgName: resources.ec2SecurityGroups.${sgName})
          (attrNames (securityGroupsByNode.${name} or {}));
      };
    };
  };
in
  cluster // settings
