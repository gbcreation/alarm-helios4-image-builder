#!/bin/bash
#
# Bash script creating an Arch Linux ARM image for the Helios4 NAS.
#
# Author: Gontran Baerts
# Repository: https://github.com/gbcreation/linux-helios4
# License: MIT
#

set -e

# Configuration
DOWNLOADER="aria2c --continue=true -x 4"
IMG_DIR="./"
IMG_DIR=`readlink -f "${IMG_DIR}"`
IMG_FILE="ArchLinuxARM-helios4-$(date +%Y-%m-%d).img"
IMG_SIZE="2G"
MOUNT_DIR="./img"
ALARM_ROOTFS="http://os.archlinuxarm.org/os/ArchLinuxARM-armv7-latest.tar.gz"
LINUX_HELIOS4_VERSION=`wget -q -O - https://api.github.com/repos/gbcreation/linux-helios4/releases/latest | sed -En '/tag_name/{s/.*"([^"]+)".*/\1/;p}'`

sources=("${ALARM_ROOTFS}"
        'https://raw.githubusercontent.com/armbian/build/master/packages/bsp/helios4/90-helios4-hwmon.rules'
        'https://raw.githubusercontent.com/armbian/build/master/packages/bsp/helios4/fancontrol_pwm-fan-mvebu-next.conf'
        'https://raw.githubusercontent.com/armbian/build/master/packages/bsp/helios4/mdadm-fault-led.sh'
        "https://github.com/gbcreation/linux-helios4/releases/download/${LINUX_HELIOS4_VERSION}/linux-helios4-${LINUX_HELIOS4_VERSION}-armv7h.pkg.tar.xz")
md5sums=('63bd1c55905af69f75cf4c046a89280a'
         'f0162acfa70e2d981c11ec4b0242d5bd'
         '7e1423c3e3b8c3c8df599a54881b5036'
         '0a5bfbea2f1d65b936da6df4085ee5f2'
         `wget -q -O - https://github.com/gbcreation/linux-helios4/releases/download/${LINUX_HELIOS4_VERSION}/md5sums.txt | sed -En "/linux-helios4-${LINUX_HELIOS4_VERSION}/{s/^([0-9a-f]{32}).*$/\1/;p}"`)

echo_step () {
    echo -e "\e[1;32m ${@} \e[0m\n"
}


echo_step "\nArchLinux ARM image builder for Helios4 NAS"

which qemu-arm-static >/dev/null 2>&1 || {
    echo 'This script needs qemu-arm-static to work. Install qemu-user-static or qemu-user-static-bin from the AUR.'
    exit 1
}

if [[ $EUID != 0 ]]; then
    echo This script requires root privileges, trying to use sudo
    sudo "$0"
    exit $?
fi

echo_step Install script dependencies...
pacman -Sy --needed --noconfirm arch-install-scripts arm-none-eabi-gcc uboot-tools

for i in ${!sources[*]}; do
    echo_step Download ${sources[i]}...
    ${DOWNLOADER} "${sources[i]}"
    if [ "`md5sum ${sources[i]##*/} | cut -d ' ' -f1`" != "${md5sums[i]}" ]; then
        echo Wrong MD5 sum for ${sources[i]}.
        exit 1
    fi
done

echo_step Create ${IMG_DIR}/${IMG_FILE} image file...
dd if=/dev/zero of="${IMG_DIR}/${IMG_FILE}" bs=1 count=0 seek=${IMG_SIZE}

echo_step Create partition...
fdisk "${IMG_DIR}/${IMG_FILE}" <<EOF
o
n
p
1


w
EOF

echo_step Mount loop image...
LOOP_MOUNT=`losetup --partscan --show --find "${IMG_DIR}/${IMG_FILE}"`

echo_step Format partition ${LOOP_MOUNT}p1...
# mkfs.ext4 -F -L alarm-helios4 "${LOOP_MOUNT}p1"
mkfs.ext4 -qF -L alarm-helios4 "${LOOP_MOUNT}p1"

echo_step Mount image partition ${LOOP_MOUNT}p1 to ${MOUNT_DIR}...
mkdir -p "${MOUNT_DIR}"
mount "${LOOP_MOUNT}p1" "${MOUNT_DIR}"

echo_step Extract ${ALARM_ROOTFS##*/} to ${MOUNT_DIR}...
bsdtar -xpf "${ALARM_ROOTFS##*/}" -C "${MOUNT_DIR}"

echo_step Copy hwmon to fix device mapping...
sed -e 's/armada_thermal/f10e4078.thermal/' 90-helios4-hwmon.rules > ${MOUNT_DIR}/etc/udev/rules.d/90-helios4-hwmon.rules

echo_step Copy linux-helios4 packages to ${MOUNT_DIR}/root...
cp linux-helios4-*-armv7h.pkg.tar.xz ${MOUNT_DIR}/root

echo_step Copy `which qemu-arm-static` to ${MOUNT_DIR}/usr/bin...
cp `which qemu-arm-static` ${MOUNT_DIR}/usr/bin

echo_step Register qemu-arm-static as ARM interpreter in the kernel...
[ ! -f /proc/sys/fs/binfmt_misc/register ] && echo ':arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-arm-static:CF' > /proc/sys/fs/binfmt_misc/register

echo_step Initialize pacman-key, update ARM system and install lm_sensors...
arch-chroot ${MOUNT_DIR} bash -c "
    pacman-key --init &&
    pacman-key --populate archlinuxarm &&
    pacman -Syu --noconfirm --ignore linux-armv7 &&
    (yes | pacman -U /root/linux-helios4-${LINUX_HELIOS4_VERSION}-armv7h.pkg.tar.xz) &&
    pacman -S --noconfirm lm_sensors &&
    systemctl enable fancontrol.service
"

echo_step Remove linux-helios4 packages to ${MOUNT_DIR}/root...
rm -f ${MOUNT_DIR}/root/linux-helios4-*-armv7h.pkg.tar.xz

echo_step Remove qemu-arm-static from ${MOUNT_DIR}/usr/bin...
rm -f ${MOUNT_DIR}/usr/bin/qemu-arm-static

echo_step Copy fancontrol config...
cp fancontrol_pwm-fan-mvebu-next.conf ${MOUNT_DIR}/etc/fancontrol

echo_step Configure loading of lm75 kernel module on boot...
echo "lm75" > ${MOUNT_DIR}/etc/modules-load.d/lm75.conf

echo_step Copy mdadm-fault-led script and modify mdadm configuration...
cp mdadm-fault-led.sh ${MOUNT_DIR}/usr/sbin
echo "PROGRAM /usr/sbin/mdadm-fault-led.sh" >> ${MOUNT_DIR}/etc/mdadm.conf

echo_step Copy u-boot boot.cmd to ${MOUNT_DIR}/boot...
cat << 'EOF' > "${MOUNT_DIR}/boot/boot.cmd"
setenv eth1addr "00:50:43:25:fb:84"
part uuid ${devtype} ${devnum}:${bootpart} uuid
setenv bootargs console=${console} root=PARTUUID=${uuid} rw rootwait loglevel=1
load ${devtype} ${devnum}:${bootpart} ${kernel_addr_r} /boot/zImage
load ${devtype} ${devnum}:${bootpart} ${fdt_addr_r} /boot/dtbs/${fdtfile}
load ${devtype} ${devnum}:${bootpart} ${ramdisk_addr_r} /boot/initramfs-linux.img
bootz ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}
EOF

echo_step Compile boot.cmd...
mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Helios4 boot script" -d "${MOUNT_DIR}/boot/boot.cmd" "${MOUNT_DIR}/boot/boot.scr"

echo_step Unmount image partition...
umount "${MOUNT_DIR}"

echo_step Build U-Boot...
[ ! -d "u-boot" ] && git clone https://github.com/helios-4/u-boot.git -b helios4
cd u-boot
[ ! -f u-boot-spl.kwb ] && {
    export ARCH=arm
    export CROSS_COMPILE=arm-none-eabi-
    make mrproper
    make helios4_defconfig
    make -j${nproc}
}

echo_step Copy u-boot to ${LOOP_MOUNT}...
dd if=u-boot-spl.kwb of="${LOOP_MOUNT}" bs=512 seek=1
cd -

echo_step Unmount loop partition...
losetup -d "${LOOP_MOUNT}"

echo_step done
