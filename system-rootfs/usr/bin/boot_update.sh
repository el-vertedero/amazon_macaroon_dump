#!/bin/sh

# Read current booted partition information from eMMC PARTITION_CONFIG register
mmc_part=$(mmc extcsd read /dev/mmcblk0 | grep PARTITION_CONFIG | cut -d "[" -f2 | cut -d "]" -f1 | cut -d " " -f2)
part_val=$(( ($mmc_part >> 3) & (0x7) ))
echo "Current eMMC boot partition is $part_val"

#kernel command line contains bootargs
CMDLINE=$(cat /proc/cmdline)
for x in $CMDLINE; do
    [[ $x = activepart=* ]] || continue
   active_part=${x#activepart=}
	if [ $active_part -eq 0 ]; then
		access_part=1
	elif [ $active_part -eq 1 ]; then
		access_part=2
	else
		echo "invalid active part $active_part bootargment"
		exit 1
	fi
done

if [ $access_part != $part_val ]; then
	mmc bootpart enable $access_part 0 /dev/mmcblk0

	# Read back programmed partition information from eMMC PARTITION_CONFIG register
	mmc_part=$(mmc extcsd read /dev/mmcblk0 | grep PARTITION_CONFIG | cut -d "[" -f2 | cut -d "]" -f1 | cut -d " " -f2)
	part_val=$(( ($mmc_part >> 3) & (0x7) ))

	# Check read back partition information as expected
	if [ $access_part != $part_val ]; then
		echo "mmc partition update to $access_part failed"
	else
		echo "mmc partition update to $access_part success"
	fi
fi

# Request to update ARBC counter
echo 1 > /sys/kernel/arbc_prog
