# sops.nix — cloud.sops helpers
{ projectRoot }:

rec {
  commonFile = projectRoot + "/secrets/common.yaml";
  hostFile = host: projectRoot + "/secrets/hosts/${host}.yaml";
  defaultFile = host: if host == null then commonFile else hostFile host;
  secret =
    {
      source,
      host ? null,
      name ? null,
    }:
    let
      options = {
        sopsFile =
          if source == "common" then
            commonFile
          else if source == "host" && host != null then
            hostFile host
          else if source == "host" then
            throw "cloud.sops.secret 使用 source = \"host\" 时必须传入 host"
          else
            throw "cloud.sops.secret.source 必须是 \"common\" 或 \"host\"";
      };
    in
    if name == null then
      options
    else if builtins.isString name && name != "" then
      { sops.secrets.${name} = options; }
    else
      throw "cloud.sops.secret.name 必须是非空字符串";
  mkModule =
    {
      sopsNixModule,
      host ? null,
      defaultSopsFile ? defaultFile host,
    }:
    { ... }:
    {
      imports = [ sopsNixModule ];
      sops = {
        defaultSopsFormat = "yaml";
        inherit defaultSopsFile;
      };
    };
}
