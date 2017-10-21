world:
let
    inputs = lib.filter (dep: dep != true && dep != null)
    ([ (pkgs.qt5 or null) (pkgs.qt5-default or null) (pkgs.qt5-qmake or null)
        (pkgs.qt5-qtbase-dev or null) (pkgs.qt5-qtbase-devel or null)
        (pkgs.qt5-qtdeclarative-dev or null)
        (pkgs.qt5-qtdeclarative-devel or null)
        (pkgs.qtdeclarative5-dev or null) ] ++ (lib.attrValues opamDeps));
    lib = pkgs.lib;
    opam2nix = world.opam2nix;
    opamDeps = 
    {
      ocaml = opamSelection.ocaml;
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
  name = "conf-qt-5.2.1";
  opamEnv = builtins.toJSON 
  {
    deps = opamDeps;
    files = null;
    name = "conf-qt";
    ocaml-version = world.ocamlVersion;
    spec = ./opam;
  };
  passthru = 
  {
    opamSelection = opamSelection;
  };
  propagatedBuildInputs = inputs;
  unpackPhase = "true";
}

