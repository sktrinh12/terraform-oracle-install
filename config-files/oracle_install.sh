#!/bin/bash

ORACLE_HOME="/u01/app/oracle/product/19.3/db_home"
TMP_HOME=/home/oracle

set -ex
sudo yum update -y
sudo yum install -y yum-utils oracle-database-preinstall-19c 
cd /tmp
curl -LJO "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
unzip awscli-exe-linux-x86_64.zip
sudo ./aws/install
eval "echo \"oracle  ALL=(ALL) NOPASSWD:ALL\" | tee \"/etc/sudoers.d/oracle\""
sudo rm awscli-exe-linux-x86_64.zip
mkdir -p $ORACLE_HOME
chown -R oracle:oinstall /u01
chmod -R 775 /u01
rm -f $TMP_HOME/.bash_profile
aws s3 cp s3://fount-data/DevOps/oracle_bash_profile $TMP_HOME/.bash_profile
aws s3 cp s3://fount-data/DevOps/LINUX.X64_193000_db_home.zip .
aws s3 cp s3://fount-data/DevOps/oracle_silent_install $TMP_HOME
aws s3 cp s3://fount-data/DevOps/tnsnames.ora $TMP_HOME
aws s3 cp s3://fount-data/DevOps/listener.ora $TMP_HOME
chmod +x $TMP_HOME/oracle_silent_install
sed -i "s/_HOSTNAME_/$HOSTNAME/g" $TMP_HOME/tnsnames.ora
sed -i "s/_HOSTNAME_/$HOSTNAME/g" $TMP_HOME/listener.ora

echo "change to oracle user"
sudo -i -u oracle bash <<EOF
        source $TMP_HOME/.bash_profile
        echo $ORACLE_HOME
        mv $TMP_HOME/LINUX.X64_193000_db_home.zip $ORACLE_HOME
        cd $ORACLE_HOME
        unzip -qo LINUX.X64_193000_db_home.zip
        sh $TMP_HOME/oracle_silent_install
EOF

echo "done running as oracle user"
/u01/app/oraInventory/orainstRoot.sh
$ORACLE_HOME/root.sh
mv $TMP_HOME/*.ora $ORACLE_HOME/network/admin
