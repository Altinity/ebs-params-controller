#!/usr/bin/env bash

source /shell_lib.sh

EBS_VOL_MODS=''

function __config__() {
    cat <<EOF
configVersion: v1
kubernetes:
- apiVersion: v1
  name: pvcs
  kind: PersistentVolumeClaim
  executeHookOnEvent: [ "Added", "Modified" ]
  includeSnapshotsFrom: ["pvs"]
- apiVersion: v1
  name: pvs
  kind: PersistentVolume
  executeHookOnSynchronization: false
  executeHookOnEvent: []
schedule:
- name: cron
  crontab: "*/5 * * * *"
  includeSnapshotsFrom: ["pvcs", "pvs"]
EOF
}

function __on_kubernetes::pvcs::synchronization() {
  echo "Sync context: ${BINDING_CONTEXT_CURRENT_BINDING}[${BINDING_CONTEXT_CURRENT_INDEX}]"
  PVCS_LENGTH=$(context::jq -r '.objects|length')
  echo "Received ${PVCS_LENGTH} PVC objects"
  for i in $(seq 0 $((PVCS_LENGTH - 1))); do
    PVCS_CURRENT_INDEX="${i}"
    PVCS_CURRENT_JSON=$(context::jq '.objects['"${PVCS_CURRENT_INDEX}"'].object')
    pvc::process
  done
}

function __on_kubernetes::pvcs::added_or_modified() {
  echo "Added or modified context: ${BINDING_CONTEXT_CURRENT_BINDING}[${BINDING_CONTEXT_CURRENT_INDEX}]"
  PVCS_CURRENT_JSON=$(context::jq '.object')
  pvc::process
}

function __on_schedule::cron() {
  echo "Cron context: ${BINDING_CONTEXT_CURRENT_BINDING}[${BINDING_CONTEXT_CURRENT_INDEX}]"
  PVCS_LENGTH=$(context::jq -r '.snapshots.pvcs|length')
  echo "Received ${PVCS_LENGTH} PVC objects"
  for i in $(seq 0 $((PVCS_LENGTH - 1))); do
    PVCS_CURRENT_INDEX="${i}"
    PVCS_CURRENT_JSON=$(context::jq '.snapshots.pvcs['"${PVCS_CURRENT_INDEX}"'].object')
    pvc::process
  done
}

function pvc::jq() {
  echo "$PVCS_CURRENT_JSON" | jq "$@"
}

function pvc::process() {
  echo "Processing..."
  pvc::jq -r '.metadata.name'

  if [[ $(pvc::jq -r '.status.phase') != "Bound" ]]; then
    echo "Not bound"
    return 0
  fi

  VOLUME_NAME=$(pvc::jq -r '.spec.volumeName')
  if [[ "$VOLUME_NAME" == 'null' || "$VOLUME_NAME" == '' ]]; then
    echo "No volume name"
    return 0
  fi

  if [[ $(pvc::jq -r '.metadata.annotations."volume.beta.kubernetes.io/storage-provisioner"') != 'ebs.csi.aws.com' ]]; then
    echo "Not a EBS CSI volume"
    return 0
  fi

  pvc::jq -r '.spec.volumeName'

  PV_JSON=$(context::jq '.snapshots.pvs[]|select(.object.metadata.name=="'"$VOLUME_NAME"'").object')

  EBS_VOL_ID=$(echo "$PV_JSON" | jq -r '.spec.csi.volumeHandle')
  echo "$EBS_VOL_ID"

  EBS_VOL_JSON="$(aws ec2 describe-volumes --volume-ids "$EBS_VOL_ID" | jq -c '.Volumes[0]')"

  if [[ "$EBS_VOL_JSON" == 'null' ]]; then
    echo "Failed to obtain volume information from AWS"
    return 0
  fi

  if [[ -z $EBS_VOL_MODS ]]; then
    EBS_VOL_MODS="$(aws ec2 describe-volumes-modifications)"
  fi

  EBS_VOL_IOPS="$(echo "$EBS_VOL_JSON" | jq -r '.Iops')"
  EBS_VOL_TP="$(echo "$EBS_VOL_JSON" | jq -r '.Throughput')"
  EBS_VOL_MOD_STATE="$(echo "$EBS_VOL_MODS" | jq -r '.VolumesModifications[]|select(.VolumeId=="'"$EBS_VOL_ID"'").ModificationState')"
  EBS_VOL_MOD_START_TIME="$(echo "$EBS_VOL_MODS" | jq -r '.VolumesModifications[]|select(.VolumeId=="'"$EBS_VOL_ID"'").StartTime')"
  EBS_VOL_MOD_END_TIME="$(echo "$EBS_VOL_MODS" | jq -r '.VolumesModifications[]|select(.VolumeId=="'"$EBS_VOL_ID"'").EndTime')"
  if [[ "$EBS_VOL_MOD_END_TIME" == 'null' ]]; then
    EBS_VOL_MOD_END_TIME=''
  fi

  if [[ -n $EBS_VOL_MOD_END_TIME || -z $EBS_VOL_MOD_START_TIME ]]; then
    EBS_VOL_MOD_ARGS=''

    SPEC_IOPS="$(pvc::jq -r '.metadata.annotations."spec.epc.altinity.com/iops"')"
    if [[ "$SPEC_IOPS" == 'null' ]]; then
      SPEC_IOPS=''
    fi

    if [[ -n $SPEC_IOPS && "$SPEC_IOPS" != "$EBS_VOL_IOPS" ]]; then
      EBS_VOL_MOD_ARGS+=' --iops='"$SPEC_IOPS"
    fi

    SPEC_TP="$(pvc::jq -r '.metadata.annotations."spec.epc.altinity.com/throughput"')"
    if [[ "$SPEC_TP" == 'null' ]]; then
      SPEC_TP=''
    fi

    if [[ -n $SPEC_TP && "$SPEC_TP" != "$EBS_VOL_TP" ]]; then
      EBS_VOL_MOD_ARGS+=' --throughput='"$SPEC_TP"
    fi

    if [[ -n $EBS_VOL_MOD_ARGS ]]; then
      set +e
      MOD_JSON="$(aws ec2 modify-volume --volume-id="${EBS_VOL_ID}" ${EBS_VOL_MOD_ARGS})"
      RET=$?
      set -e
      if [[ $RET -ne 0 ]]; then
        echo "Aws CLI failed with exit code ${RET}"
        return 0
      fi

      EBS_VOL_MOD_STATE="$(echo "$MOD_JSON" | jq -r '.VolumeModification.ModificationState')"
      EBS_VOL_MOD_START_TIME="$(echo "$MOD_JSON" | jq -r '.VolumeModification.StartTime')"
      EBS_VOL_MOD_END_TIME=''
    fi
  fi

  JQFILTER=''

  if [[ "$EBS_VOL_IOPS" != "$(pvc::jq -r '.metadata.annotations."status.epc.altinity.com/iops"')" ]]; then
    JQFILTER+="${JQFILTER:+|}"'.metadata.annotations."status.epc.altinity.com/iops"="'"$EBS_VOL_IOPS"'"'
  fi

  if [[ "$EBS_VOL_TP" != "$(pvc::jq -r '.metadata.annotations."status.epc.altinity.com/throughput"')" ]]; then
    JQFILTER+="${JQFILTER:+|}"'.metadata.annotations."status.epc.altinity.com/throughput"="'"$EBS_VOL_TP"'"'
  fi

  if [[ "$EBS_VOL_MOD_STATE" != "$(pvc::jq -r '.metadata.annotations."status.epc.altinity.com/mod-state"')" ]]; then
    JQFILTER+="${JQFILTER:+|}"'.metadata.annotations."status.epc.altinity.com/mod-state"="'"$EBS_VOL_MOD_STATE"'"'
  fi

  if [[ "$EBS_VOL_MOD_START_TIME" != "$(pvc::jq -r '.metadata.annotations."status.epc.altinity.com/mod-start-time"')" ]]; then
    JQFILTER+="${JQFILTER:+|}"'.metadata.annotations."status.epc.altinity.com/mod-start-time"="'"$EBS_VOL_MOD_START_TIME"'"'
  fi

  if [[ "$EBS_VOL_MOD_END_TIME" != "$(pvc::jq -r '.metadata.annotations."status.epc.altinity.com/mod-end-time"')" ]]; then
    JQFILTER+="${JQFILTER:+|}"'.metadata.annotations."status.epc.altinity.com/mod-end-time"="'"$EBS_VOL_MOD_END_TIME"'"'
  fi

  if [[ -n "${JQFILTER}" ]]; then
    echo "Applying jqFilter ${JQFILTER}"
    cat <<EOF >>"$KUBERNETES_PATCH_PATH"
---
operation: JQPatch
kind: PersistentVolumeClaim
namespace: $(pvc::jq -r '.metadata.namespace')
name: $(pvc::jq -r '.metadata.name')
jqFilter: '${JQFILTER}'
EOF
  fi
}

hook::run "$@"
