#!/bin/sh
# insmod mt7663 driver before appmainprog starts
# echo insmod mt7663 driver
# if [ -e /lib/modules/mt7663/wlan_mt7663_sdio_prealloc.ko ];then
# 	insmod /lib/modules/mt7663/wlan_mt7663_sdio_prealloc.ko
# fi
# if [ -e /lib/modules/mt7663/wlan_mt7663_usb_prealloc.ko ];then
# 	insmod /lib/modules/mt7663/wlan_mt7663_usb_prealloc.ko
# fi
# if [ -e /lib/modules/mt7663/wlan_mt7663_sdio.ko ];then
# 	insmod /lib/modules/mt7663/wlan_mt7663_sdio.ko
# fi
# if [ -e /lib/modules/mt7663/wlan_mt7663_usb.ko ];then
# 	insmod /lib/modules/mt7663/wlan_mt7663_usb.ko
# fi

# if [ -e /lib/modules/mt7663/btmtksdio.ko ];then
# 	insmod /lib/modules/mt7663/btmtksdio.ko
# fi

echo insmod mt7902 bt driver
if [ -e /lib/modules/mediatek/bt/btmtk_sdio_79x2.ko ];then
	modprobe bluetooth
	retries=5
	# bluetooth module is loaded second
	while ! lsmod | grep -qe "^bluetooth" && ((retries > 0));
	do
		sleep 1
		((retries --))
	done

	insmod "/lib/modules/$KERNEL_VERSION/mediatek/wifi/wlan_mt7902_sdio_reset.ko"
	retries=5
	while ! lsmod | grep -qe "^wlan_mt7902_sdio_reset" && ((retries > 0));
	do
		sleep 1
		((retries --))
	done

	# Check if btmtk_sdio_79x2 driver is loaded
	if lsmod | grep -qe "^btmtk_sdio_79x2" ; then
		# btmtk_sdio_79x2 already loaded
		exit 0
	fi

	if insmod /lib/modules/mediatek/bt/btmtk_sdio_79x2.ko; then
		retries=5
		while ((retries > 0)); do
			if  lsmod | grep -qe "^btmtk_sdio_79x2" ; then
				# btmtk_sdio_79x2 loaded successfully
				exit 0
			fi
			sleep 1
			((retries --))
		done
		echo "Failed to insmod btmtk_sdio_79x2 module"
		exit 1
	else
		echo "Failed to insmod btmtk_sdio_79x2 module"
		exit 1
	fi
fi

# if [ -e /lib/modules/mt7663/btmtk_usb.ko ];then
# 	insmod /lib/modules/mt7663/btmtk_usb.ko
# fi
