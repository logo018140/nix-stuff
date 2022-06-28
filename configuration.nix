# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{ config
, pkgs
, lib
, ...
}:
let
  #Sway GTK stuff
  # bash script to let dbus know about important env variables and
  # propogate them to relevent services run at the end of sway config
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
    text =
      let
        schema = pkgs.gsettings-desktop-schemas;
        datadir = "${schema}/share/gsettings-schemas/${schema.name}";
      in
      ''
        export XDG_DATA_DIRS=${datadir}:$XDG_DATA_DIRS
        gnome_schema=org.gnome.desktop.interface
        gsettings set $gnome_schema gtk-theme 'Dracula'
        gsettings set $gnome_schema icon-theme 'Papirus-Dark'
        gsettings set $gnome_schema cursor-theme 'capitaine-cursors'
        gsettings set $gnome_schema cursor-size 24
        gsettings set $gnome_schema font-name 'Noto Sans'
      '';
  };
in
{
  ################################################################################
  # System
  ################################################################################

  imports = [
    ./hardware-configuration.nix
    ./users.nix
  ];

  nixpkgs.config = {
    allowUnfree = true;
  };

  nix = {
    autoOptimiseStore = true;
    extraOptions = ''
      experimental-features = nix-command
   '';
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.05"; # Did you read the comment?
  system.autoUpgrade.enable = true;

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

  services.fstrim.enable = true;

  # Use EFI boot loader with Grub.
  # https://nixos.org/manual/nixos/stable/index.html#sec-installation-partitioning-UEFI
  boot = {
    kernelPackages = pkgs.linuxPackages_zen;
    supportedFilesystems = [ "vfat" "zfs" "btrfs" ];
    initrd.kernelModules = [ "amdgpu" ];
    loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true; # grub will use efibootmgr
      zfsSupport = true;
      copyKernels = true; # https://nixos.wiki/wiki/NixOS_on_ZFS
      device = "nodev"; # "/dev/sdx", or "nodev" for efi only
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
    hostName = "nixPC"; # Any arbitrary hostname.

    useDHCP = false;
    interfaces = {
      enp35s0.useDHCP = true;
    };
  };

  services.openvpn.servers = {
    piaAtlanta = { config = '' config /persist/openvpn/us_atlanta.conf ''; };
    piaAtlanta.autoStart = false;
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

  #3. Bluetooth: requires /persist/var/lib/bluetooth
  #4. ACME certificates: requires /persist/var/lib/acme
  #5. Waydroid: requires /persist/var/lib/waydroid
  #6. Libvirt: keep persistent
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
    passwordAuthentication = false;
    hostKeys = [
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
  # Display Drivers
  ################################################################################

  hardware.opengl = {
    driSupport = true; # install and enable Vulkan: https://nixos.org/manual/nixos/unstable/index.html#sec-gpu-accel
    driSupport32Bit = true;
    extraPackages = with pkgs; [ rocm-opencl-icd ];
  };

  ################################################################################
  # Window Managers & Desktop Environment
  ################################################################################

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
    jack.enable = true;
  };

  ################################################################################
  # Applications
  ################################################################################

  # List packages installed in system profile. To search, run:
  # $ nix search <packagename>
  environment.binsh = "${pkgs.dash}/bin/dash";
  environment.systemPackages = with pkgs; [
    nix-index
    efibootmgr
    parted
    gparted
    gptfdisk
    pciutils
    uutils-coreutils
    wget
    openssh
    ssh-copy-id
    ssh-import-id
    git
    git-extras
    zsh
    ffmpeg
    firefox-wayland
    screen
    tmux
    vim
    htop
    ncdu
    sway
    alacritty
    dbus-sway-environment
    configure-gtk
    wayland
    glib
    capitaine-cursors
    swaylock-effects
    swayidle
    grim
    slurp
    wl-clipboard
    wofi
    mako
    mpv
    lutris
    xivlauncher
    python39Full
    wineWowPackages.staging
    winetricks
    protontricks
    waybar
    dracula-theme
    adapta-kde-theme
    openrgb
    yadm
    mpd
    mpdris2
    playerctl
    bitwarden
    exa
    gamemode
    helvum
    irqbalance
    ncmpcpp
    gnome.file-roller
    pcmanfm
    radeontop
    swappy
    zoxide
    zsh
    dconf
    patchelf
    dash
    papirus-icon-theme
    killall
    polkit
    discord
    libsForQt5.qtstyleplugin-kvantum
    xdg-user-dirs
    xdg-utils
    xsettingsd
    steamPackages.steamcmd
    pavucontrol
    gnome.zenity
    openssl
    protonup
    python39Packages.pyotp
    betterdiscordctl
    p7zip
    unzip
    file
    perl
    nixpkgs-fmt
    bottles
    gamemode
    polymc
    sway-contrib.grimshot
    yt-dlp
    qbittorrent
    desktop-file-utils
    gnome.seahorse
    swappy
    jdk
    clinfo
    vscode
    unrar
    ps_mem
  ];

  fonts.fonts = with pkgs; [
    noto-fonts
    noto-fonts-emoji
    noto-fonts-extra
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    fira-code
    fira-code-symbols
    mplus-outline-fonts.githubRelease
    (nerdfonts.override { fonts = [ "Noto" ]; })
  ];

  ################################################################################
  # Program Config
  ################################################################################

  programs = {
    gamemode = {
      enable = true;
      enableRenice = true;
    };
    steam = {
      enable = true;
      remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    };
    zsh = {
      enable = true;
      ohMyZsh = {
        enable = true;
        plugins = [ "git" ];
        theme = "avit";
      };
    };
    noisetorch.enable = true;
    adb.enable = true;
  };

  hardware = {
    ckb-next.enable = true;
  };

  services = {
    gvfs = {
      enable = true;
      package = lib.mkForce pkgs.gnome3.gvfs;
    };
    mpd = {
      enable = true;
      user = "lfron";
      musicDirectory = "/home/lfron/Music";
      playlistDirectory = "/home/lfron/.config/mpd/playlists";
      dbFile = "/home/lfron/.config/mpd/database";
      dataDir = "/home/lfron/.config/mpd";
      extraConfig = ''
        audio_output {
          type "pipewire"
          name "Pipewire"
        }
      '';
      startWhenNeeded = true; # systemd feature: only start MPD service upon connection to its socket
    };
    gnome.gnome-keyring.enable = true;
  };

  systemd.services.mpd.environment = {
    # https://gitlab.freedesktop.org/pipewire/pipewire/-/issues/609
    XDG_RUNTIME_DIR = "/run/user/1000"; # User-id 1000 must match above user. MPD will look inside this directory for the PipeWire socket.
  };
}
