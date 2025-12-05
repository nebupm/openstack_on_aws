# openstack_on_aws

An openstack all in one setup in an AWS instance

## After the instance is running, you can use the following commands to set up Kolla-Ansible

### Update Packages
sudo apt-get update && apt-get upgrade -y
sudo apt install -y git python3-dev libffi-dev gcc libssl-dev libdbus-glib-1-dev 

### Create a python Virtual Env.
python3-venv
python3 -m venv pyenv
source pyenv/bin/activate
cd pyenv/
pip install -U pip
pip install git+https://opendev.org/openstack/kolla-ansible@master
sudo mkdir -p /etc/kolla
sudo chown $USER:$USER /etc/kolla
ll /etc/kolla
which kolla-ansible
sudo cp share/kolla-ansible/etc_examples/kolla/* /etc/kolla/.
ll /etc/kolla/
sudo cp share/kolla-ansible/ansible/inventory/all-in-one ../.
kolla-ansible install-deps --become
kolla-genpwd
cat "/etc/kolla/passwords.yml"
pip install docker
pip install dbus-python

### Edit /etc/kolla/globals.yml to set the network interface.
Details are here : https://docs.openstack.org/kolla-ansible/latest/user/quickstart-development.html

### Once all is done, Its time.

kolla-ansible bootstrap-servers -i ./all-in-one --become
kolla-ansible prechecks -i ./all-in-one --become
kolla-ansible deploy -i ./all-in-one --become

### Install openstack client.

pip install python-openstackclient -c https://releases.openstack.org/constraints/upper/master
kolla-ansible post-deploy --become -i ./all-in-one

### Add firewall rules.
sudo iptables -L -n
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -L -n

### Source the admin credentials.action
/etc/kolla/admin-openrc.sh

### Setup some basic infrastructure.action 
./share/kolla-ansible/init-runonce
openstack server create --image cirros --flavor m1.tiny --key-name mykey --network demo-net demo1
openstack server list
Access Horizon at http://<VM public_ip>:8080
