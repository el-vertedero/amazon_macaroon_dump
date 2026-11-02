/*
 * Copyright (c) 2021 - 2026 Amazon.com, Inc. or its affiliates.  All rights reserved.
 *
 * PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
 */

#ifndef EERO_INSIDE_AIPC_H
#define EERO_INSIDE_AIPC_H

/* Mostly values that we want to expose to other services, namely
 * the whad/AVLSu Needs the AIPC constants, and the value of
 * “WHAD_TRGRD_DISCONNECT”
 */

namespace eeroinsided
{
    // AIPC Properties


    // whad should write to this property to disable mesh mode.
    static constexpr auto WHAD_AIPC_BLOCK_MESHING_PROPERTY = "whad_block_meshing";

    /* max wait time in Second before blocking/disabling mesh - this time allows
     * any WHA capable EFD to get the blocking AIPC message, act, and report this change.
     */
    static constexpr int EERO_AIPC_SLEEP_BEFORE_BLOCKING_MESH = 2;

    static constexpr auto EERO_AIPC_MESH_STATUS = "mesh_status";

    /* whad property, sampled during eeroiniside init process to cover the case that whad
     * is in “client” mode before eeroinside started running.
     * If whad is running/switching to “client” mode, eeroinside should not run/enable mesh mode.
     */
    static constexpr auto AIPC_PUFFIN_MRMD_SAP_ROLE = "sap_role";
    static constexpr auto AIPC_PUFFIN_MRMD_CLIENT_ROLE = "Client";
    static constexpr auto AIPC_PUFFIN_MRMD_HOST_ROLE = "Host";

    /* Any active mesh disable requests via AIPC - value persist cross reboots */
    static constexpr auto ERI_AIPC_MESH_DISABLE = "persist.eri-aipc.mesh.disable";


    /* Puffin property reflected to the Alexa cloud
     * https://wiki.labcollab.net/confluence/display/Doppler/eero+built-in+new+setting+with+Device+as+Principal+Type
     */
    static constexpr auto AIPC_PUFFIN_EERO_MESH_PROPERTY = "EeroBuiltin.Active";
    static constexpr auto USS_MESH_ENABLED = "ENABLED";
    static constexpr auto USS_MESH_DISABLED = "DISABLED";

    typedef enum {
        ERI_GATEWAY_TRGRD_STOP = 0,
        ERI_MESHIFACEDIS_TRGRD_STOP,
        ERI_AIPC_TRGRD_DISCONNECT,
        ERI_THERMAL_TRGRD_STOP,
        ERI_PROP_TRGRD_STOP,
        ERI_CONNLOST_TRGRD_STOP,
        ERI_ERIDCRASH_TRGRD_STOP,
        ERI_WPAHAPDCRASH_TRGRD_STOP,
        ERI_APENFAIL_TRGRD_STOP,
        ERI_CHANNELSW_TRGRD_STOP,
        ERI_BIFROST_VER_TRGRD_STOP,
        ERI_MESHENFAIL_TRGRD_STOP,
        ERI_NO_BEACON_TRGRD_STOP,
        ERI_GW_PING_TIMEOUT_TRGRD_STOP,
        ERI_WIFISVC_RESTART_TRGRD_STOP,
        ERI_TRGRD_STOP_MAX,
        //on updating this also update getStrFromStopReasonCode()
    } eriMeshStopReason;

    /* incoming request to disable mesh via AIPC, all incoming request
     * will muxed into ERI_AIPC_TRGRD_DISCONNECT in the eriMeshStopReason.
     * When requesters remove previous requests, AIPC mesh disable stands
     * until the last requesters remove any standing disable requests.
     */
    typedef enum {
        ERI_AIPC_REMOVE_TRGRD_DISCONNECT = 0,
        ERI_AIPC_WHAD_TRGRD_DISCONNECT,
        ERI_AIPC_MESH_STOP_REASON_MAX, // Must be last
    } eriAipcMeshStopReason;

} //namespace eeroinsided

#endif // EERO_INSIDE_AIPC_H

