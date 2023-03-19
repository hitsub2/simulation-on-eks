echo "#####Setup EKS related ENV#####"

ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
CLUSTER_NAME=tusimple-eks-simulation
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.vpcId" --output text)
SUBNET_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.subnetIds[0]" --output text)
CIDR_BLOCK=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query "Vpcs[].CidrBlock" --output text)
SECURITY_GROUP_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)
AWS_REGION=us-east-1

echo "#####Create and Associate IAM OIDC Provider#####"
eksctl utils associate-iam-oidc-provider --region $AWS_REGION --cluster $CLUSTER_NAME --approve
echo "Done"

echo "#####Create IAM Policy for FSx for Lustre#####"
cat << EOF >  fsx-csi-driver.json
{
    "Version":"2012-10-17",
    "Statement":[
        {
            "Effect":"Allow",
            "Action":[
                "iam:CreateServiceLinkedRole",
                "iam:AttachRolePolicy",
                "iam:PutRolePolicy"
            ],
            "Resource":"arn:aws:iam::*:role/aws-service-role/s3.data-source.lustre.fsx.amazonaws.com/*"
        },
        {
            "Action":"iam:CreateServiceLinkedRole",
            "Effect":"Allow",
            "Resource":"*",
            "Condition":{
                "StringLike":{
                    "iam:AWSServiceName":[
                        "fsx.amazonaws.com"
                    ]
                }
            }
        },
        {
            "Effect":"Allow",
            "Action":[
                "s3:ListBucket",
                "fsx:CreateFileSystem",
                "fsx:DeleteFileSystem",
                "fsx:DescribeFileSystems",
                "fsx:TagResource"
            ],
            "Resource":[
                "*"
            ]
        }
    ]
}
EOF

aws iam create-policy --policy-name Amazon_FSx_Lustre_CSI_Driver --policy-document file://fsx-csi-driver.json
eksctl create iamserviceaccount --region $AWS_REGION --name fsx-csi-controller-sa --namespace default --cluster $CLUSTER_NAME --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/Amazon_FSx_Lustre_CSI_Driver --approve

echo "Done"



echo "#####Install Lustre CSI...#####"
export ROLE_ARN=$(aws cloudformation describe-stacks --stack-name eksctl-tusimple-eks-simulation-addon-iamserviceaccount-default-fsx-csi-controller-sa --query "Stacks[0].Outputs[0].OutputValue" --output text)
git clone https://github.com/kubernetes-sigs/aws-fsx-csi-driver
sed -i 's/kube-system/default/' ./aws-fsx-csi-driver/deploy/kubernetes/base/kustomization.yaml 
kubectl apply -k ./aws-fsx-csi-driver/deploy/kubernetes/base/
kubectl annotate serviceaccount -n default fsx-csi-controller-sa eks.amazonaws.com/role-arn=$ROLE_ARN --overwrite=true

echo "#####     All Done, Please use '$kubectl get pod | grep fsx' to check the status of CSI pods     #####"
