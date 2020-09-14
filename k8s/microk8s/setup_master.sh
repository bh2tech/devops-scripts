# /bin/bash

# install docker
sudo snap install docker

# install microk8s from snap
sudo snap install microk8s --classic

# enable addons
echo "Enable microk8s addons"
sudo microk8s enable dns ingress helm3

while true; do
    read -p "Do you wish to install letsencrypt? [y/n]" yn
    case $yn in
        [Yy]* ) INSTALL_LETSENCRYPT=1; break;;
        [Nn]* ) INSTALL_LETSENCRYPT=0; break;;
        * ) echo "Please answer yes or no.";;
    esac
done

if [ "$INSTALL_LETSENCRYPT" = 1 ]
then
read -p "Enter email for letsencrypt certificate: " EMAIL

# create issuer
sudo microk8s.kubectl create namespace cert-manager
sudo microk8s.kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.12.0/cert-manager.yaml
cat << EOF | sudo microk8s.kubectl apply -f -
apiVersion: cert-manager.io/v1alpha2
kind: ClusterIssuer
metadata:
 name: letsencrypt-dev
 namespace: cert-manager
spec:
 acme:
   # The ACME server URL
   server: https://acme-v02.api.letsencrypt.org/directory
   # Email address used for ACME registration
   email: $EMAIL
   # Name of a secret used to store the ACME account private key
   privateKeySecretRef:
     name: letsencrypt-dev
   # Enable the HTTP-01 challenge provider
   solvers:
   - http01:
       ingress:
         class: nginx
EOF

echo "To use the certificate on your API, using the following script"
cat << EOF
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
    namespace: {{ K8S_NAMESPACE }}
    name: {{ SERVICE_NAME_TAG }}
annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-dev"
spec:
tls:
- hosts:
    - {{ SERVICE_NAME }}.{{ DOMAIN }}
    secretName: {{ SERVICE_NAME }}-tls
rules:
- host: {{ SERVICE_NAME }}.{{ DOMAIN }}
    http:
    paths:
    - backend:
        serviceName: {{ SERVICE_NAME }}
        servicePort: 80
EOF
else
echo "To use your certificate, run:"
echo "kubectl create secret tls certificate-tls --key=\"tls.key\" --cert=\"tls.crt\""
echo ""
fi
# show tokens
KNOWN_TOKENS_FILE=/var/snap/microk8s/current/credentials/known_tokens.csv
# KNOWN_TOKENS_FILE=known_hosts.csv

FIRST_LINE="$(sudo head -1 $KNOWN_TOKENS_FILE)"

IFS=',' read -ra DATA <<< "$FIRST_LINE"

K8S_TOKEN="${DATA[0]}"
K8S_USERNAME="${DATA[1]}"
K8S_CLUSTER_IP="$(dig @resolver1.opendns.com ANY myip.opendns.com +short)"

echo "The cluster crendentials are:"
echo ""
echo "K8S_TOKEN=$K8S_TOKEN"
echo "K8S_USERNAME=$K8S_USERNAME"
echo "K8S_CLUSTER_IP=https://$K8S_CLUSTER_IP:16443"

echo ""

echo "In order to configure the connection on your machine, run the following commands:"
echo ""
echo "kubectl config set-cluster cluster --server=$K8S_CLUSTER_IP --insecure-skip-tls-verify"
echo "kubectl config set-credentials $K8S_USERNAME --token=$K8S_TOKEN"
echo "kubectl config set-context dev --cluster=cluster --user=$K8S_USERNAME"

echo ""
echo ""
echo ""
echo "To get more info, go to https://microk8s.io/docs"
