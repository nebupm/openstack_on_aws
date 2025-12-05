#########################################################
# VARIABLES
#########################################################
# EC2 Linux Instance Variables
variable "create_linux_ec2" {
  description = "Whether to create the Linux EC2 instance"
  type        = bool
  default     = true
}

variable "kolla_instance_type" {
  type        = string
  description = "EC2 Linux Instance Type"
  default     = "t3.large"
}
variable "kolla_instance_ami" {
  type        = string
  description = "EC2 Instance Amazon Linux 2023 AMI"
  #default     = "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  # Corresponds to Ubuntu 24.04 LTS
  default = "ami-0838acf0030c73b79"
}
variable "kolla_instance_name" {
  type        = string
  description = "Name of the EC2 instance"
  default     = "kolla-ansible-inst"
}
variable "linux_ebs_volume_size_gb" {
  description = "Size of the EBS volume in GB"
  type        = number
  default     = 4
}

variable "linux_enable_public_ip_address" {
  type        = bool
  description = "Whether to enable a public IP address for the Linux EC2 instance"
  default     = true
}
# Setup EC2 instance
#########################################################
# EC2 INSTANCE
#########################################################
# Setup Key Pair
resource "aws_key_pair" "this_linux_keypair" {
  key_name   = "linux-ec2-instance-keypair"
  public_key = file("../../ec2_all_keys/aws-ec2-linux-instance-public-key.pub")
}

# Setup EC2 instance
resource "aws_instance" "kolla_instance" {
  count         = var.create_linux_ec2 ? 1 : 0
  ami           = var.kolla_instance_ami
  instance_type = var.kolla_instance_type

  # Primary network interface
  subnet_id              = aws_subnet.mgmnt_subnet.id
  vpc_security_group_ids = [aws_security_group.this_sg.id]
  private_ip             = "10.0.1.10"

  root_block_device {
    volume_size           = 50 # 50GB for OpenStack
    volume_type           = "gp3"
    delete_on_termination = true
  }
  key_name          = aws_key_pair.this_linux_keypair.key_name
  availability_zone = aws_subnet.mgmnt_subnet.availability_zone

  user_data = <<-EOF
#!/bin/bash
set -e
exec > /var/log/user-data.log 2>&1
set -x
# Wait for network interfaces to be available
sleep 30
# Find the second network interface (excluding lo and the primary interface)
PRIMARY_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
SECOND_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo\|$PRIMARY_IFACE" | head -n1)

if [ -z "$SECOND_IFACE" ]; then
  echo "ERROR: Could not find second network interface"
  exit 1
fi

echo "Primary interface: $PRIMARY_IFACE"
echo "Second interface: $SECOND_IFACE"

# Bring up the second interface
ip link set dev $SECOND_IFACE up

# Create netplan configuration for the second interface
cat > /etc/netplan/60-second-nic.yaml <<NETPLAN
network:
  version: 2
  ethernets:
    $SECOND_IFACE:
      dhcp4: false
      dhcp6: false
NETPLAN
chmod 600 /etc/netplan/60-second-nic.yaml
# Apply netplan configuration
netplan apply
ip addr
# Create a helper file with interface names for easy reference
cat > /root/kolla-interfaces.txt <<INTERFACES
Primary interface (network_interface): $PRIMARY_IFACE
Secondary interface (neutron_external_interface): $SECOND_IFACE

Use these values in /etc/kolla/globals.yml:
network_interface: "$PRIMARY_IFACE"
neutron_external_interface: "$SECOND_IFACE"
INTERFACES
echo "Network configuration completed successfully"
EOF
  tags      = { Name = var.kolla_instance_name }
}

# Attach secondary NIC to instance
resource "aws_network_interface_attachment" "secondary_attachment" {
  count                = var.create_linux_ec2 ? 1 : 0
  instance_id          = aws_instance.kolla_instance[count.index].id
  network_interface_id = aws_network_interface.secondary_nic.id
  device_index         = 1
  depends_on = [
    aws_instance.kolla_instance,
    aws_network_interface.secondary_nic
  ]
}

# Associate Elastic IP with the instance
resource "aws_eip_association" "eip_assoc" {
  count         = var.create_linux_ec2 ? 1 : 0
  instance_id   = aws_instance.kolla_instance[count.index].id
  allocation_id = aws_eip.kolla_eip.id
}



#########################################################
# OUTPUTS
#########################################################
# EC2 Instance details

output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.kolla_instance[0].id
}

output "public_ip" {
  description = "Public IP address"
  value       = aws_eip.kolla_eip.public_ip
}

output "private_ip_secondary" {
  description = "Secondary NIC private IP"
  value       = aws_network_interface.secondary_nic.private_ip
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh -i /path/to/your-key.pem ubuntu@${aws_eip.kolla_eip.public_ip}"
}

###################################################################################################
# After the instance is running, you can use the following commands to set up Kolla-Ansible
###################################################################################################
# echo "Updating packages"
# sudo apt-get update && apt-get upgrade -y
# sudo apt install -y git python3-dev libffi-dev gcc libssl-dev libdbus-glib-1-dev python3-venv
# python3 -m venv pyenv
# source pyenv/bin/activate
# cd pyenv/
# pip install -U pip
# pip install git+https://opendev.org/openstack/kolla-ansible@master
# sudo mkdir -p /etc/kolla
# echo "User : $USER"
# sudo chown $USER:$USER /etc/kolla
# ll /etc/kolla
# which kolla-ansible
# sudo cp share/kolla-ansible/etc_examples/kolla/* /etc/kolla/.
# ll /etc/kolla/
# sudo cp share/kolla-ansible/ansible/inventory/all-in-one ../.
# kolla-ansible install-deps --become

# kolla-genpwd
# cat "/etc/kolla/passwords.yml"
# clear
# grep -v "^#" /etc/kolla/globals.yml | grep -v "^$"
# pip install docker
# pip install dbus-python

# kolla-ansible bootstrap-servers -i ./all-in-one --become
# kolla-ansible prechecks -i ./all-in-one --become
# kolla-ansible deploy -i ./all-in-one --become
# pip install python-openstackclient -c https://releases.openstack.org/constraints/upper/master
# kolla-ansible post-deploy --become -i ./all-in-one