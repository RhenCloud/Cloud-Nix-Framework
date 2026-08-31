{
  requires = [ "_common.always" ];
  before = [ "desktop.example" ];
  conflicts = [ "server.demo" ];
}
