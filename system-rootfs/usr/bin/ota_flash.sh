#!/bin/sh

get_mmc_dev() {
# $1 is partition name
# $2 mmc blk partition count
	c=1
	while [ "$c" -le "$2" ]
	do
		dev_name="/dev/mmcblk0p$c"
		part_name=$(udevadm info --query property -n $dev_name | grep PARTNAME | cut -d "=" -f2)
		if [ $part_name == "$1" ]; then
			echo "$dev_name"
			break;
		fi
		c=$(( c + 1 ))
	done
}

#kernel command line contains bootargs
CMDLINE=$(cat /proc/cmdline)
for x in $CMDLINE; do
    [[ $x = activepart=* ]] || continue
   active_part=${x#activepart=}
	if [ $active_part -eq 0 ]; then
		access_part=1
	elif [ $active_part -eq 1 ]; then
		access_part=0
	else
		echo "invalid active part $active_part"
		exit 1
	fi
done
#Max available mmc partitions
mmc_blk_cnt=$(ls /dev/mmcblk0p* | wc -l)
echo "mmc blk partition count $mmc_blk_cnt"
if [ -d "$1" ]; then
   for file in "$1/"*; do
		if [ -f $file ]; then
			image="$(basename $file)"
			case "$image" in
				"fip_bl2.bin")
				echo "$image write to /dev/mmcblk0boot$access_part"
				echo 0 > /sys/block/mmcblk0boot$access_part/force_ro
				dd if=$file of=/dev/mmcblk0boot$access_part bs=512
				;;
				"fip.bin")
				if [ $access_part -eq 0 ]; then
					image_part="bootloader_a"
				else
					image_part="bootloader_b"
				fi
				dev_name=$(get_mmc_dev $image_part $mmc_blk_cnt)
				echo "$image file will write to $dev_name"
				dd if=$file of=$dev_name bs=512
				;;
				"fitImage")
				if [ $access_part -eq 0 ]; then
					image_part="boot_a"
				else
					image_part="boot_b"
				fi
				dev_name=$(get_mmc_dev $image_part $mmc_blk_cnt)
				echo "$image file will write to $dev_name"
				dd if=$file of=$dev_name bs=512
				;;
				"azma-image-azma15-gf.ext4")
				if [ $access_part -eq 0 ]; then
					image_part="system_a"
				else
					image_part="system_b"
				fi
				dev_name=$(get_mmc_dev $image_part $mmc_blk_cnt)
				echo "$image file will write to $dev_name"
				dd if=$file of=$dev_name bs=512
				;;
			esac
		fi
   done
else
    echo "$1 no directory exists"
fi
if [ $2 -eq 1 ]; then
	echo "update ota boot and reboot"
	echo 1 > /sys/kernel/ota_boot
	reboot -f
fi
