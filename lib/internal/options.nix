# 框架内置的 NixOS/HM 选项定义
{ lib }:

{
  optionsCloud =
    { lib, ... }:
    {
      options.cloud = {
        users = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        homeManager = {
          backupFileExtension = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "嵌入式 home-manager 的 backupFileExtension；仅当该主机启用了 HM 嵌入时生效";
          };
          embed = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            description = "仅读取用；实际嵌入策略由 hosts/<host>/meta.nix 的 home.embed 字段或 mkFlake 的 embedHomeManager 参数控制";
          };
        };
      };
    };

  optionsCloudHome =
    { lib, ... }:
    {
      options.cloud = {
        users = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      };
    };
}
