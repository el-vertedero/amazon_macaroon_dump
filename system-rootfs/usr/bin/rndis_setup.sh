#!/bin/sh

USB_GADGET_1_PATH=/sys/kernel/config/usb_gadget/g1
mkdir -p /dev/pts
if mount -t devpts none /dev/pts &> /dev/null ; then
  echo "devpts mounted"
else
  echo "devpts mount failed"
  exit 1
fi
sleep 0.01

MODULE="libcomposite.ko"
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
	echo " rndis_setup.sh <b1000000.usb>"
	exit 1
fi

if mount -t configfs none /sys/kernel/config &> /dev/null ; then
  echo "configfs mounted"
else
  echo "configfs mount failed"
  exit 1
fi
sleep 0.01

mkdir -p $USB_GADGET_1_PATH
sleep 0.01
echo 0x0200 > $USB_GADGET_1_PATH/bcdUSB
echo "0x1949" > $USB_GADGET_1_PATH/idVendor
echo "0x1950" > $USB_GADGET_1_PATH/idProduct
mkdir -p $USB_GADGET_1_PATH/strings/0x409
echo "Amazon Azma15" > $USB_GADGET_1_PATH/strings/0x409/serialnumber
echo "Amazon Inc" > $USB_GADGET_1_PATH/strings/0x409/manufacturer
echo "Azma15 BSP Ethernet" >  $USB_GADGET_1_PATH/strings/0x409/product

mkdir -p $USB_GADGET_1_PATH/configs/b.1
sleep 0.01
mkdir -p $USB_GADGET_1_PATH/configs/b.1/strings/0x409
sleep 0.01

echo "RNDIS" > $USB_GADGET_1_PATH/configs/b.1/strings/0x409/configuration
sleep 0.01
mkdir -p $USB_GADGET_1_PATH/functions/rndis.usb0
sleep 0.01
ln -s $USB_GADGET_1_PATH/functions/rndis.usb0 $USB_GADGET_1_PATH/configs/b.1
sleep 0.01
echo "$1" > $USB_GADGET_1_PATH/UDC
