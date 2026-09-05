{
  lib,
  profileTools,
}:
{
  profileSuccessChecks = {
    listFormBothSides =
      profileTools.readProfile {
        name = "workstation";
        value = [
          "a"
          "b"
        ];
        source = "test fixture";
      } == {
        extends = [ ];
        nixos = [
          "a"
          "b"
        ];
        home = [
          "a"
          "b"
        ];
      };
  };
}