#!/bin/sh

mkdir -p /dev/pts
if mount -t devpts none /dev/pts &> /dev/null ; then
  echo "devpts mounted"
else
  echo "devpts mount failed"
  exit 1
fi
sleep 0.01

MODULE="libcomposite"
if modprobe "$MODULE" &> /dev/null ; then
  echo "module $MODULE is inserted"
else
  echo "module $MODULE insertion failed"
  exit 1
fi

if [ -L "/sys/class/udc/$1" ]; then
	echo "UDC device is $1"
else
	echo "Please input valild UDC device file"
	echo "For valild UDC device file.. check inside /sys/class/udc/"
	echo "Usage.."
	echo " adb_setup.sh <b0200000.usb>"
	exit 1
fi

CONFIG_FS="configfs"
CONFIG_FS_DIR="/sys/kernel/config"
if grep -F " $CONFIG_FS " /proc/mounts > /dev/null; then
	echo "$CONFIG_FS is already mounted"
else
	echo "Trying to mount configfs"
	if mount -t $CONFIG_FS none $CONFIG_FS_DIR &> /dev/null ; then
		echo "$CONFIG_FS is mounted on $CONFIG_FS_DIR"
	else
		echo "$CONFIG_FS mount failed"
		exit 1
	fi
fi

sleep 0.01
mkdir -p /sys/kernel/config/usb_gadget/gadb
sleep 0.01
echo 0x0200 > /sys/kernel/config/usb_gadget/gadb/bcdUSB
mkdir -p /sys/kernel/config/usb_gadget/gadb/strings/0x409
echo 1 > /sys/kernel/config/usb_gadget/gadb/os_desc/use 1
sleep 0.01

# Use serial number from IDME
IDME_SERIAL_PATH=/sys/firmware/devicetree/base/idme/serial/value
# fallback if idme does not have serial number
DSN="Amazon Azma15"
if [ -e ${IDME_SERIAL_PATH} ]; then
	SERIAL_VAL=$(cat ${IDME_SERIAL_PATH})
	if [ "0" != "${SERIAL_VAL}" ]; then
		DSN=${SERIAL_VAL}
	fi
fi

echo "0x1949" > /sys/kernel/config/usb_gadget/gadb/idVendor
echo "0x1949" > /sys/kernel/config/usb_gadget/gadb/idProduct
echo "${DSN}" > /sys/kernel/config/usb_gadget/gadb/strings/0x409/serialnumber
echo "Amazon Inc" > /sys/kernel/config/usb_gadget/gadb/strings/0x409/manufacturer
echo "Azma15 BSP" >  /sys/kernel/config/usb_gadget/gadb/strings/0x409/product

mkdir -p /sys/kernel/config/usb_gadget/gadb/functions/ffs.adb
sleep 0.01
mkdir -p /sys/kernel/config/usb_gadget/gadb/configs/b.1
sleep 0.01
mkdir -p /sys/kernel/config/usb_gadget/gadb/configs/b.1/strings/0x409
sleep 0.01
echo "ffs.adb" > /sys/kernel/config/usb_gadget/gadb/configs/b.1/strings/0x409/configuration
ln -s /sys/kernel/config/usb_gadget/gadb/functions/ffs.adb /sys/kernel/config/usb_gadget/gadb/configs/b.1

mkdir -p /dev/usb-ffs
sleep 0.01
mkdir -p /dev/usb-ffs/adb
sleep 0.01
mount -t functionfs adb /dev/usb-ffs/adb
sleep 0.01
#Start adbd daemon
adbd &
sleep 0.1
echo "0x1" > /sys/kernel/config/usb_gadget/gadb/os_desc/b_vendor_code
sleep 10
echo "$1" > /sys/kernel/config/usb_gadget/gadb/UDC
