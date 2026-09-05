# profile：主机声明的启用包（与 moduleGroups 的模块侧 all-of 硬依赖语义不同）
# 分侧写法：podman 只有 nixos.nix，仅在 NixOS 侧启用
{
  nixos = [ "workstation.podman" ];
}
