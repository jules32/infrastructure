/*
    This file is a jsonnet template of a eksctl's cluster configuration file,
    that is used with the eksctl CLI to both update and initialize an AWS EKS
    based cluster.

    This file has in turn been generated from eksctl/template.jsonnet which is
    relevant to compare with for changes over time.

    To use jsonnet to generate an eksctl configuration file from this, do:

        jsonnet earthscope.jsonnet > earthscope.eksctl.yaml

    References:
    - https://eksctl.io/usage/schema/
*/
local ng = import "./libsonnet/nodegroup.jsonnet";

// place all cluster nodes here
local clusterRegion = "us-east-2";
local masterAzs = ["us-east-2a", "us-east-2b", "us-east-2c"];
local nodeAz = "us-east-2a";

// Node definitions for notebook nodes. Config here is merged
// with our notebook node definition.
// A `node.kubernetes.io/instance-type label is added, so pods
// can request a particular kind of node with a nodeSelector
local notebookNodes = [
    { instanceType: "r5.xlarge" },
    { instanceType: "r5.4xlarge" },
    { instanceType: "r5.16xlarge" },
];
local daskNodes = [
    // Node definitions for dask worker nodes. Config here is merged
    // with our dask worker node definition, which uses spot instances.
    // A `node.kubernetes.io/instance-type label is set to the name of the
    // *first* item in instanceDistribution.instanceTypes, to match
    // what we do with notebook nodes. Pods can request a particular
    // kind of node with a nodeSelector
    //
    // A not yet fully established policy is being developed about using a single
    // node pool, see https://github.com/2i2c-org/infrastructure/issues/2687.
    //
    { instancesDistribution+: { instanceTypes: ["r5.4xlarge"] }},
];


{
    apiVersion: 'eksctl.io/v1alpha5',
    kind: 'ClusterConfig',
    metadata+: {
        name: "earthscope",
        region: clusterRegion,
        version: "1.28",
    },
    availabilityZones: masterAzs,
    iam: {
        withOIDC: true,
    },
    // If you add an addon to this config, run the create addon command.
    //
    //    eksctl create addon --config-file=earthscope.eksctl.yaml
    //
    addons: [
        {
            // aws-ebs-csi-driver ensures that our PVCs are bound to PVs that
            // couple to AWS EBS based storage, without it expect to see pods
            // mounting a PVC failing to schedule and PVC resources that are
            // unbound.
            //
            // Related docs: https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html
            //
            name: 'aws-ebs-csi-driver',
            version: "latest",
            wellKnownPolicies: {
                ebsCSIController: true,
            },
        },
    ],
    nodeGroups: [
        ng + {
            namePrefix: 'core',
            nameSuffix: 'a',
            nameIncludeInstanceType: false,
            availabilityZones: [nodeAz],
            ssh: {
                publicKeyPath: 'ssh-keys/earthscope.key.pub'
            },
            instanceType: "r5.xlarge",
            minSize: 1,
            maxSize: 6,
            labels+: {
                "hub.jupyter.org/node-purpose": "core",
                "k8s.dask.org/node-purpose": "core"
            },
        },
    ] + [
        ng + {
            namePrefix: 'nb',
            availabilityZones: [nodeAz],
            minSize: 0,
            maxSize: 500,
            instanceType: n.instanceType,
            ssh: {
                publicKeyPath: 'ssh-keys/earthscope.key.pub'
            },
            labels+: {
                "hub.jupyter.org/node-purpose": "user",
                "k8s.dask.org/node-purpose": "scheduler"
            },
            taints+: {
                "hub.jupyter.org_dedicated": "user:NoSchedule",
                "hub.jupyter.org/dedicated": "user:NoSchedule"
            },
        } + n for n in notebookNodes
    ] + ( if daskNodes != null then
        [
        ng + {
            namePrefix: 'dask',
            availabilityZones: [nodeAz],
            minSize: 0,
            maxSize: 500,
            ssh: {
                publicKeyPath: 'ssh-keys/earthscope.key.pub'
            },
            labels+: {
                "k8s.dask.org/node-purpose": "worker"
            },
            taints+: {
                "k8s.dask.org_dedicated" : "worker:NoSchedule",
                "k8s.dask.org/dedicated" : "worker:NoSchedule"
            },
            instancesDistribution+: {
                onDemandBaseCapacity: 0,
                onDemandPercentageAboveBaseCapacity: 0,
                spotAllocationStrategy: "capacity-optimized",
            },
        } + n for n in daskNodes
        ] else []
    )
}