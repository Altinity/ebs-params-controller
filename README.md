# EBS Params Controller

This controller provides a way to control iops and throughput parameters for EBS volumes
provisioned by EBS CSI Driver with annotations on corresponding PersistentVolumeClaim objects in Kubernetes.
It also sets some annotations on PVCs backed by EBS CSI Driver representing current parameters and last modification status and timestamps.

## Annotations to control parameters

### spec.epc.altinity.com/iops

Defines the required Iops value. Example: `spec.epc.altinity.com/iops: "6000"`

### spec.epc.altinity.com/throughput

Defines the required Throughput value. Example: `spec.epc.altinity.com/throughput: "300"`

## Annotations to display current volume status

### status.epc.altinity.com/iops

Current Iops.

### status.epc.altinity.com/throughput

Current Throughput.

### status.epc.altinity.com/mod-state

Represents the state of last volume modification attempt. Empty string if never modified before. Other possible values are `modifying`, `optimizing`, `completed`, or `failed`.

### status.epc.altinity.com/mod-start-time

Timestamp of the beginning of last modification attempt. Empty string if never modified before.

### status.epc.altinity.com/mod-end-time

Timestamp of the end of last modification attempt. Empty string if modification is in progress or the volume was never modified before.   
