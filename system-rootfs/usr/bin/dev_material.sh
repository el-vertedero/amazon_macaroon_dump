#!/bin/sh
#
# Copyright 2022 - 2025 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
VERSION_STRING="1"
DEV_MAT_OUT_FILE_PATH=/var/run/dev_material/device_material.json
DM_TRIGGER_FILE=/var/run/dev_material/trigger_dev_material.txt
DHA_SELF_TEST="failed"
# DRM supported type compatible strings variable names
AmazonDHA=0x0001
WideVine=0x0010
PlayReady=0x0020
HDCP1_x=0x0040
HDCP2_xTX=0x0080
HDCP2_2RX=0x0100
FairPlay=0x0400
YouTube=0x10000
Netflix=0x20000

DT_CHOSEN_NODE_FILEPATH=/sys/firmware/devicetree/base/chosen/
SEC_DEV_PROPS=("rpmb-status" "kernel_unlocked" "prod_device" "secboot_enabled" "dm_verity_off" "root_rw")

DISK_ENCRYPTION_STATUS_FILEPATH=/tmp/disk-encryption-error

VERSION_JSON_STRING="\"version\" : "
DHA_JSON_STRING="\"dha_self_test\" : "
DRM_JSON_OBJECT_STRING="\"drm\" : {"
SEC_DEV_PROPS_JSON_OBJECT_STRING="\"device_state_props\" : {"
DISK_ENCRYPTION_STATUS_JSON_STRING="\"disk_encryption_status\" : "

form_version_json_string() {
	VERSION_JSON_STRING+="\"${VERSION_STRING}\""
}

form_dha_json_string() {
	if amzn_dha_tool -t > /dev/null 2>&1; then
		DHA_SELF_TEST="success"
	fi
	DHA_JSON_STRING+="\"${DHA_SELF_TEST}\""
}

form_drm_json_object() {
	if amzn_drmprov_tool --supported-types > /dev/null 2>&1; then
		DRM_SUPPORTED_TYPES=$(amzn_drmprov_tool --supported-types)
		DRM_UNSUPPORTED_PREFIX="Supported DRM types:"
		# Clip the non-DRM type string from the output
		DRM_SUPPORTED_TYPES=${DRM_SUPPORTED_TYPES#${DRM_UNSUPPORTED_PREFIX}}
		# Remove the whilespaces and replace '.' with '_' for mapping to variable names
		# this gives us the DRM types names in compatible variable names format (above)
		DRM_SUPPORTED_TYPES=$(echo "${DRM_SUPPORTED_TYPES}" | sed 's/ //g' | sed 's/\./_/g')
		# Save the DRM last type name for formating JSON string accordingly
		DRM_LAST_TYPE=$(echo "${DRM_SUPPORTED_TYPES}" | tail -1 | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
	fi

	for i in ${DRM_SUPPORTED_TYPES}; do
		DRM_JSON_OBJECT_STRING+="\"DRM_${i}\" : "
		if amzn_drmprov_tool -c "${!i}" > /dev/null 2>&1; then
			DRM_JSON_OBJECT_STRING+="\"exists\""
		else
			DRM_JSON_OBJECT_STRING+="\"not_exist\""
		fi
		if [[ "${i}" != "${DRM_LAST_TYPE}" ]]; then
			DRM_JSON_OBJECT_STRING+=", "
		fi
	done
	DRM_JSON_OBJECT_STRING+="}"
}

form_sec_dev_props_object() {
	local prop_file_path
	local prop_file_value
	for prop in ${SEC_DEV_PROPS[*]}; do
		SEC_DEV_PROPS_JSON_OBJECT_STRING+="\"${prop}\" : "
		prop_file_path=${DT_CHOSEN_NODE_FILEPATH}${prop}
		if [[ -f ${prop_file_path} ]]; then
			prop_file_value=$(cat "${prop_file_path}")
			SEC_DEV_PROPS_JSON_OBJECT_STRING+="\"${prop_file_value}\""
		else
			SEC_DEV_PROPS_JSON_OBJECT_STRING+="\"failed\""
		fi
		if [[ "${prop}" != "${SEC_DEV_PROPS[${#SEC_DEV_PROPS[@]}-1]}" ]]; then
			SEC_DEV_PROPS_JSON_OBJECT_STRING+=", "
		fi
	done
	SEC_DEV_PROPS_JSON_OBJECT_STRING+="}"
}

form_disk_encryption_status_json_string() {
	if [[ -f ${DISK_ENCRYPTION_STATUS_FILEPATH} ]]; then
		DISK_ENCRYPTION_STATUS_JSON_STRING+="\"failed\""
	else
		DISK_ENCRYPTION_STATUS_JSON_STRING+="\"success\""
	fi
}

form_version_json_string
form_dha_json_string
form_drm_json_object
form_sec_dev_props_object
form_disk_encryption_status_json_string

cat > ${DEV_MAT_OUT_FILE_PATH} <<EOF
{
	${VERSION_JSON_STRING},
	${DHA_JSON_STRING},
	${DRM_JSON_OBJECT_STRING},
	${SEC_DEV_PROPS_JSON_OBJECT_STRING},
	${DISK_ENCRYPTION_STATUS_JSON_STRING}
}
EOF

# We will remove this tempoary part when test team change the TCs.
TMP_DEV_MAT_OUT_FILE_PATH=/tmp/dev_material/device_material.json
cat > ${TMP_DEV_MAT_OUT_FILE_PATH} <<EOF
{
	${VERSION_JSON_STRING},
	${DHA_JSON_STRING},
	${DRM_JSON_OBJECT_STRING},
	${SEC_DEV_PROPS_JSON_OBJECT_STRING},
	${DISK_ENCRYPTION_STATUS_JSON_STRING}
}
EOF

if [[ -f ${DM_TRIGGER_FILE} ]]; then
	# Clear the trigger file
	rm -f ${DM_TRIGGER_FILE}
fi
