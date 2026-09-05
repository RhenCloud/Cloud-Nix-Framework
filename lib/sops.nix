{
  projectRoot,
  sopsLayout ? null,
}:

let
  defaultLayout = {
    commonFile = projectRoot + "/secrets/common.yaml";
    hostFile = host: projectRoot + "/secrets/hosts/${host}.yaml";
  };
  effectiveLayout =
    if sopsLayout == null then
      defaultLayout
    else
      defaultLayout // sopsLayout;
in

rec {
  inherit (effectiveLayout) commonFile hostFile;
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
          throw "snowveil.sops.secret.name must be a non-empty string";

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
            throw "snowveil.sops.secret.config.networking.hostName must be a non-empty string";

      staticOptions =
        if source == "common" then
          if config != null then
            throw "snowveil.sops.secret.config is only valid with source = \"host\""
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
          throw "snowveil.sops.secret could not derive hostname from config.networking.hostName";
    in
    if host != null && config != null then
      throw "snowveil.sops.secret cannot receive both host and config"
    else if staticOptions != null then
      wrapName staticOptions
    else if source == "host" then
      dynamicModule
    else
      throw "snowveil.sops.secret.source must be \"common\" or \"host\"";

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
