# sops.nix — cloud.sops helpers
{ projectRoot }:

rec {
  commonFile = projectRoot + "/secrets/common.yaml";
  hostFile = host: projectRoot + "/secrets/hosts/${host}.yaml";
  defaultFile = host: if host == null then commonFile else hostFile host;

  # secret { source; host?; name?; }
  #
  # source = "common"              → { sopsFile = .../secrets/common.yaml; }
  # source = "host"; host = "foo"  → { sopsFile = .../secrets/hosts/foo.yaml; }
  # source = "host"（无 host）     → 返回 NixOS module，在求值时从 config.networking.hostName 推导
  #
  # 加 name 时直接返回 { sops.secrets.<name> = ...; } / module（适合 imports = [...]）
  secret =
    {
      source,
      host ? null,
      name ? null,
    }:
    let
      makeOptions = sopsFile: { inherit sopsFile; };

      wrapName =
        options:
        if name == null then
          options
        else if builtins.isString name && name != "" then
          { sops.secrets.${name} = options; }
        else
          throw "cloud.sops.secret.name 必须是非空字符串";

      # 纯属性集路径（host 已知）
      staticOptions =
        if source == "common" then
          makeOptions commonFile
        else if source == "host" && host != null then
          makeOptions (hostFile host)
        else
          null;

      # NixOS module 路径（source = "host"，host 未提供，延迟到求值）
      dynamicModule =
        { config, ... }:
        let
          h = config.networking.hostName;
          opts = makeOptions (hostFile h);
        in
        wrapName opts;
    in
    if staticOptions != null then
      wrapName staticOptions
    else if source == "host" then
      dynamicModule
    else
      throw "cloud.sops.secret.source 必须是 \"common\" 或 \"host\"";

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
