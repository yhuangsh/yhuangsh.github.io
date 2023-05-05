---
layout: post
title:  "iPad to Raspberry Pi, The NixOS Way"
date:   2023-05-04 17:45:01 +0800
categories: nixos raspberry-pi
---

## Recap of What's Already Known

It's not new that one can connect an iPad and a Raspberry Pi via a USB-C data cable to make a wonderful mobile working station. The USB-C cable provides power from iPad to Pi which runs in a so-called "USB Gadget" mode where the Pi provides a ethernet interface over the USB connection so that both can communicate directly without resorting to any external WiFi. This way one can enjoy working off the grid, for example, on a airplane, or when remote connectivity is expected to be unstable. 

This particular setup has been covered in details by many great minds on the Internet. Here are a few sources I used:

- [Ben Hardill' Pi4 USB-C Gadget](https://www.hardill.me.uk/wordpress/2019/11/02/pi4-usb-c-gadget/)
- [Andrzej Pietraiewicz' Modern USB gadget on Linux & how to integrate it with systemd](https://www.collabora.com/news-and-blog/blog/2019/02/18/modern-usb-gadget-on-linux-and-how-to-integrate-it-with-systemd-part-1/)
- [Tech Craft's My Favourite iPad Pro Accessory: The Raspberry Pi 4](https://youtu.be/IR6sDcKo3V8)

So I won't repeat them, but just give a short recap on the basic idea as follows:

- Enable a series of kernnel and after-boot device tweaks so that once the cable is connected, iPad would recognize the Pi box a Ethernet over USB device.
- As such, iPad would get an extra Ethernet interface and start to request an IP address.
- The Pi runs a small DHCP server to hand out the IP address to iPad, thus connecting the two. 

The aobve sources all used Raspbian or "regular" Linux distros on the Pi and made the tweaks using the "regular" method, i.e.: boot parameters, rc scripts, etc. All fine and working well. 

What I didn't was taking the very same approach and apply them on a standard NixOS way. This means two things: (1) my Raspberry runs NixOS; (2) my setup is declarative using mainly `/etc/nixos/configuration.nix`, the standard NixOS way. 

## The configuration.nix 

Here's the snippets of my configuration that are relevant, with comments

Each of the following code blocks should be part of the main `configuration.nix` body. Ordering is not important except for the imports. They can also mix and merge with other configuration attributes. If you are familiar with nix, this should be rather obvious. 

```
{ config, pkgs, lib, ...}:
{
    # code blocks go here, order not important
}
```

Import Raspberry Pi hardware configuration, and enable `dwc2` driver. 

```nix
imports = [
  <nixos-hardware/raspberry-pi/4>
];

hardware.raspberry-pi."4" = {
  dwc2.enable = true;
  dwc2.dr_mode = "peripheral";  # kernal supports host, otg, peripheral modes. 
                                # peripheral is for our use case
};
```

Load `libcomposite` kernel module

```nix
boot.kernelModules = [
  "libcomposite"
];
```

Now create a one-short systemd service that runs on every boot. the script creates the usb0 interface. Once activated, a "Ethernet" item will appear in the iPad settings list right below Network.

```nix
systemd.services.ipadlink = {
  description = "Set up configfs to expose Ethernet to iPad";

  wantedBy = [ "multi-user.target" ];
  after = [ "usb-gadget.target" ];                

  serviceConfig = {
    Type = "oneshot";
  };

  environment = {
    id_vendor = "0x1d6b";                        # Linux Foundation
    id_product = "0x104";                        # Multifunction Composite Gadget     
    manufacturer = "David Huang";                # Tailor to your taste
    product = "David's Raspberry Pi 4 Ethernet"; # This is what's shown on iPad, 
                                                 # tailor to your taste
  };
  script = ''
    cd /sys/kernel/config/usb_gadget
    mkdir -p pi4/strings/0x409

    cd pi4
    echo $id_vendor > idVendor
    echo $id_product > idProduct

    echo $manufacturer > strings/0x409/manufacturer
    echo $product > strings/0x409/product
    
    mkdir configs/c.1
    mkdir functions/ecm.usb0
    ln -s functions/ecm.usb0/ configs/c.1

    udevadm settle -t 2 || :
    ls /sys/class/udc > UDC
  '';
};
```

Assign a static address to usb0 on the Pi side and enable DHCP server to hand out IP address to iPad

```nix
networking = {
  firewall = {
    allowedUDPPorts = [ 67 ];  # Enabling dnsmasq does NOT automatically 
                               # enable DHCP server port 67.
                               # You have to open the port manually. 
  };
  interfaces.usb0.ipv4.addresses = [
    {
      address = "10.55.0.1";
      prefixLength = 29;
    }
  ];

  dhcpcd.denyInterfaces = [ "usb0" ]; # Disable dhcpcd (the dhcp client 
                                      # daemon on Pi side) for usb0.
};

services = {                      
  dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {               # This "settings" syntax is new in the 
                               # nixos-unstable channel.
                               # If it doesn't work for your NixOS version, 
                               # put everything in the original dnsmasq.conf 
                               # format under extraConfig
      interface = "usb0";          
      dhcp-range = [ "10.55.0.2,10.55.0.6" ];
      dhcp-option = 3;
    };
                       # Ironically, "settings" cannot cover all options. 
                       # I still need extraConfig to include this 
                       # "leasefire-ro" option that does not conform to 
                       # "key=value" format. I tried to set it to null, 
                       # "" (empty string), to no avail. If you know how to 
                       # express it in "settings", please drop me a line.
    extraConfig = ''   
      leasefile-ro
    '';
  };
};
```  

And that's it. Time for `sudo nixos-rebuild switch`. Once the Pi boots, you should see an Ethernet interface popping up on iPad with a green dot indicating it has got an IP address. 

Enjoy sshing and hacking in the Pi!
