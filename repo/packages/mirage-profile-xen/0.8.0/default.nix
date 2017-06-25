world:
let
    fetchurl = pkgs.fetchurl;
    inputs = lib.filter (dep: dep != true && dep != null)
    ([  ] ++ (lib.attrValues opamDeps));
    lib = pkgs.lib;
    opam2nix = world.opam2nix;
    opamDeps = 
    {
      io-page = opamSelection.io-page;
      jbuilder = opamSelection.jbuilder;
      mirage-profile = opamSelection.mirage-profile;
      mirage-xen-minios = opamSelection.mirage-xen-minios;
      ocaml = opamSelection.ocaml;
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
  name = "mirage-profile-xen-0.8.0";
  opamEnv = builtins.toJSON 
  {
    deps = opamDeps;
    files = null;
    name = "mirage-profile-xen";
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
    sha256 = "0wb4qgn59jzadij9va0qpc111lwi30ixf7sk0xvn1g4xs7khkg1m";
    url = "https://github.com/mirage/mirage-profile/releases/download/0.8.0/mirage-profile-0.8.0.tbz";
  };
  unpackCmd = "tar -xf \"$curSrc\"";
}
