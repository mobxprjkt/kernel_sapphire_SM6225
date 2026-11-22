#!/usr/bin/env sh
# AnyKernel3 installer — Redmi Note 13 4G / NFC (sapphire / sapphiren)

properties() { 
  kernel.string="Sapphiren SukiSU-Nova Kernel"
  do.devicecheck=1
  do.modules=0
  do.cleanup=1
  do.cleanuponabort=0
  device.name1=sapphire
  device.name2=sapphiren
  device.name3=Redmi Note 13 4G
  device.name4=Redmi Note 13 4G NFC
  supported.versions="13-17"
  supported.patchlevels=""
}

# A/B device: flash only the currently active boot slot.
block=boot
is_slot_device=1
slot_select=active

. tools/ak3-core.sh
