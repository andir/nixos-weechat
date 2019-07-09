{ config, lib, pkgs, ...}:
let

  unstable_pkgs = import <nixos-unstable> {};

  defaultWeechatScriptOverrides = {
    weetris = attrs: {};
    otr = attrs: {
      nativeBuildInputs = (attrs.nativeBuildInputs or []) ++ [unstable_pkgs.pythonPackages.wrapPython];
      pythonPath = with unstable_pkgs.python.pkgs; [ (potr.overridePythonAttrs (oldAttrs: {
        propagatedBuildInputs  = [
          (buildPythonPackage rec {
            name = "pycrypto-${version}";
            version = "2.6.1";

            src = pkgs.fetchurl {
              url = "mirror://pypi/p/pycrypto/${name}.tar.gz";
              sha256 = "0g0ayql5b9mkjam8hym6zyg6bv77lbh66rv1fyvgqb17kfc1xkpj";
            };

            patches = pkgs.stdenv.lib.singleton (pkgs.fetchpatch {
              name = "CVE-2013-7459.patch";
              url = "https://anonscm.debian.org/cgit/collab-maint/python-crypto.git"
                + "/plain/debian/patches/CVE-2013-7459.patch?h=debian/2.6.1-7";
              sha256 = "01r7aghnchc1bpxgdv58qyi2085gh34bxini973xhy3ks7fq3ir9";
            });

            buildInputs = [ pkgs.gmp ];

            preConfigure = ''
              sed -i 's,/usr/include,/no-such-dir,' configure
              sed -i "s!,'/usr/include/'!!" setup.py
            '';
          })
        ];
      }))];
      fixupPhase = ''
        buildPythonPath "$out $pythonPath"
        patchPythonScript $out/share/*
      '';
    };
  };


  scripts = unstable_pkgs.callPackage ./scripts.nix { inherit defaultWeechatScriptOverrides; };
  pkg = unstable_pkgs.weechat-unwrapped.overrideAttrs (old: { patches = [ ./upgrade.patch ]; });
  configuredPkg = unstable_pkgs.wrapWeechat pkg {
    configure = { availablePlugins, ...}: {
      plugins = builtins.attrValues availablePlugins;
      scripts = with scripts; [
        autojoin
        autojoin_on_invite
        autosort
        # bandwidth
        buffer_autoclose
        buffer_autoset
        chanmon
        colorize_nicks
        emote
        go
        grep
        keepnick
        listbuffer
        otr
        parse_relayed_msg
        topicdiff
        weetris
        whois_on_query
      ];
    };
  };

  tmuxConf = pkgs.writeText "tmux.conf" ''
     unbind-key -a
     set -g status off
     set -g default-terminal "tmux-256color"
     set -ga terminal-overrides ",*256col*:Tc"
     set -g bell-action any
  '';
in {

  users = {
    groups.weechat = {
      members = [ "andi" ];
    };
    users.weechat = {
      createHome = true;
      group = "weechat";
      home = "/var/lib/weechat";
#      isSystemUser = true;
      isNormalUser = true;
      packages = with pkgs; [
        aspell
        aspellDicts.en
        aspellDicts.en-computers
        aspellDicts.en-science
      ];
    };
  };
  systemd.services.weechat = {
    environment = {
      WEECHAT_HOME = "/var/lib/weechat";
      ASPELL_CONF = "dict-dir ${pkgs.buildEnv {
        name = "aspell-all-dicts";
        paths = lib.collect lib.isDerivation pkgs.aspellDicts;
      }}/lib/aspell";
    };
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.RequiresMountsFor = "/var/lib/weechat";
    serviceConfig = {
      User = "weechat";
      Group = "weechat";
      Type = "forking";
      RemainAfterExit = "yes";
      ExecStart = "${pkgs.tmux}/bin/tmux -f ${tmuxConf} -S /var/lib/weechat/tmux.session new-session -d -s irc '${configuredPkg}/bin/weechat'";
      ExecStop = "${pkgs.tmux}/bin/tmux -f ${tmuxConf} -S /var/lib/weechat/tmux.session kill-session -t irc";
    };
    postStart = ''
      chmod 660 /var/lib/weechat/tmux.session
      chmod g+rX /var/lib/weechat
    '';
    reload = ''
      echo "*/upgrade -yes ${configuredPkg}/bin/weechat" > /var/lib/weechat/weechat_fifo
      # FIXME: script reloading?!?
    '';
    restartIfChanged = false;
    reloadIfChanged = true;
  };

  networking.firewall.allowedTCPPorts = [ 9001 ]; # weechat relay

}
