#! /bin/sh
export DATE=$(date +%Y_%m_%d)
export TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
export ORACLE_HOME=/u01/app/oracle/product/19.3/db_home
export ORACLE_SID=orcl_dm
export PATH=$PATH:$ORACLE_HOME/bin
BACKUP='/orabackup/ORA_DM'
S3B=DevOps/rman_backups

fullbackup() {
	mkdir -p $BACKUP/archivelogs/$DATE
	rman log=$BACKUP/bkpscripts/b_$DATE_full_bkp.log <<EOF

connect target /

set echo on;

run
{

backup incremental level 0 
cumulative device type disk 
format '${BACKUP}/autobackup/${DATE}/%U.bkp'
tag 'ORA_DM' database;
backup device type disk tag 'ORA_DM' 
format = '${BACKUP}/archivelogs/${DATE}/%d_%u' 
archivelog all not backed up delete all input;
delete noprompt obsolete device type disk;
backup as copy current controlfile format '${BACKUP}/autobackup/${DATE}/ctlfile_%c.ctl'; 
}
exit
EOF
}

pfile() {
	sqlplus / as sysdba <<EOF
		create spfile='${BACKUP}/autobackup/${DATE}/spfileorcl_dm.ora' from pfile='${ORACLE_HOME}/dbs/spfileorcl_dm.ora';
		exit
EOF
}

uploadbackup() {
	check=$(/usr/local/bin/aws s3api list-objects-v2 --bucket fount-data --prefix "${S3B}/${DATE}" --query 'Contents[]')
	first_string=$(echo $check | awk '{print $1}')
	echo $first_string
	[[ $first_string == 'null' ]] && {
		echo "creating prefix (folder) ${DATE}"
		/usr/local/bin/aws s3api put-object --bucket fount-data --key $S3B/$DATE/archivelogs
	}
	# upoad files to s3
	/usr/local/bin/aws s3 cp $BACKUP/autobackup/$DATE s3://fount-data/$S3B/$DATE/ --recursive --exclude 'o1_*'
	/usr/local/bin/aws s3 cp $BACKUP/archivelogs/$DATE s3://fount-data/$S3B/$DATE/archivelogs/ --recursive
	# tag backups
	for file in $BACKUP/autobackup/$DATE/*; do
		/usr/local/bin/aws s3api put-object-tagging \
			--bucket fount-data \
			--key $S3B/$DATE/$(basename $file) \
			--tagging '{"TagSet": [{ "Key": "Name", "Value": "RMAN" }]}'
	done
	# tag archivelogs
	for file in $BACKUP/archivelogs/$DATE/*; do
		/usr/local/bin/aws s3api put-object-tagging \
			--bucket fount-data \
			--key $S3B/$DATE/$(basename $file) \
			--tagging '{"TagSet": [{ "Key": "Name", "Value": "RMAN" }]}'
	done
}

#MAIN
pfile
fullbackup
uploadbackup