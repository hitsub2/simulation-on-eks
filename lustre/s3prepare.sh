echo "###### Preparing new S3 bucket and example files ######"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
CLUSTER_NAME=tusimple-eks-simulation
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.vpcId" --output text)
SUBNET_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.subnetIds[0]" --output text)
CIDR_BLOCK=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query "Vpcs[].CidrBlock" --output text)
S3_LOGS_BUCKET=eks-fsx-lustre-$(cat /dev/urandom | LC_ALL=C tr -dc "[:alpha:]" | tr '[:upper:]' '[:lower:]' | head -c 32)
SECURITY_GROUP_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)
AWS_REGION=us-east-1

aws s3 mb s3://$S3_LOGS_BUCKET
echo This is the context in the testfile >> testfile
aws s3 cp testfile s3://$S3_LOGS_BUCKET/testfile

echo "Done!"

echo "##### Creating StorageClass for FSx Lustre and link to example S3 bucket"
cat << EOF > storageclass.yaml
---
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
    name: fsx-sc
provisioner: fsx.csi.aws.com
parameters:
    subnetId: ${SUBNET_ID}
    securityGroupIds: ${SECURITY_GROUP_ID}
    s3ImportPath: s3://${S3_LOGS_BUCKET}
    s3ExportPath: s3://${S3_LOGS_BUCKET}/export
    deploymentType: SCRATCH_2
mountOptions:
    - flock
EOF

kubectl apply -f ./storageclass.yaml

echo "Done!"
