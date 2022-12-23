#!/bin/bash

ORACLE_HOME="/u01/app/oracle/product/19.3/db_home"
TMP_HOME=/home/oracle
BACKUP=/orabackup/ORA_DM
ORA_DATA=/oradata/ORA_DM
S3B=DevOps/rman_backups

set -ex

# install required packages
sudo yum update -y
sudo yum install -y yum-utils oracle-database-preinstall-19c epel-release jq

# download & install aws cli
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
/usr/local/bin/aws s3 cp s3://fount-data/DevOps/oracle_bash_profile $TMP_HOME/.bash_profile
/usr/local/bin/aws s3 cp s3://fount-data/DevOps/LINUX.X64_193000_db_home.zip $TMP_HOME
/usr/local/bin/aws s3 cp s3://fount-data/DevOps/oracle_silent_install $TMP_HOME
/usr/local/bin/aws s3 cp s3://fount-data/DevOps/tnsnames.ora $TMP_HOME
/usr/local/bin/aws s3 cp s3://fount-data/DevOps/listener.ora $TMP_HOME
chmod +x $TMP_HOME/oracle_silent_install
chown oracle:oinstall $TMP_HOME/.bash_profile
sed -i "s/_HOSTNAME_/$HOSTNAME/g" $TMP_HOME/tnsnames.ora
sed -i "s/_HOSTNAME_/$HOSTNAME/g" $TMP_HOME/listener.ora

# install oracle 19c as oracle user
echo "change to oracle user"
sudo -i -u oracle bash <<EOF
        source $TMP_HOME/.bash_profile
        echo $ORACLE_HOME
        mv $TMP_HOME/LINUX.X64_193000_db_home.zip $ORACLE_HOME
        cd $ORACLE_HOME
        unzip -qo LINUX.X64_193000_db_home.zip
        sh $TMP_HOME/oracle_silent_install
				exit 0
EOF

# configure and change ownership
echo "done running as oracle user"
sudo /u01/app/oraInventory/orainstRoot.sh
sudo $ORACLE_HOME/root.sh
mv $TMP_HOME/*.ora $ORACLE_HOME/network/admin
# add port rule to firewall
firewall-cmd --zone=public --add-port=1521/tcp --permanent
firewall-cmd --reload
mkdir -p $BACKUP/archivelogs $BACKUP/autobackup
mkdir -p $ORA_DATA/controlfile $ORA_DATA/datafile
mkdir -p $ORACLE_HOME/admin/ora_dm/adump
chown -R oracle:oinstall $ORACLE_HOME/admin/ora_dm/adump
chown -R oracle:oinstall $BACKUP
chown -R oracle:oinstall $ORA_DATA

# use aws cli to get latest backup directory on s3
newest_file=$(/usr/local/bin/aws s3api list-objects-v2 \
--bucket fount-data \
--prefix $S3B/ \
--query 'sort_by(Contents, &LastModified)[-1]' | jq -r '.Key')
echo $newest_file
echo

newest_folder=$(echo $newest_file | sed -E "s|$S3B||g" | awk -F/ '{print FS $2}')
echo $newest_folder # contains '/' already
echo

# download newest backup
/usr/local/bin/aws s3 cp s3://fount-data/$S3B$newest_folder $BACKUP/autobackup$newest_folder --recursive
mv $BACKUP/autobackup$newest_folder/spfileorcl_dm.ora $ORACLE_HOME/dbs/
mkdir -p $BACKUP/archivelogs/$DATE
mv $BACKUP/autobackup$newest_folder/archivelogs/* $BACKUP/archivelogs/$DATE

# startup
sudo -i -u oracle bash <<EOF
sqlplus / as sysdba <<EOL
  startup NOMOUNT pfile=$ORACLE_HOME/dbs/spfileorcl_dm.ora;
  exit
EOL
EOF

# RMAN commands
sudo -i -u oracle bash <<EOF
rman target / <<EOL
  restore controlfile from '${BACKUP}/autobackup${newest_folder}/ctlfile_1.ctl';
  alter database mount;
  crosscheck backup;
  delete noprompt expired backup;
  catalog start with '${BACKUP}/archivelogs$newest_folder' noprompt;
  crosscheck archivelog all;
  change archivelog all validate;
  restore database;
  recover database;
  exit
EOL
EOF

# alter db & test
sudo -i -u oracle bash <<EOF
sqlplus / as sysdba <<'EOL'
  alter database open resetlogs;
  alter system set log_archive_dest_1 = 'location=${BACKUP}/archivelogs';
  select name, open_mode from v\$database;
  select * from c\$pinpoint.reg_data fetch next 1 rows only;
  exit
EOL
EOF

# start listener
sudo -i -u oracle bash <<< 'lsnrctl start'

echo "complete!"
