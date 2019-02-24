# alarm-helios4-image-builder

This Bash script creates an [ArchLinux ARM](https://archlinuxarm.org/) image for the **Helios4 NAS** ready to be written on microSD card.

[Helios4](https://kobol.io/helios4/) is an powerful Open Source and Open Hardware Network Attached Storage (NAS) made by Kobol Innovations Pte. Ltd. It harnesses its processing capabilities from the ARMADA 38x-MicroSoM from SolidRun.

The resulting image file contains:
* a Linux kernel [configured and patched](https://github.com/gbcreation/linux-helios4) for Helios4. Especially to make the second fan detected.
* the udev rules for hardware monitoring.
* the configuration file and patch for fancontrol originally provided by the Kobol Team for Armbian.
* the mdadm bash script originally provided by the Kobol Team for Armbian, to report mdadm error events using the Red Faut LED (LED2).

## Requirements

This script expects to be used on a x86 system running ArchLinux. It needs `qemu-arm-static` to work. You can install it using the **[qemu-user-static](https://aur.archlinux.org/packages/qemu-user-static/)** or **[qemu-user-static-bin](https://aur.archlinux.org/packages/qemu-user-static-bin/)** packages from the AUR.

## Usage

> **Note:** this script needs to execute commands as the superuser. If not run as root, it will re-run itself using sudo. **It is highly recommanded to review this script and understand what it does before running it on your system.**

```
$ git clone https://github.com/gbcreation/alarm-helios4-image-builder.git
$ cd alarm-helios4-image-builder
$ sh ./build-archlinux-img-for-helios4.sh
```

Once the image file is created, write it to a microSD card using [Etcher](http://etcher.io) or the `dd` command:

```
$ dd bs=4M if=ArchLinuxARM-helios4-2019-02-24.img of=/dev/sdX conv=fsync
```

Insert the microSD card to the Helios4 and enjoy Arch Linux ARM on you NAS.

## Known bugs

* LEDs do not light up on disk access.

## What does this script do?

Here are all the steps performed by the script:

* Check if the `qemu-arm-static` executable is installed (see Requirements above).
* Check if script is run as root. Re-run itself using `sudo` if not.
* Check if the following packages are installed (automatically install them if not):
    * [arch-install-scripts](https://www.archlinux.org/packages/extra/any/arch-install-scripts/): use `arch-chroot` to enter to the created chroot
    * [arm-none-eabi-gcc](https://www.archlinux.org/packages/community/x86_64/arm-none-eabi-gcc/): ARM cross compiler used to compile the u-boot bootloader
    * [uboot-tools](https://www.archlinux.org/packages/community/x86_64/uboot-tools/): use `mkimage` to compile the u-boot script
* Download the root ArchLinux ARM filesystem / patches / Linux packages for Helios4 :
    * [ArchLinuxARM-armv7-latest.tar.gz](http://os.archlinuxarm.org/os/ArchLinuxARM-armv7-latest.tar.gz): the generic ArchLinux ARMv7 root filesystem
    * [90-helios4-hwmon.rules](https://raw.githubusercontent.com/armbian/build/master/packages/bsp/helios4/90-helios4-hwmon.rules): udev rules for hardware monitoring
    * [fancontrol_pwm-fan-mvebu-next.conf](https://raw.githubusercontent.com/armbian/build/master/packages/bsp/helios4/fancontrol_pwm-fan-mvebu-next.conf): fancontrol configuration file
    * [mdadm-fault-led.sh](https://raw.githubusercontent.com/armbian/build/master/packages/bsp/helios4/mdadm-fault-led.sh): Bash script used by mdadm to report error events using the Red Faut LED (LED2)
    * [fancontrol.patch](https://raw.githubusercontent.com/helios-4/build/helios4/packages/bsp/helios4/fancontrol.patch): patch for the fancontrol script fixing 'too many arguments' error message and setting pwm to minimum speed when fancontrol exits (see [this comment](https://forum.armbian.com/topic/6033-helios4-support/?page=2&tab=comments#comment-49490) on the Armbian forum from gprovost).
    * [linux-helios4-4.20.11-1-armv7h.pkg.tar.xz](https://github.com/gbcreation/linux-helios4/releases/download/4.20.11-1/linux-helios4-4.20.11-1-armv7h.pkg.tar.xz) and [linux-helios4-headers-4.20.11-1-armv7h.pkg.tar.xz](https://github.com/gbcreation/linux-helios4/releases/download/4.20.11-1/linux-helios4-headers-4.20.11-1-armv7h.pkg.tar.xz): Linux kernel patched for Helios4 (see https://github.com/gbcreation/linux-helios4)
* Create a new image file on disk. Change the `ÌMG_FILE` variable in script to set the image filename.
* Create a new partition in the image file using `fdisk`.
* Mount the image file as a loop device using `losetup`, forcing the kernel to scan the partition table to detect the partition inside.
* Format the partition as ext4.
* Mount the formatted partition to the `./img/` sub-directory. Change the `MOUNT_DIR` variable in script to set the target directory.
* Extract ArchLinuxARM-armv7-latest.tar.gz to `./img/`.
* Copy `90-helios4-hwmon.rules` to `./img/etc/udev/rules.d`. Patch it to replace the `armada_thermal` device name by `f10e4078.thermal`.
* Copy Helios4 Linux packages to `./img/root`.
* Copy `qemu-arm-static` to `./img/usr/bin`.
* Register qemu-arm-static as ARM interpreter in the host kernel
* Use `arch-chroot` to enter to the `./img/` chroot and then:
    * initialize the Pacman keyring
    * populate the Arch Linux ARM package signing keys
    * upgrade the Arch Linux ARM system
    * install the Helios4 Linux kernel
    * install lm_sensors
    * enable the fancontrol service to start on boot
* Remove Helios4 Linux packages from `./img/root`.
* Remove `qemu-arm-static` from `./img/usr/bin`.
* Apply `fancontrol.patch` to `./img/usr/sbin/fancontrol`.
* Copy the fancontrol configuration file `fancontrol_pwm-fan-mvebu-next.conf` to `./img/etc/fancontrol`.
* Make the `lm75` kernel module loaded on boot by creating `./img/etc/modules-load.d/lm75.conf`.
* Copy `mdadm-fault-led.sh` to `./img/usr/bin` and set the `PROGRAM` directive to `/usr/sbin/mdadm-fault-led.sh` in `./img/etc/mdadm.conf`.
* Create the u-boot script `./img/boot/boot.cmd`.
* Use `mkimage` to compile `./img/boot/boot.cmd` to `./img/boot/boot.scr`.
* Unmount the image file partition.
* Clone the `helios-4/u-boot` Git repository and compile the u-boot bootloader.
* Copy the compiled u-boot bootloader to the loop device.
* Unmount the loop device

## About loop devices and mounted partitions

If the script stops due to errors, the image file can still be mounted as a loop device, and its partition mounted to the `./img/` sub-directory. Before running the script again, ensure that the `./img` is unmounted:

```
$ sudo umount ./img
```

Check also if the image file is still mounted as a loop device:

```
$ sudo losetup -a
```

If so, umount it:

```
$ sudo losetup -d /dev/loopX
```

## Thanks

Thanks to:

* the **Kobol Team** for this great piece of Open Hardware that is Helios4 NAS
* **Aditya** from the Kobol Team for his valuable help on explaining various patches and configuration files
* **Summers** from the Arch Linux ARM forum for his precious advices and encouraging responses

## License

MIT. Copyright (c) Gontran Baerts
