#!/bin/sh

echo insmod mt7902 zb driver
if [ -e /lib/modules/mediatek/zigbee/mtk_802154_spi.ko ]; then
	insmod "/lib/modules/$KERNEL_VERSION/mediatek/wifi/wlan_mt7902_sdio_reset.ko"
	retries=5
	while ! lsmod | grep -qe "^wlan_mt7902_sdio_reset" && ((retries > 0));
	do
		sleep 1
		((retries --))
	done
	# Check if mtk_802154_spi driver is loaded
	if lsmod | grep -qe "^mtk_802154_spi" ; then
		# mtk_802154_spi already loaded
		exit 0
	fi

	# Attempt to insert zigbee module
	if insmod /lib/modules/mediatek/zigbee/mtk_802154_spi.ko; then
		retries=5
		while ((retries > 0)); do
			if  lsmod | grep -qe "^mtk_802154_spi" ; then
				# mtk_802154_spi loaded successfully
				exit 0
			fi
			sleep 1
			((retries --))
		done
		echo "Failed to insmod mtk_802154_spi module"
		exit 1
	else
		echo "Failed to insmod mtk_802154_spi module"
		exit 1
	fi
fi

