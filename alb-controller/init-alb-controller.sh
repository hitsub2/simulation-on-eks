
#!/bin/bash
#install ingress-alb
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
export AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
export VPC_ID=$(aws eks describe-cluster --name tusimple-eks-simulation  --query "cluster.resourcesVpcConfig.vpcId" --output text)
echo 'export LBC_VERSION="v2.4.1"' >>  ~/.bash_profile
echo 'export LBC_CHART_VERSION="1.4.1"' >>  ~/.bash_profile
source  ~/.bash_profile

#verify if the AWS Load Balancer Controller version has been set
if [ ! -x ${LBC_VERSION} ]
  then
    tput setaf 2; echo '${LBC_VERSION} has been set.'
  else
    tput setaf 1;echo '${LBC_VERSION} has NOT been set.'
fi

#Create IAM OIDC provider 
eksctl utils associate-iam-oidc-provider \
    --region ${AWS_REGION} \
    --cluster tusimple-eks-simulation \
    --approve

#Create a policy called AWSLoadBalancerControllerIAMPolicy
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${LBC_VERSION}/docs/install/iam_policy.json
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json

#Create a IAM role and ServiceAccount 
eksctl create iamserviceaccount \
  --cluster tusimple-eks-simulation \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

#Install the TargetGroupBinding CRDs 
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"

kubectl get crd

#deploy the ingress alb helm chart.
helm repo add eks https://aws.github.io/eks-charts

helm upgrade -i aws-load-balancer-controller \
    eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=tusimple-eks-simulation \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set image.tag="${LBC_VERSION}" \
    --set vpcId="${VPC_ID}" \
    --version="${LBC_CHART_VERSION}"

kubectl -n aws-load-balancer rollout status deployment aws-load-balancer-controller