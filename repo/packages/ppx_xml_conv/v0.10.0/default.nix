world:
let
    fetchurl = pkgs.fetchurl;
    inputs = lib.filter (dep: dep != true && dep != null)
    ([  ] ++ (lib.attrValues opamDeps));
    lib = pkgs.lib;
    opam2nix = world.opam2nix;
    opamDeps = 
    {
      csvfields = opamSelection.csvfields;
      jbuilder = opamSelection.jbuilder;
      ocaml = opamSelection.ocaml;
      ocaml-migrate-parsetree = opamSelection.ocaml-migrate-parsetree;
      ocamlfind = opamSelection.ocamlfind or null;
      ppx_conv_func = opamSelection.ppx_conv_func;
      ppx_core = opamSelection.ppx_core;
      ppx_driver = opamSelection.ppx_driver;
      ppx_fields_conv = opamSelection.ppx_fields_conv;
      ppx_metaquot = opamSelection.ppx_metaquot;
      ppx_type_conv = opamSelection.ppx_type_conv;
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
  name = "ppx_xml_conv-v0.10.0";
  opamEnv = builtins.toJSON 
  {
    deps = opamDeps;
    files = null;
    name = "ppx_xml_conv";
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
    sha256 = "17dda63misprgirqwk0p8qbcr6n7bpbrapgbgdcry8gm9s0xfvwl";
    url = "https://ocaml.janestreet.com/ocaml-core/v0.10/files/ppx_xml_conv-v0.10.0.tar.gz";
  };
}
