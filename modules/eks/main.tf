# EKS Module - Main Configuration

# Data Sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# EKS Cluster IAM Role
resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# EKS Cluster Security Group
resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  vpc_id      = var.vpc_id
  description = "Security group for EKS cluster control plane"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-cluster-sg"
    }
  )
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
    security_group_ids      = [aws_security_group.cluster.id]
  }

  encryption_config {
    provider {
      key_arn = var.kms_key_id
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_policy
  ]
}

# OIDC Provider for IRSA
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  tags            = var.tags
}

# Node IAM Role
resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.node.name
}

# Additional policy for EBS CSI Driver
resource "aws_iam_role_policy" "node_ebs_policy" {
  name = "${var.cluster_name}-node-ebs-policy"
  role = aws_iam_role.node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:ModifyVolume",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ]
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = [
              "CreateVolume",
              "CreateSnapshot"
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteTags"
        ]
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
        }
      }
    ]
  })
}

# Launch Template for Main Node Group (with NVMe mounting)
resource "aws_launch_template" "main" {
  name_prefix = "${var.cluster_name}-main-"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 50 # Smaller root volume since we have NVMe
      volume_type = "gp3"
      encrypted   = true
    }
  }

  # User data script in MIME multipart format (required for EKS managed node groups)
  # NOTE: Do NOT call bootstrap.sh - EKS managed node groups handle this automatically
  user_data = base64encode(<<-EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="

--==MYBOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
set -ex

# DO NOT call /etc/eks/bootstrap.sh here - EKS managed node groups handle it automatically
# Mount NVMe storage and configure containerd to use it

echo "Starting NVMe mount and containerd configuration script..."

# Wait for NVMe devices to be available
sleep 5

# Find the NVMe device (not the root device)
NVME_DEVICE=$(lsblk -d -n | grep nvme | grep -v nvme0n1 | head -1 | awk '{print "/dev/"$1}')

if [ ! -z "$NVME_DEVICE" ]; then
  echo "Found NVMe device: $NVME_DEVICE"

  # Check if already formatted
  if ! blkid $NVME_DEVICE; then
    echo "Formatting $NVME_DEVICE with ext4..."
    mkfs -t ext4 $NVME_DEVICE
  fi

  # Mount to /mnt/nvme
  mkdir -p /mnt/nvme
  mount $NVME_DEVICE /mnt/nvme
  chmod 755 /mnt/nvme

  # Add to fstab for persistence
  if ! grep -q "$NVME_DEVICE" /etc/fstab; then
    echo "$NVME_DEVICE /mnt/nvme ext4 defaults,noatime 0 0" >> /etc/fstab
  fi

  # Create containerd directories on NVMe
  mkdir -p /mnt/nvme/containerd
  chmod 711 /mnt/nvme/containerd

  # Stop containerd before moving data
  systemctl stop containerd || true

  # Move existing containerd data if it exists and hasn't been moved yet
  if [ -d /var/lib/containerd ] && [ ! -L /var/lib/containerd ]; then
    echo "Moving existing containerd data to NVMe..."
    cp -a /var/lib/containerd/* /mnt/nvme/containerd/ 2>/dev/null || true
    mv /var/lib/containerd /var/lib/containerd.old
  fi

  # Create symlink from /var/lib/containerd to NVMe location
  ln -sf /mnt/nvme/containerd /var/lib/containerd

  # Restart containerd
  systemctl start containerd

  echo "NVMe successfully mounted and containerd configured to use it"
  df -h /mnt/nvme
  ls -la /var/lib/containerd
else
  echo "No NVMe device found - using default storage on root volume"
fi

--==MYBOUNDARY==--
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.tags,
      {
        Name = "${var.cluster_name}-main-node"
      }
    )
  }
}

# Main Node Group (Legacy 2-node architecture)
# Only created if use_three_node_groups = false
resource "aws_eks_node_group" "main" {
  count = var.use_three_node_groups ? 0 : 1

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-main"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.main_node_subnet_ids != null ? var.main_node_subnet_ids : var.subnet_ids

  instance_types = var.main_node_instance_types
  capacity_type  = var.main_enable_spot_instances ? "SPOT" : "ON_DEMAND"
  ami_type       = "AL2023_x86_64_STANDARD"

  # Use the launch template with NVMe mounting script
  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  scaling_config {
    desired_size = var.main_node_desired_size
    max_size     = var.main_node_max_size
    min_size     = var.main_node_min_size
  }

  update_config {
    max_unavailable_percentage = 33
  }

  labels = {
    role = "main"
    type = var.main_enable_spot_instances ? "spot" : "on-demand"
  }

  # NOTE: No taint on main nodes - system pods (CoreDNS, EBS CSI) need to run here
  # Taints are only applied to dask_workers node group below

  tags = merge(
    var.tags,
    {
      Name                                            = "${var.cluster_name}-main-node"
      "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      "k8s.io/cluster-autoscaler/enabled"             = "true"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_registry_policy
  ]
}

# System Node Group (3-node architecture)
# Always running, runs Hub, Kubecost, Prometheus, system pods
resource "aws_eks_node_group" "system" {
  count = var.use_three_node_groups ? 1 : 0

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-system"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = var.system_node_instance_types
  capacity_type  = var.system_enable_spot_instances ? "SPOT" : "ON_DEMAND"
  ami_type       = "AL2023_x86_64_STANDARD"

  scaling_config {
    desired_size = var.system_node_desired_size
    max_size     = var.system_node_max_size
    min_size     = var.system_node_min_size
  }

  update_config {
    max_unavailable_percentage = 33
  }

  labels = {
    role = "system"
    type = var.system_enable_spot_instances ? "spot" : "on-demand"
  }

  # NOTE: No taint on system nodes!
  # EKS managed add-ons (CoreDNS, EBS CSI) need to run on system nodes
  # and don't have tolerations configured.
  # We use nodeSelectors in Helm configs to control pod placement instead.

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-system-node"
      # System nodes don't autoscale
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_registry_policy
  ]
}

# User Node Groups (3-node architecture)
# Split into separate groups for Small (r5.large) and Medium (r5.xlarge) profiles
# This allows cluster autoscaler to scale the correct instance type for each profile

# User Small Node Group - r5.large only
resource "aws_eks_node_group" "user_small" {
  count = var.use_three_node_groups ? 1 : 0

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-user-small"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.user_node_subnet_ids != null ? var.user_node_subnet_ids : var.subnet_ids

  instance_types = ["r5.large"] # Small profile: 2 vCPU, 16 GiB
  capacity_type  = var.user_enable_spot_instances ? "SPOT" : "ON_DEMAND"
  ami_type       = "AL2023_x86_64_STANDARD"

  scaling_config {
    desired_size = var.user_node_desired_size
    max_size     = var.user_node_max_size
    min_size     = var.user_node_min_size
  }

  update_config {
    max_unavailable_percentage = 33
  }

  labels = {
    role = "user"
    size = "small"
    type = var.user_enable_spot_instances ? "spot" : "on-demand"
  }

  # No taint - user pods welcome here

  tags = merge(
    var.tags,
    {
      Name                                            = "${var.cluster_name}-user-small-node"
      "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      "k8s.io/cluster-autoscaler/enabled"             = "true"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_registry_policy
  ]
}

# User Medium Node Group - r5.xlarge only
resource "aws_eks_node_group" "user_medium" {
  count = var.use_three_node_groups ? 1 : 0

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-user-medium"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.user_node_subnet_ids != null ? var.user_node_subnet_ids : var.subnet_ids

  instance_types = ["r5.xlarge"] # Medium profile: 4 vCPU, 32 GiB
  capacity_type  = var.user_enable_spot_instances ? "SPOT" : "ON_DEMAND"
  ami_type       = "AL2023_x86_64_STANDARD"

  scaling_config {
    desired_size = var.user_node_desired_size
    max_size     = var.user_node_max_size
    min_size     = var.user_node_min_size
  }

  update_config {
    max_unavailable_percentage = 33
  }

  labels = {
    role = "user"
    size = "medium"
    type = var.user_enable_spot_instances ? "spot" : "on-demand"
  }

  # No taint - user pods welcome here

  tags = merge(
    var.tags,
    {
      Name                                            = "${var.cluster_name}-user-medium-node"
      "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      "k8s.io/cluster-autoscaler/enabled"             = "true"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_registry_policy
  ]
}

# Launch Template for Dask Worker Node Group (with NVMe mounting)
resource "aws_launch_template" "dask_workers" {
  name_prefix = "${var.cluster_name}-dask-"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 50 # Smaller root volume since we have NVMe
      volume_type = "gp3"
      encrypted   = true
    }
  }

  # User data script in MIME multipart format (required for EKS managed node groups)
  # NOTE: Do NOT call bootstrap.sh - EKS managed node groups handle this automatically
  user_data = base64encode(<<-EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="

--==MYBOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
set -ex

# DO NOT call /etc/eks/bootstrap.sh here - EKS managed node groups handle it automatically
# Mount NVMe storage and configure containerd to use it

echo "Starting NVMe mount and containerd configuration script for Dask worker..."

# Wait for NVMe devices to be available
sleep 5

# Find the NVMe device (not the root device)
NVME_DEVICE=$(lsblk -d -n | grep nvme | grep -v nvme0n1 | head -1 | awk '{print "/dev/"$1}')

if [ ! -z "$NVME_DEVICE" ]; then
  echo "Found NVMe device: $NVME_DEVICE"

  # Check if already formatted
  if ! blkid $NVME_DEVICE; then
    echo "Formatting $NVME_DEVICE with ext4..."
    mkfs -t ext4 $NVME_DEVICE
  fi

  # Mount to /mnt/nvme
  mkdir -p /mnt/nvme
  mount $NVME_DEVICE /mnt/nvme
  chmod 755 /mnt/nvme

  # Add to fstab for persistence
  if ! grep -q "$NVME_DEVICE" /etc/fstab; then
    echo "$NVME_DEVICE /mnt/nvme ext4 defaults,noatime 0 0" >> /etc/fstab
  fi

  # Create containerd directories on NVMe
  mkdir -p /mnt/nvme/containerd
  chmod 711 /mnt/nvme/containerd

  # Stop containerd before moving data
  systemctl stop containerd || true

  # Move existing containerd data if it exists and hasn't been moved yet
  if [ -d /var/lib/containerd ] && [ ! -L /var/lib/containerd ]; then
    echo "Moving existing containerd data to NVMe..."
    cp -a /var/lib/containerd/* /mnt/nvme/containerd/ 2>/dev/null || true
    mv /var/lib/containerd /var/lib/containerd.old
  fi

  # Create symlink from /var/lib/containerd to NVMe location
  ln -sf /mnt/nvme/containerd /var/lib/containerd

  # Restart containerd
  systemctl start containerd

  echo "NVMe successfully mounted and containerd configured to use it for Dask worker"
  df -h /mnt/nvme
  ls -la /var/lib/containerd
else
  echo "No NVMe device found - using default storage on root volume"
fi

--==MYBOUNDARY==--
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.tags,
      {
        Name = "${var.cluster_name}-dask-worker"
      }
    )
  }
}

# Dask Worker Node Group
resource "aws_eks_node_group" "dask_workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-dask-workers"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = var.dask_node_instance_types
  capacity_type  = var.dask_enable_spot_instances ? "SPOT" : "ON_DEMAND"
  ami_type       = "AL2023_x86_64_STANDARD"

  # Use the launch template with NVMe mounting script
  launch_template {
    id      = aws_launch_template.dask_workers.id
    version = "$Latest"
  }

  scaling_config {
    desired_size = var.dask_node_desired_size
    max_size     = var.dask_node_max_size
    min_size     = var.dask_node_min_size
  }

  update_config {
    max_unavailable_percentage = 33
  }

  labels = {
    role     = "dask-worker"
    type     = var.dask_enable_spot_instances ? "spot" : "on-demand"
    workload = "dask"
  }

  taint {
    key    = "lifecycle"
    value  = "spot"
    effect = "NO_EXECUTE"
  }

  tags = merge(
    var.tags,
    {
      Name                                            = "${var.cluster_name}-dask-worker-node"
      "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      "k8s.io/cluster-autoscaler/enabled"             = "true"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_registry_policy
  ]
}

# EKS Add-ons
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = var.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = var.tags

  depends_on = [
    aws_eks_node_group.main,
    aws_eks_node_group.system
  ]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = var.tags

  depends_on = [
    aws_eks_node_group.main,
    aws_eks_node_group.system
  ]
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = var.tags

  depends_on = [
    aws_eks_pod_identity_association.ebs_csi_driver,
    aws_eks_node_group.system
  ]
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = var.tags

  depends_on = [
    aws_eks_node_group.system
  ]
}

# EBS CSI Driver IAM Role for Pod Identity
resource "aws_iam_role" "ebs_csi_driver" {
  name = "${var.cluster_name}-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# EBS CSI Driver Pod Identity Association
resource "aws_eks_pod_identity_association" "ebs_csi_driver" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi_driver.arn

  depends_on = [
    aws_eks_addon.pod_identity
  ]
}

# Cluster Autoscaler IRSA
module "cluster_autoscaler_irsa" {
  source = "../irsa"

  cluster_name      = var.cluster_name
  oidc_provider_arn = aws_iam_openid_connect_provider.cluster.arn
  namespace         = "kube-system"
  service_account   = "cluster-autoscaler"

  policy_statements = [
    {
      Effect = "Allow"
      Action = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:GetInstanceTypesFromInstanceRequirements",
        "eks:DescribeNodegroup"
      ]
      Resource = "*"
    },
    {
      Effect = "Allow"
      Action = [
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ]
      Resource = "*"
      Condition = {
        StringEquals = {
          "autoscaling:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
        }
      }
    }
  ]

  tags = var.tags
}

# User Node Group Scheduled Scaling
# Scales up user node groups during business hours (e.g., 8am-5pm PT Mon-Fri)
# Uses AWS Auto Scaling Scheduled Actions with timezone support

# Schedule for scaling up user-small nodes during business hours
resource "aws_autoscaling_schedule" "user_small_scale_up" {
  count = var.use_three_node_groups && var.enable_user_node_scheduling ? 1 : 0

  scheduled_action_name  = "${var.cluster_name}-user-small-scale-up"
  autoscaling_group_name = aws_eks_node_group.user_small[0].resources[0].autoscaling_groups[0].name
  min_size               = var.user_node_schedule_min_size_during_hours
  max_size               = var.user_node_max_size
  desired_capacity       = var.user_node_schedule_min_size_during_hours
  recurrence             = var.user_node_schedule_scale_up_cron
  time_zone              = var.user_node_schedule_timezone
}

# Schedule for scaling down user-small nodes after hours
resource "aws_autoscaling_schedule" "user_small_scale_down" {
  count = var.use_three_node_groups && var.enable_user_node_scheduling ? 1 : 0

  scheduled_action_name  = "${var.cluster_name}-user-small-scale-down"
  autoscaling_group_name = aws_eks_node_group.user_small[0].resources[0].autoscaling_groups[0].name
  min_size               = var.user_node_schedule_min_size_after_hours
  max_size               = var.user_node_max_size
  desired_capacity       = var.user_node_schedule_min_size_after_hours
  recurrence             = var.user_node_schedule_scale_down_cron
  time_zone              = var.user_node_schedule_timezone
}

# Schedule for scaling up user-medium nodes during business hours
resource "aws_autoscaling_schedule" "user_medium_scale_up" {
  count = var.use_three_node_groups && var.enable_user_node_scheduling ? 1 : 0

  scheduled_action_name  = "${var.cluster_name}-user-medium-scale-up"
  autoscaling_group_name = aws_eks_node_group.user_medium[0].resources[0].autoscaling_groups[0].name
  min_size               = var.user_node_schedule_min_size_during_hours
  max_size               = var.user_node_max_size
  desired_capacity       = var.user_node_schedule_min_size_during_hours
  recurrence             = var.user_node_schedule_scale_up_cron
  time_zone              = var.user_node_schedule_timezone
}

# Schedule for scaling down user-medium nodes after hours
resource "aws_autoscaling_schedule" "user_medium_scale_down" {
  count = var.use_three_node_groups && var.enable_user_node_scheduling ? 1 : 0

  scheduled_action_name  = "${var.cluster_name}-user-medium-scale-down"
  autoscaling_group_name = aws_eks_node_group.user_medium[0].resources[0].autoscaling_groups[0].name
  min_size               = var.user_node_schedule_min_size_after_hours
  max_size               = var.user_node_max_size
  desired_capacity       = var.user_node_schedule_min_size_after_hours
  recurrence             = var.user_node_schedule_scale_down_cron
  time_zone              = var.user_node_schedule_timezone
}