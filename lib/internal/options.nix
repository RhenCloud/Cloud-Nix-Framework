# 框架内置的 NixOS/HM 选项定义
# 模块内部通过 { lib, ... } 拿到自己的 lib，此处不需要外层 lib。
_:

{
  optionsSnowveil =
    { lib, ... }:
    {
      options.snowveil = {
        users = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        homeManager = {
          backupFileExtension = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "backupFileExtension for the embedded home-manager module; only takes effect when HM embedding is enabled for this host.";
          };
          embed = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            description = "Read-only view of the current embed policy. The actual value is controlled by hosts/<host>/meta.nix (home.embed field) or mkFlake's embedHomeManager parameter.";
          };
        };
      };
    };

  optionsSnowveilHome =
    { lib, ... }:
    {
      options.snowveil = {
        users = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      };
    };
}
