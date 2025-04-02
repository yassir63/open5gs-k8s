#!/bin/bash

echo 'Configuring bridges for use by ovs-cni ...'

ovs-vsctl --may-exist add-br n2br
ovs-vsctl --may-exist add-br n3br
ovs-vsctl --may-exist add-br n4br

echo 'install ovs-cni'

kubectl apply -f https://github.com/kubevirt/cluster-network-addons-operator/releases/download/v0.98.1/namespace.yaml
kubectl apply -f https://github.com/kubevirt/cluster-network-addons-operator/releases/download/v0.98.1/network-addons-config.crd.yaml
kubectl apply -f https://github.com/kubevirt/cluster-network-addons-operator/releases/download/v0.98.1/operator.yaml

  # kubectl apply -f https://gist.githubusercontent.com/niloysh/1f14c473ebc08a18c4b520a868042026/raw/d96f07e241bb18d2f3863423a375510a395be253/network-addons-config.yaml
cat <<EOF > "/tmp/netaddonsconf.yaml"
apiVersion: networkaddonsoperator.network.kubevirt.io/v1
kind: NetworkAddonsConfig
metadata:
  name: cluster
spec:
  ovs: {}
EOF
kubectl apply -f /tmp/netaddonsconf.yaml
kubectl wait networkaddonsconfig cluster --for condition=Available

echo 'Done, you can now run script start-core.sh'
