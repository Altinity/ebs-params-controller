# EBS Params Controller

This controller provides a way to control iops and throughput parameters for EBS volumes
provisioned by EBS CSI Driver with annotations on corresponding PersistentVolumeClaim objects in Kubernetes.
It also sets some annotations on PVCs backed by EBS CSI Driver representing current parameters and last modification status and timestamps.

## Installation 

**To create your EBS Params Controller IAM role with the AWS Management Console**

1. Open the IAM console at https://console.aws.amazon.com/iam/
2. In the left navigation pane, choose **Roles**.
3. On the **Roles** page, choose **Create role**.
4. On the **Select trusted entity** page, do the following:
   - a. In the **Trusted entity type** section, choose **Web identity**.
   - b. For **Identity provider**, choose the **OpenID Connect provider URL** for your cluster (as shown under **Overview** in Amazon EKS).
   - c. For **Audience**, choose `sts.amazonaws.com`.
   - d. Choose **Next**.
5. On the **Add permissions page**, skip everything and choose **Next**.
6. On the **Name, review, and create** page, do the following:
   - a. For **Role name**, enter a unique name for your role, such as ***AltinityRoleForEBSParamsController***.
   - b. Under **Add tags (Optional)**, add metadata to the role by attaching tags as key–value pairs. For more information about using tags in IAM, see [Tagging IAM Entities](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_tags.html) in the _IAM User Guide_.
   - c. Choose Create role.
7. After the role is created, choose the role in the console to open it for editing.
8. On the **Permissions** tab, choose **Add permissions**, and then choose **Create inline policy**.
9. Choose **JSON**, and replace the contents in the **Policy editor** with the following code:
```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:ModifyVolume",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumesModifications"
      ],
      "Resource": "*"
    }
  ]
}
```
10. Choose **Next**, then enter a unique policy name, such as ***AltinityEBSParamsControllerPolicy***.
11. Choose **Create policy**
12. Choose the **Trust relationships** tab, and then choose **Edit trust policy**.
13. Find the line that looks similar to the following line:
```
"oidc.eks.region-code.amazonaws.com/id/EXAMPLE168660E7300CC5879EEXAMPLE:aud": "sts.amazonaws.com"
```
Add a comma to the end of the previous line, and then add the following line after the previous line. Replace `region-code` with the AWS Region that your cluster is in. Replace `EXAMPLE168660E7300CC5879EEXAMPLE` with your cluster's OIDC provider ID.
```
"oidc.eks.region-code.amazonaws.com/id/EXAMPLE168660E7300CC5879EEXAMPLE:sub": "system:serviceaccount:kube-system:ebs-params-controller"
```
14. Choose **Update policy** to finish.
15. Copy the **ARN** value from the role's **Summary**.

**To deploy the EBS Params Controller**

1. Save the **Manifest** from https://github.com/Altinity/ebs-params-controller/blob/main/deployment.yaml
2. Replace the `${role_arn}` string with your role's **ARN**.
3. Apply the **Manifest**:
```
kubectl apply -n kube-system -f deployment.yaml
```

## Annotations to control parameters

| Annotation | Description | Example |
| :--------- | :---------- | :------ |
| spec.epc.altinity.com/throughput | Defines the required Throughput value | `spec.epc.altinity.com/throughput: "300"` |
| spec.epc.altinity.com/iops | Defines the required IOPS value | `spec.epc.altinity.com/iops: "6000"` |
| spec.epc.altinity.com/type | Defines the required EBS volume type. <br> Possible values are: io1, io2, gp2, gp3, sc1, st1, sbp1, sbg1 | `spec.epc.altinity.com/type: "gp3"` |

## Annotations to display current volume status

| Annotation | Description | 
| :--------- | :---------- |
| status.epc.altinity.com/throughput | Current Throughput |
| status.epc.altinity.com/iops | Current IOPS |
| status.epc.altinity.com/type | Current volume type |
| status.epc.altinity.com/mod-state | Represents the state of last volume modification attempt. Empty string if never modified before. Other possible values are `modifying`, `optimizing`, `completed`, or `failed` |
| status.epc.altinity.com/mod-start-time | Timestamp of the beginning of last modification attempt. Empty string if never modified before |
| status.epc.altinity.com/mod-end-time | Timestamp of the end of last modification attempt. Empty string if modification is in progress or the volume was never modified before |   

## License

Copyright (c) 2022-2023, Altinity Inc and/or its affiliates. All rights reserved.

EBS Params Controller is licensed under the Apache License 2.0.
