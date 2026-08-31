{ projectRoot }:

rec {
  commonFile = projectRoot + "/secrets/common.yaml";
  hostFile = host: projectRoot + "/secrets/hosts/${host}.yaml";
  defaultFile = host: if host == null then commonFile else hostFile host;

  secret =
    {
      source,
      host ? null,
      config ? null,
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

      hostnameFromConfig =
        if config == null then
          null
        else
          let
            value = config.networking.hostName or null;
          in
          if builtins.isString value && value != "" then
            value
          else
            throw "cloud.sops.secret.config.networking.hostName 必须是非空字符串";

      staticOptions =
        if source == "common" then
          if config != null then
            throw "cloud.sops.secret.config 仅可用于 source = \"host\""
          else
            makeOptions commonFile
        else if source == "host" && host != null then
          makeOptions (hostFile host)
        else if source == "host" && config != null then
          makeOptions (hostFile hostnameFromConfig)
        else
          null;

      dynamicModule =
        { config, ... }:
        let
          hostname = config.networking.hostName;
        in
        if builtins.isString hostname && hostname != "" then
          wrapName (makeOptions (hostFile hostname))
        else
          throw "cloud.sops.secret 无法从 config.networking.hostName 推导主机名";
    in
    if host != null && config != null then
      throw "cloud.sops.secret 不能同时传入 host 和 config"
    else if staticOptions != null then
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
