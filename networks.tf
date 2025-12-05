#########################################################
#This will create a VPC, Subnets, IGW, Routing tables and Security Groups.
#########################################################
# VARIABLES
#########################################################
# VPC and Networking Variables
variable "vpc_name" {
  type        = string
  description = "VPC Name"
  default     = "main-vpc-kolla"
}
variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR values"
  default     = "10.0.0.0/16"
}

variable "igw_name" {
  type        = string
  description = "Internet Gateway Name"
  default     = "igw"
}

#########################################################
# NETWORK RESOURCES
#########################################################
# Setup main vpc
resource "aws_vpc" "this_vpc" {
  cidr_block = var.vpc_cidr
  tags       = { Name = var.vpc_name }
}

# Management Subnet (for eth0)
resource "aws_subnet" "mgmnt_subnet" {
  vpc_id                  = aws_vpc.this_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = { Name = "${var.vpc_name}-mgmnt-subnet" }
}

# External/Public Subnet (for eth1 - Neutron external interface)
resource "aws_subnet" "extnl_subnet" {
  vpc_id            = aws_vpc.this_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = aws_subnet.mgmnt_subnet.availability_zone

  tags = { Name = "${var.vpc_name}-extnl-subnet" }
}


resource "aws_internet_gateway" "this_igw" {
  vpc_id = aws_vpc.this_vpc.id
  tags   = { Name = "${var.vpc_name}-igw" }
}

# Route table for management subnet
resource "aws_route_table" "management_rt" {
  vpc_id = aws_vpc.this_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this_igw.id
  }

  tags = { Name = "${var.vpc_name}-mgmnt-rt" }
}

resource "aws_route_table_association" "management_rt_association" {
  subnet_id      = aws_subnet.mgmnt_subnet.id
  route_table_id = aws_route_table.management_rt.id
}

resource "aws_security_group" "this_sg" {
  name        = "${var.vpc_name}-kolla-ansible-sg"
  description = "Security group for Kolla-Ansible OpenStack deployment in ${var.vpc_name}"
  vpc_id      = aws_vpc.this_vpc.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["82.16.60.106/32"]
    description = "SSH access"
  }
  # Horizon Dashboard
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["82.16.60.106/32"]
    description = "HTTP for Horizon"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["82.16.60.106/32"]
    description = "HTTPS for Horizon"
  }

  # OpenStack APIs (common ports)
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Keystone API"
  }

  ingress {
    from_port   = 8774
    to_port     = 8774
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Nova API"
  }

  ingress {
    from_port   = 9696
    to_port     = 9696
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Neutron API"
  }

  # All traffic within VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Internal VPC traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.vpc_name}-ec2-inst-sg" }
}

# Secondary Network Interface (eth1 - Neutron External)
resource "aws_network_interface" "secondary_nic" {
  subnet_id         = aws_subnet.extnl_subnet.id
  security_groups   = [aws_security_group.this_sg.id]
  private_ips       = ["10.0.2.10"]
  source_dest_check = false # Important for OpenStack networking

  tags = {
    Name = "kolla-secondary-nic"
  }
}

# Elastic IP for primary interface
resource "aws_eip" "kolla_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.this_igw]

  tags = {
    Name = "kolla-ansible-eip"
  }
}


#########################################################
# OUTPUTS - VPC and SUBNETS
#########################################################

output "vpc_name" {
  description = "Details of the main VPC"
  value       = aws_vpc.this_vpc.tags.Name
}

output "public_subnet_name" {
  description = "Details of the main public subnet"
  value       = aws_subnet.mgmnt_subnet.tags.Name
}

output "vpc_id" {
  value = aws_vpc.this_vpc.id
}
