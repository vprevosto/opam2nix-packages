world:
let
    fetchurl = pkgs.fetchurl;
    inputs = lib.filter (dep: dep != true && dep != null)
    ([  ] ++ (lib.attrValues opamDeps));
    lib = pkgs.lib;
    opam2nix = world.opam2nix;
    opamDeps = 
    {
      alcotest = opamSelection.alcotest or null;
      base-bytes = opamSelection.base-bytes;
      base-threads = opamSelection.base-threads;
      base-unix = opamSelection.base-unix;
      bos = opamSelection.bos;
      cmdliner = opamSelection.cmdliner;
      cstruct = opamSelection.cstruct;
      duration = opamSelection.duration;
      fmt = opamSelection.fmt;
      logs = opamSelection.logs;
      lwt = opamSelection.lwt;
      mirage-flow-lwt = opamSelection.mirage-flow-lwt;
      mirage-time-lwt = opamSelection.mirage-time-lwt;
      ocaml = opamSelection.ocaml;
      ocamlbuild = opamSelection.ocamlbuild;
      ocamlfind = opamSelection.ocamlfind;
    };
    opamSelection = world.opamSelection;
    pkgs = world.pkgs;
in
pkgs.stdenv.mkDerivation 
{
  buildInputs = inputs;
  buildPhase = "${opam2nix}/bin/opam2nix invoke build";
  configurePhase = "true";
  installPhase = "${opam2nix}/bin/opam2nix invoke install";
  name = "hvsock-0.14.0";
  opamEnv = builtins.toJSON 
  {
    deps = opamDeps;
    files = null;
    name = "hvsock";
    ocaml-version = world.ocamlVersion;
    spec = ./opam;
  };
  passthru = 
  {
    opamSelection = opamSelection;
  };
  propagatedBuildInputs = inputs;
  src = fetchurl 
  {
    sha256 = "1k3f3k74hknn9qznmrzdbi09m38sd4mqkpqrqmv6lkdvqqzf5w4c";
    url = "https://github.com/mirage/ocaml-hvsock/archive/v0.14.0.tar.gz";
  };
}
