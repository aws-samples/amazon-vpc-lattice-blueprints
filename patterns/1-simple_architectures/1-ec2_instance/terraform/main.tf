/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0 */

# --- patterns/1-simple_architectures/1-ec2_instance/terraform/main.tf ---

# Data source: AWS Region
data "aws_region" "region" {}

# Data source: Amazon VPC Lattice prefix list (IPv4 and IPv6)
data "aws_ec2_managed_prefix_list" "vpclattice_pl_ipv4" {
  name = "com.amazonaws.${data.aws_region.region.region}.vpc-lattice"
}

data "aws_ec2_managed_prefix_list" "vpclattice_pl_ipv6" {
  name = "com.amazonaws.${data.aws_region.region.region}.ipv6.vpc-lattice"
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

# ---------- VPC LATTICE ACCESS LOGGING ----------
# CloudWatch Logs log group (access logs destination)
resource "aws_cloudwatch_log_group" "vpclattice_access_logs" {
  name              = "/aws/vpclattice/${var.identifier}"
  retention_in_days = 7
}

# Access log subscription (service network scope - covers all associated services)
resource "aws_vpclattice_access_log_subscription" "service_network_access_logs" {
  resource_identifier = module.service_network.service_network.arn
  destination_arn     = aws_cloudwatch_log_group.vpclattice_access_logs.arn
}

# VPC Lattice service1 - VPC Lattice-generated FQDN, HTTPS listener, EC2 instance targets
module "service1" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    identifier = module.service_network.service_network.id
  }

  services = {
    service1 = {
      name      = "service1-${var.identifier}"
      auth_type = "NONE"

      listeners = {
        https = {
          protocol = "HTTPS"
          port     = "443"
          default_action_forward = {
            target_groups = {
              instancetarget = { weight = 100 }
            }
          }
        }
      }
    }
  }

  target_groups = {
    instancetarget = {
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
      targets = {
        instance1 = {
          id   = aws_instance.web_instance[0].id
          port = 80
        }
        instance2 = {
          id   = aws_instance.web_instance[1].id
          port = 80
        }
      }
    }
  }
}

# VPC Lattice service2 - Custom domain name, HTTPS listener, IPv4 & IPv6 targets
module "service2" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "= 1.1.0"

  service_network = {
    identifier = module.service_network.service_network.id
  }

  services = {
    service2 = {
      name               = "service2-${var.identifier}"
      auth_type          = "NONE"
      custom_domain_name = var.custom_domain_name
      certificate_arn    = var.certificate_arn
      hosted_zone_id     = aws_route53_zone.private_hosted_zone.id

      listeners = {
        https = {
          protocol = "HTTPS"
          port     = "443"
          default_action_forward = {
            target_groups = {
              ipv4target = { weight = 50 }
              ipv6target = { weight = 50 }
            }
          }
        }
      }
    }
  }

  target_groups = {
    ipv4target = {
      type = "IP"
      config = {
        port             = 80
        protocol         = "HTTP"
        vpc_identifier   = module.provider_vpc.vpc_attributes.id
        ip_address_type  = "IPV4"
        protocol_version = "HTTP1"
      }
      health_check = {
        enabled = true
      }
      targets = {
        ip1 = {
          id   = data.aws_instance.web_instance[0].private_ip
          port = 80
        }
        ip2 = {
          id   = data.aws_instance.web_instance[1].private_ip
          port = 80
        }
      }
    }

    ipv6target = {
      type = "IP"
      config = {
        port             = 80
        protocol         = "HTTP"
        vpc_identifier   = module.provider_vpc.vpc_attributes.id
        ip_address_type  = "IPV6"
        protocol_version = "HTTP1"
      }
      health_check = {
        enabled = true
      }
      targets = {
        ip1 = {
          id   = tolist(data.aws_instance.web_instance[0].ipv6_addresses)[0]
          port = 80
        }
        ip2 = {
          id   = tolist(data.aws_instance.web_instance[1].ipv6_addresses)[0]
          port = 80
        }
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

# Private Hosted Zone
resource "aws_route53_zone" "private_hosted_zone" {
  name = var.hosted_zone_name

  vpc {
    vpc_id = module.consumer_vpc.vpc_attributes.id
  }
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
    endpoints = {
      netmask          = var.vpc.endpoints_subnet_netmask
      assign_ipv6_cidr = true
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

resource "aws_instance" "web_instance" {
  count = var.vpc.number_azs

  ami                         = data.aws_ami.amazon_linux.id
  associate_public_ip_address = false
  ipv6_address_count          = 1
  instance_type               = var.vpc.instance_type
  vpc_security_group_ids      = [aws_security_group.provider_instance_sg.id]
  subnet_id                   = values({ for k, v in module.provider_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })[count.index]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<-EOF
#!/bin/bash
# Update system and install httpd
sudo yum update -y
sudo yum install -y httpd php

# Ensure httpd listens on both IPv4 and IPv6
# Remove any existing Listen directives and add explicit ones
sudo sed -i '/^Listen /d' /etc/httpd/conf/httpd.conf
echo "Listen 0.0.0.0:80" | sudo tee -a /etc/httpd/conf/httpd.conf
echo "Listen [::]:80" | sudo tee -a /etc/httpd/conf/httpd.conf

sudo systemctl start httpd
sudo systemctl enable httpd
sudo chown -R $USER:$USER /var/www

# Create index.php to show request source IP
cat > /var/www/html/index.php <<'HTML'
<html>
<body>
<h1>Hello from EC2 instance</h1>
<p><strong>Request IP address:</strong> <?php echo $_SERVER['REMOTE_ADDR']; ?></p>
</body>
</html>
HTML
EOF

  tags = {
    Name = "provider-vpc-instance-${count.index + 1}-${var.identifier}"
  }
}

# Data source: EC2 Instance (to obtain IPv4 and IPv6 addresses)
data "aws_instance" "web_instance" {
  count = var.vpc.number_azs

  instance_id = aws_instance.web_instance[count.index].id
}
