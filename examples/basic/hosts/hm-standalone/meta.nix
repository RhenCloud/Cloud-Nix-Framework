{
  system = "x86_64-linux";
  roles = [ "server" ];
  profiles = [ "workstation" ];

  # profile 启用的成员仍可被主机级覆盖显式禁用（验证仍走 override）
  modules."workstation.podman" = false;

  home.embed = false;
}
