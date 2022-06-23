{ config, pkgs, ... }: {
  users = {
    mutableUsers = false;
    defaultUserShell = pkgs.fish;
    users = {
      root = {
        # disable root login here, and also when installing nix by running nixos-install --no-root-passwd
        # https://discourse.nixos.org/t/how-to-disable-root-user-account-in-configuration-nix/13235/3
        hashedPassword = "!"; # disable root logins, nothing hashes to !
      };
      test = {
        isNormalUser = true;
        description = "Non-sudo account for testing new config options that could break login.  If need sudo for testing, add 'wheel' to extraGroups and rebuild.";
        initialPassword = "password";
        extraGroups = [ "networkmanager" ];
      };
      lfron = {
        isNormalUser = true;
        description = "Logan Fron";
        hashedPassword = "$6$ovjrHbT8FxLvXNCP$ZSYRVZ5nrQBEy1dewTb/s90yqs5KDoT7ytYiv6lEKFHjqEZKXWt4vp/dAvGZ4fT/KYuazRp9x32IRVPNl457d.";
        extraGroups = [ "wheel" "networkmanager" "adbusers" "libvirtd" "kvm" "lxd" ];
        openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFf8CPNUMwqUiQ3QFEZSOr2K1cNwY7bHw32pg75o2TMt JuiceSSH" ];
      };
    };
  };

  environment.variables = rec {
    XDG_CACHE_HOME = "\${HOME}/.cache";
    XDG_STATE_HOME = "\${HOME}/.local/state";
    XDG_CONFIG_HOME = "\${HOME}/.config";
    XDG_BIN_HOME = "\${HOME}/.local/bin";
    XDG_DATA_HOME = "\${HOME}/.local/share";
    QT_QPA_PLATFORMTHEME = "qt5ct";
  };
}
