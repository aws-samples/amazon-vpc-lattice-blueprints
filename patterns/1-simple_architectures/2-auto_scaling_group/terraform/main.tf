/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/2-auto_scaling_group/terraform/main.tf ---

# Data source: Amazon VPC Lattice prefix list (IPv4 and IPv6)
data "aws_ec2_managed_prefix_list" "vpclattice_pl_ipv4" {
  name = "com.amazonaws.${var.aws_region}.vpc-lattice"
}

data "aws_ec2_managed_prefix_list" "vpclattice_pl_ipv6" {
  name = "com.amazonaws.${var.aws_region}.ipv6.vpc-lattice"
}

# ---------- VPC LATTICE RESOURCES ----------
# VPC Lattice service network
module "service_network" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    name      = "service-network-${var.identifier}"
    auth_type = "NONE"
  }
}

# VPC Lattice service - VPC Lattice-generated FQDN, HTTPS listener, Instance type target
module "service" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    identifier = module.service_network.service_network.id
  }

  services = {
    service = {
      name      = "service-${var.identifier}"
      auth_type = "NONE"

      listeners = {
        https = {
          protocol = "HTTPS"
          port     = "443"
          default_action_forward = {
            target_groups = {
              asgtarget = { weight = 100 }
            }
          }
        }
      }
    }
  }

  target_groups = {
    asgtarget = {
      type = "INSTANCE"
      config = {
        port             = 80
        protocol         = "HTTP"
        vpc_identifier   = module.provider_vpc.vpc_attributes.id
        protocol_version = "HTTP1"
      }
      health_check = {
        enabled = true
      }
    }
  }
}

# ---------- CONSUMER VPC AND EC2 INSTANCES ----------
module "consumer_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.7.3"

  name                                 = "consumer-vpc-${var.identifier}"
  cidr_block                           = var.vpc.cidr_block
  vpc_assign_generated_ipv6_cidr_block = true
  az_count                             = var.vpc.number_azs

  vpc_lattice = {
    service_network_identifier = module.service_network.service_network.id
    security_group_ids         = [aws_security_group.vpclattice_sg.id]
  }

  subnets = {
    workload = {
      netmask          = var.vpc.private_subnet_netmask
      assign_ipv6_cidr = true
    }
    endpoints = {
      netmask          = var.vpc.endpoints_subnet_netmask
      assign_ipv6_cidr = true
    }
  }
}

module "consumer_instances" {
  source = "../../../tf_modules/consumer_instance"

  identifier      = var.identifier
  vpc_name        = "consumer-vpc"
  vpc             = module.consumer_vpc
  vpc_information = var.vpc
}

# Security Group (VPC Lattice VPC association)
resource "aws_security_group" "vpclattice_sg" {
  name        = "consumer-vpc-vpclattice-security-group-${var.identifier}"
  description = "VPC Lattice Security Group"
  vpc_id      = module.consumer_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_instances_https" {
  security_group_id = aws_security_group.vpclattice_sg.id

  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.consumer_instances.consumer_sg
}

# ---------- PROVIDER VPC AND EC2 INSTANCES ----------
module "provider_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "= 4.7.3"

  name                                 = "provider-vpc-${var.identifier}"
  cidr_block                           = var.vpc.cidr_block
  vpc_assign_generated_ipv6_cidr_block = true
  vpc_egress_only_internet_gateway     = true
  az_count                             = var.vpc.number_azs

  subnets = {
    workload = {
      netmask          = var.vpc.private_subnet_netmask
      assign_ipv6_cidr = true
      connect_to_eigw  = true
    }
  }
}

# EC2 Instance Security Group
resource "aws_security_group" "provider_instance_sg" {
  name        = "provider-vpc-instance-security-group-${var.identifier}"
  description = "EC2 Instance Security Group"
  vpc_id      = module.provider_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_http_ipv4" {
  security_group_id = aws_security_group.provider_instance_sg.id

  from_port      = 80
  to_port        = 80
  ip_protocol    = "tcp"
  prefix_list_id = data.aws_ec2_managed_prefix_list.vpclattice_pl_ipv4.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_http_ipv6" {
  security_group_id = aws_security_group.provider_instance_sg.id

  from_port      = 80
  to_port        = 80
  ip_protocol    = "tcp"
  prefix_list_id = data.aws_ec2_managed_prefix_list.vpclattice_pl_ipv6.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_https_ipv4" {
  security_group_id = aws_security_group.provider_instance_sg.id

  from_port      = 443
  to_port        = 443
  ip_protocol    = "tcp"
  prefix_list_id = data.aws_ec2_managed_prefix_list.vpclattice_pl_ipv4.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_https_ipv6" {
  security_group_id = aws_security_group.provider_instance_sg.id

  from_port      = 443
  to_port        = 443
  ip_protocol    = "tcp"
  prefix_list_id = data.aws_ec2_managed_prefix_list.vpclattice_pl_ipv6.id
}

resource "aws_vpc_security_group_egress_rule" "provider_allowing_egress_any" {
  security_group_id = aws_security_group.provider_instance_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "provider_allowing_egress_any_ipv6" {
  security_group_id = aws_security_group.provider_instance_sg.id

  ip_protocol = "-1"
  cidr_ipv6   = "::/0"
}

# Data resource to determine the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# Launch Template
resource "aws_launch_template" "launch_template_webinstance" {
  name_prefix   = "web-template-${var.identifier}"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.vpc.instance_type

  network_interfaces {
    associate_public_ip_address = false
    ipv6_address_count          = 1
    security_groups             = [aws_security_group.provider_instance_sg.id]
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      encrypted = true
    }
  }

  user_data = base64encode(<<-EOF
#!/bin/bash
# Update system and install httpd
sudo yum update -y
sudo yum install -y httpd php
sudo systemctl start httpd
sudo systemctl enable httpd
sudo chown -R $USER:$USER /var/www

# Create index.php to show request source IP
cat > /var/www/html/index.php <<'HTML'
<html>
<body>
<h1>Hello from the AutoScaling Group!!</h1>
<p><strong>Request IP address:</strong> <?php echo $_SERVER['REMOTE_ADDR']; ?></p>
</body>
</html>
HTML
EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "provider-instance-${var.identifier}"
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "web_asg" {
  name                = "web-asg-${var.identifier}"
  vpc_zone_identifier = values({ for k, v in module.provider_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })

  min_size         = 2
  max_size         = 2
  desired_capacity = 2

  launch_template {
    id      = aws_launch_template.launch_template_webinstance.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "web-asg-${var.identifier}"
    propagate_at_launch = true
  }
}

# Autoscaling group association to VPC Lattice target group
resource "aws_autoscaling_traffic_source_attachment" "asg_target_vpclattice" {
  autoscaling_group_name = aws_autoscaling_group.web_asg.id

  traffic_source {
    identifier = module.service.target_groups.asgtarget.arn
    type       = "vpc-lattice"
  }
}