{ lib, pkgs, defaultWeechatScriptOverrides }:
let
  pythonPackages = pkgs.python27Packages;

  json = builtins.fromJSON (builtins.readFile ./scripts.json);

  mkScript = {
    name,
    language,
    md5sum,
    version,
    description,
    url ? null,
    gh_url ? null,
    license,
    sha256 ? null,
    sha512 ? null
  }: 
  assert sha256 == null -> sha512 != null;
  assert sha512 == null -> sha256 != null;
  assert url == null -> gh_url != null;
  assert gh_url == null -> url != null;
  let
    ext = {
      "python" = "py";
      "perl" = "pl";
      "lua" = "lua";
      "javascript" = "js";
      "guile" = "scm";
      "ruby" = "rb";
      "tcl" = "tcl";
    }.${language};
  in pkgs.stdenvNoCC.mkDerivation {
    src = pkgs.fetchurl {
      name = "${name}-${version}";
      url = if gh_url != null then gh_url else url;
      inherit sha256 sha512;
    };
    
    unpackPhase = ":";

    name = "weechat-plugin-${name}-${version}";
    installPhase = ''
      mkdir -p $out/share
      cp $src $out/share/${name}.${ext}
    '';

    passthru = {
      inherit language;
      scripts = [ "${name}.${ext}" ];
    };

    meta = {
      inherit description license;
    };
  };
in
  lib.mapAttrs (n: v: let 
      script = mkScript v;
      override = defaultWeechatScriptOverrides.${n} or null;
    in if (override != null) then script.overrideAttrs override else script
  ) json
