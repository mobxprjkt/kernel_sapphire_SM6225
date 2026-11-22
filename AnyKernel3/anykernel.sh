
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
properties() { '
kernel.string=SukiSU Nova Kernel
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=sapphire
device.name2=sapphiren
supported.versions=13-17
supported.patchlevels=
supported.vendorpatchlevels=
'; }

### AnyKernel install

boot_attributes() {
  set_perm_recursive 0 0 755 644 $RAMDISK/*
  set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin
}

BLOCK=boot
IS_SLOT_DEVICE=auto
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=auto

# Import AnyKernel3 core
. tools/ak3-core.sh

## Install kernel Image

# Verify Image
if [ ! -f "$AKHOME/Image" ]; then
  ui_print " "
  ui_print "ERROR: Kernel Image not found!"
  ui_print "Expected: AnyKernel3/Image"
  ui_print " "
  exit 1
fi

# Detect target partition
if [ -L "/dev/block/bootdevice/by-name/init_boot_a" ] || \
   [ -L "/dev/block/by-name/init_boot_a" ]; then

  ui_print "  Detected init_boot partition"
  split_boot
  flash_boot

else

  ui_print "  Using boot partition"
  dump_boot
  write_boot

fi

ui_print " "
ui_print "  Kernel Image installation completed!"
ui_print " "
## end boot install
