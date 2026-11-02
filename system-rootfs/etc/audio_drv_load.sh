#!/bin/sh

echo "load Audio kerneldriver"

modprobe -a gpio-amzncpld dw-audio-dmac-platform hifi_pre_machine acs_audio_client voice_dsp_card codec_utils hifi1_cpu ax5688 aw85805s aw89401 aw85806 es7210L es7243l tlv320adc5140 tlv320adc5120 tas5805m tas5815m tas2781 tas5815m tas6582 hifi1_debug hifi1_pcm hifi_host_driver adf_sound_card hifi_proc hifi1_machine
