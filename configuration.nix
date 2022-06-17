# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

let

 #Sway GTK stuff
  # bash script to let dbus know about important env variables and
  # propogate them to relevent services run at the end of sway config
  # see
  # https://github.com/emersion/xdg-desktop-portal-wlr/wiki/"It-doesn't-work"-Troubleshooting-Checklist
  # note: this is pretty much the same as  /etc/sway/config.d/nixos.conf but also restarts  
  # some user services to make sure they have the correct environment variables
  dbus-sway-environment = pkgs.writeTextFile {
    name = "dbus-sway-environment";
    destination = "/bin/dbus-sway-environment";
    executable = true;

    text = ''
  dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway
  systemctl --user stop pipewire pipewire-media-session xdg-desktop-portal xdg-desktop-portal-wlr
  systemctl --user start pipewire pipewire-media-session xdg-desktop-portal xdg-desktop-portal-wlr
      '';
  };
 
  # currently, there is some friction between sway and gtk:
  # https://github.com/swaywm/sway/wiki/GTK-3-settings-on-Wayland
  # the suggested way to set gtk settings is with gsettings
  # for gsettings to work, we need to tell it where the schemas are
  # using the XDG_DATA_DIR environment variable
  # run at the end of sway config
  configure-gtk = pkgs.writeTextFile {
      name = "configure-gtk";
      destination = "/bin/configure-gtk";
      executable = true;
      text = let
        schema = pkgs.gsettings-desktop-schemas;
        datadir = "${schema}/share/gsettings-schemas/${schema.name}";
      in ''
        export XDG_DATA_DIRS=${datadir}:$XDG_DATA_DIRS
        gnome_schema=org.gnome.desktop.interface
        gsettings set $gnome_schema gtk-theme 'Adapta-Nokto'
        '';
  };

in
{
################################################################################
# System 
################################################################################

  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];
    
  # Default nixPath.  Uncomment and modify to specify non-default nixPath
  # https://search.nixos.org/options?query=nix.nixPath
  #nix.nixPath =
  #  [
  #    "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
  #    "nixos-config=/persist/etc/nixos/configuration.nix"
  #    "/nix/var/nix/profiles/per-user/root/channels"
  #  ];
  
  # Enable non-free packages (Nvidia driver, etc)
  # Reboot after rebuilding to prevent possible clash with other kernel modules
  nixpkgs.config = {
    allowUnfree = true;
  };

  # Make nixos-rebuild snapshot the current configuration.nix to 
  # /run/current-system/configuration.nix
  # With this enabled, every new system profile contains the configuration.nix
  # that created it.  Useful in troubleshooting broken build, just diff 
  # current vs prior working configurion.nix.  This will only copy configuration.nix
  # and no other imported files, so put all config in this file.  
  # Configuration.nix should have no imports besides hardware-configuration.nix.
  # https://search.nixos.org/options?query=system.copySystemConfiguration
  system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.05"; # Did you read the comment?
  
  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };
  
  time.timeZone = "America/New_York";

################################################################################
# Boot
################################################################################

  # import /persist into initial ramdisk so that tmpfs can access persisted data like user passwords
  # https://www.reddit.com/r/NixOS/comments/o1er2p/tmpfs_as_root_but_without_hardcoding_your/h22f1b9/
  # https://search.nixos.org/options?channel=21.05&show=fileSystems.%3Cname%3E.neededForBoot&query=fileSystems.%3Cname%3E.neededForBoot
  fileSystems."/persist".neededForBoot = true;
  
  # Use EFI boot loader with Grub.
  # https://nixos.org/manual/nixos/stable/index.html#sec-installation-partitioning-UEFI
  boot = {
    kernelPackages = pkgs.linuxPackages_zen;
    supportedFilesystems = [ "vfat" "zfs" ];
    loader = {
      #systemd-boot.enable = true;
      efi = {
        #canTouchEfiVariables = true;  # must be disabled if efiInstallAsRemovable=true
        #efiSysMountPoint = "/boot/efi";  # using the default /boot for this config
      };
      grub = {
        enable = true;
        efiSupport = true;
        efiInstallAsRemovable = true;  # grub will use efibootmgr 
        zfsSupport = true;
         copyKernels = true;  # https://nixos.wiki/wiki/NixOS_on_ZFS
        device = "nodev";  # "/dev/sdx", or "nodev" for efi only
      };
    };
  };

################################################################################
# ZFS
################################################################################

  # Set the disk’s scheduler to none. ZFS takes this step automatically 
  # if it controls the entire disk, but since it doesn't control the /boot 
  # partition we must set this explicitly.
  # source: https://grahamc.com/blog/nixos-on-zfs
  boot.kernelParams = [ "elevator=none" ];

  boot.zfs = {
    enableUnstable = true;
    requestEncryptionCredentials = true; # enable if using ZFS encryption, ZFS will prompt for password during boot
  };

  services.zfs = {
    autoScrub.enable = true;
    autoSnapshot.enable = true;
    # TODO: autoReplication
  };

################################################################################
# Networking
################################################################################

  networking = {
    #hostId = "$(head -c 8 /etc/machine-id)";  # required by zfs. hardware-specific so should be set in hardware-configuration.nix
    hostName = "nixPC";  # Any arbitrary hostname.
    #wireless.enable = true;  # Wireless via wpa_supplicant. Unecessary with Gnome.

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
    useDHCP = false;
    interfaces = {
      enp1s0.useDHCP = true;
    };
  };
  
################################################################################
# Persisted Artifacts
################################################################################

  #Erase Your Darlings & Tmpfs as Root:
  # config/secrets/etc to be persisted across tmpfs reboots and rebuilds.  setup
  # soft-links from /persist/<loc on root> to their expected location on /<loc on root>
  # https://github.com/barrucadu/nixfiles/blob/master/hosts/nyarlathotep/configuration.nix
  # https://grahamc.com/blog/erase-your-darlings
  # https://elis.nu/blog/2020/05/nixos-tmpfs-as-root/
  
  environment.etc = {

    # /etc/nixos: requires /persist/etc/nixos 
    "nixos".source = "/persist/etc/nixos";
    
        #NetworkManager/system-connections: requires /persist/etc/NetworkManager/system-connections
    "NetworkManager/system-connections".source = "/persist/etc/NetworkManager/system-connections/";
    
    # machine-id is used by systemd for the journal, if you don't persist this 
    # file you won't be able to easily use journalctl to look at journals for 
    # previous boots.
    "machine-id".source = "/persist/etc/machine-id";
    
    # if you want to run an openssh daemon, you may want to store the host keys 
    # across reboots.
        "ssh/ssh_host_rsa_key".source = "/persist/etc/ssh/ssh_host_rsa_key";
  "ssh/ssh_host_rsa_key.pub".source = "/persist/etc/ssh/ssh_host_rsa_key.pub";
  "ssh/ssh_host_ed25519_key".source = "/persist/etc/ssh/ssh_host_ed25519_key";
  "ssh/ssh_host_ed25519_key.pub".source = "/persist/etc/ssh/ssh_host_ed25519_key.pub";

  };
  
  #2. Wireguard:  requires /persist/etc/wireguard/
  networking.wireguard.interfaces.wg0 = {
    generatePrivateKeyFile = true;
    privateKeyFile = "/persist/etc/wireguard/wg0";
  };
  
  #3. Bluetooth: requires /persist/var/lib/bluetooth
  #4. ACME certificates: requires /persist/var/lib/acme  
  systemd.tmpfiles.rules = [
    "L /var/lib/bluetooth - - - - /persist/var/lib/bluetooth"
    "L /var/lib/bluetooth - - - - /persist/var/lib/bluetooth" 
    "L /var/lib/acme - - - - /persist/var/lib/acme"
  ];

################################################################################
# GnuPG & SSH
################################################################################

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    permitRootLogin = "no";
    passwordAuthentication = true;
    hostKeys =
      [
        {
          path = "/persist/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
        {
          path = "/persist/etc/ssh/ssh_host_rsa_key";
          type = "rsa";
          bits = 4096;
        }
      ];
  };
  
  # Enable GnuPG Agent
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

################################################################################
# XServer & Drivers
################################################################################
  
  hardware.opengl = {
    driSupport = true;  # install and enable Vulkan: https://nixos.org/manual/nixos/unstable/index.html#sec-gpu-accel
    driSupport32Bit = true;
  };
  
  # Enable X11 + Nvidia
  # https://nixos.org/manual/nixos/unstable/index.html#sec-gnome-gdm
  #services.xserver = {
  #  enable = true;  # enable X11
  #  layout = "us";
  #  xkbOptions = "eurosign:e";
  #  #videoDrivers = [ "nvidia" ];  # seems unecessary if nixpkgs.config.allowUnfree=true (above in System section);
  #};
  
################################################################################
# Window Managers & Desktop Environment
################################################################################

  # Enable gdm + GNOME
  #services.xserver = {
  #  desktopManager.gnome.enable = true;
  #  displayManager.gdm.enable = true;
  #};
  #services.gnome.core-developer-tools.enable = true;
  
  services.dbus.enable = true;
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    # gtk portal needed to make gtk apps happy
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    gtkUsePortal = true;
  };
  
  # enable sway window manager
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };
  
################################################################################
# Print
################################################################################

  # Enable CUPS to print documents.
  services.printing.enable = true;
  
################################################################################
# Sound
################################################################################
  
  # Enable sound.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    jack.enable = true;
  };

################################################################################
# Input
################################################################################

  # Enable touchpad support (enabled by default in most desktopManagers).
  # services.xserver.libinput.enable = true;

################################################################################
# Users
################################################################################

  # When using a password file via users.users.<name>.passwordFile, put the 
  # passwordFile in the specified location *before* rebooting, or you will be 
  # locked out of the system.  To create this file, make a single file with only 
  # a password hash in it, compatible with `chpasswd -e`.  Or you can copy-paste 
  # your password hash from `/etc/shadow` if you first built the system with 
  # `password=`, `hashedPassword=`, initialPassword-, or initialHashedPassword=.
  # `sudo cat /etc/shadow` will show all hashed user passwords.
  # More info:  https://search.nixos.org/options?channel=21.05&show=users.users.%3Cname%3E.passwordFile&query=users.users.%3Cname%3E.passwordFile
  
  users = {
    mutableUsers = false;
    defaultUserShell = pkgs.fish;
    users = {
      root = {
        # disable root login here, and also when installing nix by running nixos-install --no-root-passwd
        # https://discourse.nixos.org/t/how-to-disable-root-user-account-in-configuration-nix/13235/3
        hashedPassword = "!";  # disable root logins, nothing hashes to !
      };
      test = {
        isNormalUser = true;
        description = "Non-sudo account for testing new config options that could break login.  If need sudo for testing, add 'wheel' to extraGroups and rebuild.";
        initialPassword = "password";
        #passwordFile = "/persist/etc/users/test";
        extraGroups = [ "networkmanager" ];
        #openssh.authorizedKeys.keys = [ "${AUTHORIZED_SSH_KEY}" ];
      };
      lfron = {
        isNormalUser = true;
        description = "Logan Fron";
        passwordFile = "/persist/etc/users/lfron";  
        extraGroups = [ "wheel" "networkmanager" ];
        #openssh.authorizedKeys.keys = [ "${AUTHORIZED_SSH_KEY}" ];
      };
    };
  };

  environment.sessionVariables = rec {
    XDG_DATA_HOME ="\${HOME}/.local/share";
    XDG_CONFIG_HOME ="\${HOME}/.config";
    XDG_STATE_HOME ="\${HOME}/.local/state";
    XDG_CACHE_HOME ="\${HOME}/.cache";
    CARGO_HOME ="\${XDG_DATA_HOME}/cargo";
    GNUPGHOME ="\${XDG_DATA_HOME}/gnupg";
    GOPATH ="\${XDG_DATA_HOME}/go";
    LESSHISTFILE ="\${XDG_CACHE_HOME}/less/history";
    NUGET_PACKAGES ="\${XDG_CACHE_HOME}/NuGetPackages";
    PARALLEL_HOME ="\${XDG_CONFIG_HOME}/parallel";
    RUSTUP_HOME ="\${XDG_DATA_HOME}/rustup";
    WINEPREFIX ="\${XDG_DATA_HOME}/wine";
    _JAVA_OPTIONS =-Djava.util.prefs.userRoot="\${XDG_CONFIG_HOME}/java";
    GTK2_RC_FILES ="\${XDG_CONFIG_HOME}/gtk-2.0/gtkrc";
    MPLAYER_HOME = "\${$XDG_CONFIG_HOME}/mplayer";
    GRADLE_USER_HOME="\${XDG_DATA_HOME}/gradle";
  };

################################################################################
# Applications
################################################################################

  # List packages installed in system profile. To search, run:
  # $ nix search <packagename>
  environment.binsh = "${pkgs.dash}/bin/dash";
  environment.systemPackages = with pkgs; [
    
  # system core (useful for a minimal first install)
  nix-index 
  efibootmgr 
  parted gparted gptfdisk 
  pciutils uutils-coreutils wget  
  openssh ssh-copy-id ssh-import-id fail2ban sshguard
  git git-extras 
  zsh ffmpeg
  librewolf-wayland
  screen tmux
  vim wpgtk
  htop ncdu 
  sway alacritty
  dbus-sway-environment configure-gtk
  wayland glib
  capitaine-cursors swaylock-effects
  swayidle grim
  slurp wl-clipboard
  wofi mako
  mpv lutris
  xivlauncher python
  wine-staging winetricks
  protontricks waybar
  adapta-gtk-theme adapta-kde-theme
  ckb-next easyeffects
  openrgb yadm
  mpd mpd-mpris
  playerctl steam
  pywal bitwarden
  exa gamemode
  helvum irqbalance
  ncmpcpp noto-fonts
  noto-fonts-extra noto-fonts-emoji
  openvpn pavucontrol
  pcmanfm radeontop
  swappy zoxide
  fish dconf
  patchelf dash
  papirus-icon-theme libsForQt5.qt5ct
  killall polkit
  polkit_gnome discord
  libsForQt5.qtstyleplugin-kvantum xdg-user-dirs
  xdg-utils noto-fonts-cjk-sans
  noto-fonts-cjk-serif
  xsettingsd gnome.gnome-keyring
  steamPackages.steamcmd
  ];

################################################################################
# Program Config
################################################################################

  programs.fish = {
    enable = true;  
  };

  programs.steam = {
      enable = true;
      remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
      dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
  };

  hardware.ckb-next.enable = true;
  
  services.gnome.gnome-keyring.enable = true;
}