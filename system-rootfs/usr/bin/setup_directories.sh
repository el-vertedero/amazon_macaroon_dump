#!/bin/sh

# creates SmartHome directories with the right permissions and user
function createDir() {
    echo "Creating " $1
    mkdir -p $1
    chown -R system:system $1
    chmod -R 770 $1
}

# the main goal of this method is to try to peform the migration for
# the smarthome data, if it fails, it does not remove the old directory
# it retries again in the next reboot (or crash)
# $1 -> old directory (e.g. /data/securedStorageLocation/SmartHome)
# $2 -> new directory (e.g. /var/lib/data/dshs)
function migrate () {
echo ======== Migrating $1 to $2 ========

if [[ -L $1 ]]; then
    echo "Migration is already done, just create $2"
    createDir $2
    return 0
fi

# first remove any symbolic link
unlink $1

# check if the old directory still exists (e.g. coming from old OTA)
if [ -d $1 ]
then
    echo $1 still exists
    # make sure that the new directory exists
    createDir $2
    # migrate the data from the old directory to the new one

    # check first if the directory is empty
    if [ "$(ls -A $1)" ]
    then
        echo source directory is not empty, let us copy data
        if cp -R $1/* $2/; then
            echo Migration Passed
        else
            echo Migration failed, rolling back
            return 1
        fi
    else
        echo Migration is passed since the source directory is empty, $1
  fi

    echo continuing migration, remove old directory i.e. $1
    # remove the old directory (or back it up..)
    rm -rf $1
    # create symbolic link
    echo setting up symbolic link between $2 and $1
    ln -s $2 $1
else
    # in case of a fresh OTA
    if [ ! -d $2 ]
    then
        echo $2 is not created, let us create it
        createDir $2
    fi
    echo setting up symbolic link between $2 and $1
    ln -s $2 $1
fi
return 0
}

for n in 1 2 3
do
    echo "Trying migrating /data/securedStorageLocation, retry=$n"
    if migrate /data/securedStorageLocation /var/lib/data/dshs
    then
        break
    fi
done

echo "creating /data/misc/ if not created"
if [ ! -d '/data/misc' ]
then
    createDir /data/misc
fi

for n in 1 2 3
do
    echo "Trying migrating /data/misc/smarthome_shared, retry=$n"
    if migrate /data/misc/smarthome_shared /var/lib/data/dshs/smarthome_shared
    then
        break
    fi
done

# chip tool/sdk directory
createDir /data/securedStorageLocation/SmartHome/chip-tool
chown -R system:system /data/securedStorageLocation/SmartHome
chmod -R 770 /data/securedStorageLocation/SmartHome
createDir /data/securedStorageLocation/SmartHome_shared
createDir /data/securedStorageLocation/SmartHome_shared/images

# create EDCF directories as EDCF components are currently running as part smarthomed
# script below should be removed once separate EDCf service is created.
echo "creating /data/edcf/ if not created"
if [ ! -d '/data/edcf' ]
then
    createDir /data/edcf
fi

for n in 1 2 3
do
    echo "Trying migrating /data/edcf, retry=$n"
    if migrate /data/edcf /var/lib/data/edcf
    then
        break
    fi
done
